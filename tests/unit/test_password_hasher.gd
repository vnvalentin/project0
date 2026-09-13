extends GutTest
## Headless public-seam test for Slice 040's server-only PBKDF2-HMAC-SHA256
## password hasher (server/password_hasher.gd). Security-critical: proves the
## KDF itself is correct against a published known-answer test vector, not
## just that round-trip verification is internally self-consistent. See
## .scratch/player-accounts/handoff-040-account-auth-session.md and
## docs/slices/040-account-auth-session.md.

const PasswordHasherScript: Script = preload("res://server/password_hasher.gd")

## Published PBKDF2-HMAC-SHA256 test vector (password="password", salt="salt",
## 1 iteration, derived key length 32 bytes) — reproduced by CPython's stdlib
## hashlib.pbkdf2_hmac("sha256", b"password", b"salt", 1, 32) and widely cited
## as a PBKDF2-HMAC-SHA256 known-answer vector (an SHA-256 extension of the
## RFC 6070 PBKDF2-HMAC-SHA1 vector family).
const KAT_PASSWORD: String = "password"
const KAT_SALT_HEX: String = "73616c74" # "salt"
const KAT_ITERATIONS: int = 1
const KAT_EXPECTED_HEX: String = "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b"

# A second published vector at 2 iterations, same password/salt, proving the
# iteration count actually changes the output (not just returning U_1).
const KAT_ITERATIONS_2: int = 2
const KAT_EXPECTED_HEX_2: String = "ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43"


func test_known_answer_vector_reproduces_expected_derived_key() -> void:
	var salt_bytes: PackedByteArray = KAT_SALT_HEX.hex_decode()
	var derived: PackedByteArray = PasswordHasherScript._derive(KAT_PASSWORD, salt_bytes, KAT_ITERATIONS)
	assert_eq(derived.hex_encode(), KAT_EXPECTED_HEX, "PBKDF2-HMAC-SHA256(password, salt, 1, 32) must match the published KAT")


func test_known_answer_vector_at_two_iterations() -> void:
	var salt_bytes: PackedByteArray = KAT_SALT_HEX.hex_decode()
	var derived: PackedByteArray = PasswordHasherScript._derive(KAT_PASSWORD, salt_bytes, KAT_ITERATIONS_2)
	assert_eq(derived.hex_encode(), KAT_EXPECTED_HEX_2, "PBKDF2-HMAC-SHA256(password, salt, 2, 32) must match the published KAT")


func test_hash_password_produces_16_byte_salt_and_32_byte_key() -> void:
	var result: Dictionary = PasswordHasherScript.hash_password("correct horse battery staple", 1000)
	var salt: PackedByteArray = (result["salt"] as String).hex_decode()
	var derived: PackedByteArray = (result["hash"] as String).hex_decode()
	assert_eq(salt.size(), PasswordHasherScript.SALT_BYTES, "salt is 16 bytes")
	assert_eq(derived.size(), PasswordHasherScript.KEY_BYTES, "derived key is 32 bytes")
	assert_eq(result["iterations"], 1000, "the requested iteration count is stored with the record")


func test_verify_password_accepts_correct_and_rejects_wrong_password() -> void:
	var result: Dictionary = PasswordHasherScript.hash_password("s3cret!", 1000)
	assert_true(
		PasswordHasherScript.verify_password("s3cret!", result["salt"], result["hash"], result["iterations"]),
		"the correct password verifies"
	)
	assert_false(
		PasswordHasherScript.verify_password("wrong-password", result["salt"], result["hash"], result["iterations"]),
		"an incorrect password does not verify"
	)


func test_two_hashes_of_the_same_password_use_distinct_salts_and_hashes() -> void:
	var first: Dictionary = PasswordHasherScript.hash_password("same-password", 1000)
	var second: Dictionary = PasswordHasherScript.hash_password("same-password", 1000)
	assert_ne(first["salt"], second["salt"], "each hash_password call draws a fresh CSPRNG salt")
	assert_ne(first["hash"], second["hash"], "distinct salts produce distinct stored hashes for the same password")
	# Both still independently verify against their own record.
	assert_true(PasswordHasherScript.verify_password("same-password", first["salt"], first["hash"], first["iterations"]))
	assert_true(PasswordHasherScript.verify_password("same-password", second["salt"], second["hash"], second["iterations"]))


func test_hash_password_is_deterministic_given_the_same_salt_and_iterations() -> void:
	# hash_password itself always draws a fresh salt, so determinism is proven
	# at the pure _derive core: the same password+salt+iterations must always
	# reproduce the same derived key (no hidden randomness beyond the salt).
	var salt_bytes: PackedByteArray = PasswordHasherScript.hash_password("determinism-check", 500)["salt"].hex_decode()
	var first: PackedByteArray = PasswordHasherScript._derive("determinism-check", salt_bytes, 500)
	var second: PackedByteArray = PasswordHasherScript._derive("determinism-check", salt_bytes, 500)
	assert_eq(first.hex_encode(), second.hex_encode(), "same salt+password+iterations must derive the same key every time")


func test_verify_password_rejects_malformed_or_empty_stored_record() -> void:
	assert_false(PasswordHasherScript.verify_password("anything", "", "", 0), "an empty salt/hash/iterations record never verifies")
	assert_false(PasswordHasherScript.verify_password("anything", "aa", "bb", -1), "a negative iteration count never verifies")
