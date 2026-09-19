extends RefCounted
class_name UpdateManifest
## Slice 147 (Phase 16, F-037): the signed update manifest — the only thing that
## makes a downloaded patch trustworthy. Auto-update is remote code delivery, so
## this is the security linchpin: nothing here may accept bytes it has not proven
## were signed by the release operator's offline key.
##
## Trust order matters. The signature is verified over the RAW manifest bytes
## exactly as received, BEFORE any parsing — never over a re-serialized copy.
## Re-serializing first is a classic signature bypass: two different byte strings
## can parse to the same object, so an attacker edits the bytes the program will
## actually read while the signature still checks out against a normalized form.
## Verify the bytes you were given, then read them.
##
## TLS is required for transport but is NOT the trust anchor (ADR 0008): it
## authenticates the host, not the artifact. The signature authenticates the
## artifact, and the signed `pck_sha256` then authenticates the patch itself.
##
## See `.scratch/client-auto-update/spec.md` and
## `docs/adr/0008-windows-client-delivery-trust-and-rollback.md`.

const ClientBuildVersionScript: Script = preload("res://shared/client_build_version.gd")

const SCHEMA_VERSION: int = 1

const OUTCOME_OK: String = "ok"
## The signature did not verify against the trusted key. Never applied.
const OUTCOME_UNVERIFIED: String = "unverified"
## The manifest is signed but structurally unusable.
const OUTCOME_MALFORMED: String = "malformed"
const OUTCOME_UNSUPPORTED_VERSION: String = "unsupported_version"
## The trusted public key itself is unusable \u2014 an operator fault, not an attack.
const OUTCOME_KEY_UNUSABLE: String = "key_unusable"
## The downloaded patch does not match the signed manifest.
const OUTCOME_HASH_MISMATCH: String = "hash_mismatch"
const OUTCOME_SIZE_MISMATCH: String = "size_mismatch"
const OUTCOME_UNREADABLE: String = "unreadable"

const _HASH_CHUNK_BYTES: int = 65536
const _SHA256_HEX_LENGTH: int = 64
const _HTTPS_PREFIX: String = "https://"


## Verify a detached signature over the raw manifest bytes with the trusted
## public key, then parse and validate. Fail-closed at every step; the returned
## manifest is only ever non-null on OUTCOME_OK, so a caller cannot accidentally
## read fields from an unverified document.
## Returns {outcome, detail, manifest}.
static func verify_and_parse(
	raw_bytes: PackedByteArray, signature: PackedByteArray, public_key_pem: String
) -> Dictionary:
	var key := CryptoKey.new()
	# Public-only: the client never holds the signing key.
	if public_key_pem.is_empty() or key.load_from_string(public_key_pem, true) != OK:
		return _fail(OUTCOME_KEY_UNUSABLE, "trusted public key could not be loaded")
	if raw_bytes.is_empty():
		return _fail(OUTCOME_UNVERIFIED, "empty manifest bytes")
	if signature.is_empty():
		return _fail(OUTCOME_UNVERIFIED, "empty signature")

	var digest: PackedByteArray = _sha256_of_bytes(raw_bytes)
	var crypto := Crypto.new()
	if not crypto.verify(HashingContext.HASH_SHA256, digest, signature, key):
		return _fail(OUTCOME_UNVERIFIED, "signature does not match the trusted key")

	# Only now are these bytes trustworthy enough to interpret.
	var parsed: Variant = JSON.parse_string(raw_bytes.get_string_from_utf8())
	if not (parsed is Dictionary):
		return _fail(OUTCOME_MALFORMED, "manifest is not a JSON object")
	return _validate(parsed as Dictionary)


## Structural validation of an already-verified manifest.
static func _validate(data: Dictionary) -> Dictionary:
	if int(data.get("schema_version", -1)) != SCHEMA_VERSION:
		return _fail(OUTCOME_UNSUPPORTED_VERSION, "unsupported manifest schema_version")

	var required_version: Variant = data.get("required_client_version")
	if not ClientBuildVersionScript.is_valid(required_version):
		return _fail(OUTCOME_MALFORMED, "required_client_version is missing or malformed")

	var sha: Variant = data.get("pck_sha256")
	if not (sha is String) or not _is_sha256_hex(sha as String):
		return _fail(OUTCOME_MALFORMED, "pck_sha256 is not a lowercase 64-character hex digest")

	var url: Variant = data.get("pck_url")
	if not (url is String) or not (url as String).begins_with(_HTTPS_PREFIX):
		return _fail(OUTCOME_MALFORMED, "pck_url must be an https URL")

	var size: Variant = data.get("size_bytes")
	if not (size is int or size is float) or int(size) <= 0:
		return _fail(OUTCOME_MALFORMED, "size_bytes must be a positive integer")

	return {
		"outcome": OUTCOME_OK,
		"detail": "",
		"manifest": {
			"schema_version": SCHEMA_VERSION,
			"required_client_version": String(required_version),
			"pck_sha256": String(sha),
			"pck_url": String(url),
			"size_bytes": int(size),
		},
	}


## Verify a downloaded patch against an already-verified manifest: exact byte
## size first (cheap, and it bounds the work), then a streamed SHA-256 so a
## multi-hundred-megabyte pack never has to be held in memory at once.
## Returns {outcome, detail, sha256}.
static func verify_patch_file(path: String, manifest: Dictionary) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _hash_fail(OUTCOME_UNREADABLE, "patch file does not exist: %s" % path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _hash_fail(OUTCOME_UNREADABLE, "patch file could not be opened: %s" % path)
	var actual_size: int = int(file.get_length())
	if actual_size != int(manifest.get("size_bytes", -1)):
		file.close()
		return _hash_fail(
			OUTCOME_SIZE_MISMATCH,
			"patch is %d bytes, signed manifest says %d" % [actual_size, int(manifest.get("size_bytes", -1))]
		)

	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	while not file.eof_reached():
		var chunk: PackedByteArray = file.get_buffer(_HASH_CHUNK_BYTES)
		if chunk.is_empty():
			break
		context.update(chunk)
	file.close()
	var actual_sha: String = context.finish().hex_encode()
	if actual_sha != String(manifest.get("pck_sha256", "")):
		return _hash_fail(OUTCOME_HASH_MISMATCH, "patch digest does not match the signed manifest")
	return {"outcome": OUTCOME_OK, "detail": "", "sha256": actual_sha}


static func _sha256_of_bytes(bytes: PackedByteArray) -> PackedByteArray:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish()


static func _is_sha256_hex(value: String) -> bool:
	if value.length() != _SHA256_HEX_LENGTH:
		return false
	for index: int in value.length():
		var c: String = value[index]
		if not ((c >= "0" and c <= "9") or (c >= "a" and c <= "f")):
			return false
	return true


static func _fail(outcome: String, detail: String) -> Dictionary:
	return {"outcome": outcome, "detail": detail, "manifest": null}


static func _hash_fail(outcome: String, detail: String) -> Dictionary:
	return {"outcome": outcome, "detail": detail, "sha256": ""}
