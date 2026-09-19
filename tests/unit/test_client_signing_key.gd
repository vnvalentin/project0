extends GutTest
## Slice 150 (Phase 16, F-037): the embedded trusted release key
## (`shared/client_signing_key.gd`). This is the client's entire basis for
## trusting an update, so the tests assert it is actually loadable, actually
## matches its recorded fingerprint, and actually rejects a foreign signer.
## See docs/slices/150-trusted-signing-key.md.

const ClientSigningKeyScript: Script = preload("res://shared/client_signing_key.gd")
const UpdateManifestScript: Script = preload("res://shared/update_manifest.gd")


func test_the_shipped_key_is_usable() -> void:
	assert_true(
		ClientSigningKeyScript.is_configured(),
		"a build whose trusted key does not load could never verify an update"
	)


func test_the_shipped_key_matches_its_recorded_fingerprint() -> void:
	# Guards against a key being swapped without the fingerprint (and reviewer
	# attention) moving with it.
	var key := CryptoKey.new()
	assert_eq(key.load_from_string(ClientSigningKeyScript.TRUSTED_PUBLIC_KEY_PEM, true), OK, "key loads")
	# Line-wise so the digest is identical under LF and CRLF checkouts.
	var base64: String = ""
	for line: String in ClientSigningKeyScript.TRUSTED_PUBLIC_KEY_PEM.split("\n"):
		var trimmed: String = line.strip_edges()
		if trimmed.is_empty() or trimmed.begins_with("-----"):
			continue
		base64 += trimmed
	var der: PackedByteArray = Marshalls.base64_to_raw(base64)
	assert_gt(der.size(), 0, "the embedded PEM body decodes as base64")
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(der)
	assert_eq(
		ctx.finish().hex_encode(),
		ClientSigningKeyScript.TRUSTED_KEY_FINGERPRINT,
		"the embedded key is the one the fingerprint names"
	)


func test_the_shipped_key_is_public_only() -> void:
	# A private key in the pack would let any tester forge an update.
	assert_false(
		ClientSigningKeyScript.TRUSTED_PUBLIC_KEY_PEM.contains("PRIVATE KEY"),
		"only public key material may ship in the client"
	)


func test_a_foreign_key_cannot_pass_as_the_trusted_signer() -> void:
	var crypto := Crypto.new()
	var foreign: CryptoKey = crypto.generate_rsa(3072)
	var raw: PackedByteArray = '{"schema_version":1}'.to_utf8_buffer()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(raw)
	var signature: PackedByteArray = crypto.sign(HashingContext.HASH_SHA256, ctx.finish(), foreign)

	var result: Dictionary = UpdateManifestScript.verify_and_parse(
		raw, signature, ClientSigningKeyScript.trusted_public_key_pem()
	)
	assert_eq(
		result["outcome"],
		UpdateManifestScript.OUTCOME_UNVERIFIED,
		"a manifest signed by anyone else is refused"
	)
