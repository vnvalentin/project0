extends RefCounted
class_name PasswordHasher
## Slice 040: server-only PBKDF2-HMAC-SHA256 password hashing on Godot
## `Crypto` (see .scratch/player-accounts/handoff-040-account-auth-session.md
## and docs/slices/040-account-auth-session.md). Per CLAUDE.md's Shared
## Contracts / Runtime Ownership rules, this class MUST NEVER be referenced
## from `shared/` or `client/` — it is a server-only secret-handling seam.
##
## Exposes a pure, synchronous, unit-testable core (hash_password/
## verify_password below). The RPC-facing caller (server auth logic) is
## responsible for running these off the main thread via WorkerThreadPool so a
## slow hash can never stall the authoritative simulation tick — this class
## itself does no threading, matching the "pure core, caller drives execution
## context" seam style already used elsewhere in this codebase.
##
## Never logs, stores, or returns a plaintext password. Salt/hash bytes are
## hex-encoded Strings so they round-trip cleanly through SQLite TEXT columns
## (see server/account_character_repository.gd's pbkdf2_salt/pbkdf2_hash
## columns) and JSON/telemetry boundaries without ever needing raw bytes to
## cross a serialization seam.

const SALT_BYTES: int = 16
const KEY_BYTES: int = 32
const DEFAULT_ITERATIONS: int = 100000


## Public seam. Derives a new PBKDF2-HMAC-SHA256 key for `password` using a
## fresh 16-byte CSPRNG salt (Crypto.generate_random_bytes) and `iterations`
## rounds of HMAC-SHA256. Returns hex-encoded salt/hash strings plus the
## iteration count actually used, so the caller can persist all three
## alongside the account row (schema: pbkdf2_salt, pbkdf2_hash,
## pbkdf2_iterations).
static func hash_password(password: String, iterations: int = DEFAULT_ITERATIONS) -> Dictionary:
	var crypto := Crypto.new()
	var salt: PackedByteArray = crypto.generate_random_bytes(SALT_BYTES)
	var derived: PackedByteArray = _derive(password, salt, iterations)
	return {
		"salt": salt.hex_encode(),
		"hash": derived.hex_encode(),
		"iterations": iterations,
	}


## Public seam. Recomputes the PBKDF2 derivation for `password` against the
## stored `salt_hex`/`iterations` and compares it to `hash_hex` using
## Crypto.constant_time_compare, so the comparison itself leaks no timing
## signal about how many leading bytes matched.
static func verify_password(password: String, salt_hex: String, hash_hex: String, iterations: int) -> bool:
	if salt_hex.is_empty() or hash_hex.is_empty() or iterations <= 0:
		return false
	var salt: PackedByteArray = salt_hex.hex_decode()
	var expected: PackedByteArray = hash_hex.hex_decode()
	var actual: PackedByteArray = _derive(password, salt, iterations)
	if actual.size() != expected.size():
		return false
	var crypto := Crypto.new()
	return crypto.constant_time_compare(actual, expected)


## PBKDF2-HMAC-SHA256 core (RFC 8018), built on Crypto.hmac_digest as the PRF.
## Produces exactly KEY_BYTES of derived key material, concatenating as many
## 32-byte HMAC-SHA256 blocks (T_1, T_2, ...) as needed and truncating the
## final block — standard PBKDF2 block construction.
static func _derive(password: String, salt: PackedByteArray, iterations: int) -> PackedByteArray:
	var password_bytes: PackedByteArray = password.to_utf8_buffer()
	var crypto := Crypto.new()
	var derived := PackedByteArray()
	var block_index: int = 1
	while derived.size() < KEY_BYTES:
		var block: PackedByteArray = _derive_block(crypto, password_bytes, salt, iterations, block_index)
		derived.append_array(block)
		block_index += 1
	derived.resize(KEY_BYTES)
	return derived


## One PBKDF2 block: U_1 = HMAC(password, salt || INT_32_BE(block_index)),
## U_n = HMAC(password, U_(n-1)), T = U_1 XOR U_2 XOR ... XOR U_iterations.
static func _derive_block(crypto: Crypto, password_bytes: PackedByteArray, salt: PackedByteArray, iterations: int, block_index: int) -> PackedByteArray:
	var salt_with_index: PackedByteArray = salt.duplicate()
	salt_with_index.append((block_index >> 24) & 0xFF)
	salt_with_index.append((block_index >> 16) & 0xFF)
	salt_with_index.append((block_index >> 8) & 0xFF)
	salt_with_index.append(block_index & 0xFF)

	var u_key: PackedByteArray = password_bytes
	var u: PackedByteArray = crypto.hmac_digest(HashingContext.HASH_SHA256, u_key, salt_with_index)
	var result: PackedByteArray = u.duplicate()

	for _i in range(iterations - 1):
		u = crypto.hmac_digest(HashingContext.HASH_SHA256, u_key, u)
		for byte_index in range(result.size()):
			result[byte_index] = result[byte_index] ^ u[byte_index]

	return result
