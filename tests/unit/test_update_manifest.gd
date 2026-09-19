extends GutTest
## Slice 147 (Phase 16, F-037): the signed update manifest verifier
## (`shared/update_manifest.gd`). This is remote code delivery, so the tests that
## matter are the refusals: a tampered manifest, a foreign key, and a patch that
## does not match its signed digest must never be accepted. Uses REAL RSA keys
## generated in-test, so the production verify path is exercised, not a double.
## See docs/slices/147-signed-update-manifest.md.

const UpdateManifestScript: Script = preload("res://shared/update_manifest.gd")

var _crypto: Crypto
var _key: CryptoKey
var _public_pem: String
var _foreign_public_pem: String
var _written_paths: Array[String] = []


func before_all() -> void:
	_crypto = Crypto.new()
	# 3072 matches the production key size decided in ADR 0008.
	_key = _crypto.generate_rsa(3072)
	_public_pem = _key.save_to_string(true)
	_foreign_public_pem = _crypto.generate_rsa(3072).save_to_string(true)


func after_each() -> void:
	for path: String in _written_paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_written_paths.clear()


func _manifest_json(overrides: Dictionary = {}) -> String:
	var manifest: Dictionary = {
		"schema_version": 1,
		"required_client_version": "0.7.0",
		"pck_sha256": "0".repeat(64),
		"pck_url": "https://enrollment.example/patches/0.7.0/Project0.pck",
		"size_bytes": 1024,
	}
	for key: String in overrides:
		manifest[key] = overrides[key]
	return JSON.stringify(manifest)


func _sign(raw: PackedByteArray) -> PackedByteArray:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(raw)
	return _crypto.sign(HashingContext.HASH_SHA256, context.finish(), _key)


func _write_file(name: String, bytes: PackedByteArray) -> String:
	var path: String = "user://%s" % name
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	_written_paths.append(path)
	return path


func test_a_correctly_signed_manifest_is_accepted_and_parsed() -> void:
	var raw: PackedByteArray = _manifest_json().to_utf8_buffer()
	var result: Dictionary = UpdateManifestScript.verify_and_parse(raw, _sign(raw), _public_pem)
	assert_eq(result["outcome"], UpdateManifestScript.OUTCOME_OK, "genuine manifest verifies: %s" % result["detail"])
	assert_eq(result["manifest"]["required_client_version"], "0.7.0", "parsed the required version")
	assert_eq(result["manifest"]["size_bytes"], 1024, "parsed the size")


func test_a_tampered_manifest_is_refused() -> void:
	var raw: PackedByteArray = _manifest_json().to_utf8_buffer()
	var signature: PackedByteArray = _sign(raw)
	# Same signature, one byte of the document changed — the attack this exists for.
	var tampered: PackedByteArray = _manifest_json({"pck_url": "https://evil.example/Project0.pck"}).to_utf8_buffer()
	var result: Dictionary = UpdateManifestScript.verify_and_parse(tampered, signature, _public_pem)
	assert_eq(result["outcome"], UpdateManifestScript.OUTCOME_UNVERIFIED, "a tampered manifest never verifies")
	assert_null(result["manifest"], "and nothing is handed back to read")


func test_a_foreign_key_cannot_sign_an_update() -> void:
	var raw: PackedByteArray = _manifest_json().to_utf8_buffer()
	var result: Dictionary = UpdateManifestScript.verify_and_parse(raw, _sign(raw), _foreign_public_pem)
	assert_eq(result["outcome"], UpdateManifestScript.OUTCOME_UNVERIFIED, "only the trusted key is accepted")


func test_empty_signature_or_document_is_refused() -> void:
	var raw: PackedByteArray = _manifest_json().to_utf8_buffer()
	assert_eq(
		UpdateManifestScript.verify_and_parse(raw, PackedByteArray(), _public_pem)["outcome"],
		UpdateManifestScript.OUTCOME_UNVERIFIED,
		"an absent signature is not a pass"
	)
	assert_eq(
		UpdateManifestScript.verify_and_parse(PackedByteArray(), _sign(raw), _public_pem)["outcome"],
		UpdateManifestScript.OUTCOME_UNVERIFIED,
		"an empty document is not a pass"
	)


func test_an_unusable_trusted_key_is_an_operator_fault_not_a_rejection() -> void:
	var raw: PackedByteArray = _manifest_json().to_utf8_buffer()
	for bad_key: String in ["", "not a pem"]:
		var result: Dictionary = UpdateManifestScript.verify_and_parse(raw, _sign(raw), bad_key)
		assert_eq(
			result["outcome"],
			UpdateManifestScript.OUTCOME_KEY_UNUSABLE,
			"an unusable key is reported as such, never as a verified update"
		)


func test_signed_but_structurally_invalid_manifests_are_refused() -> void:
	var cases: Dictionary = {
		"unsupported schema": {"schema_version": 99},
		"bad version": {"required_client_version": "1.2"},
		"short digest": {"pck_sha256": "abc"},
		"uppercase digest": {"pck_sha256": "A".repeat(64)},
		"plaintext url": {"pck_url": "http://enrollment.example/Project0.pck"},
		"zero size": {"size_bytes": 0},
		"negative size": {"size_bytes": -5},
	}
	for label: String in cases:
		var raw: PackedByteArray = _manifest_json(cases[label]).to_utf8_buffer()
		var result: Dictionary = UpdateManifestScript.verify_and_parse(raw, _sign(raw), _public_pem)
		assert_ne(result["outcome"], UpdateManifestScript.OUTCOME_OK, "refuses %s even though it is signed" % label)
		assert_null(result["manifest"], "no manifest is returned for %s" % label)


func test_signed_non_json_is_refused() -> void:
	var raw: PackedByteArray = "this is not json".to_utf8_buffer()
	var result: Dictionary = UpdateManifestScript.verify_and_parse(raw, _sign(raw), _public_pem)
	assert_eq(result["outcome"], UpdateManifestScript.OUTCOME_MALFORMED, "a signed non-document is still refused")


func test_a_patch_matching_its_signed_digest_is_accepted() -> void:
	var payload: PackedByteArray = "pretend this is Project0.pck".to_utf8_buffer()
	var path: String = _write_file("test_patch_ok.bin", payload)
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(payload)
	var manifest: Dictionary = {"pck_sha256": context.finish().hex_encode(), "size_bytes": payload.size()}
	var result: Dictionary = UpdateManifestScript.verify_patch_file(path, manifest)
	assert_eq(result["outcome"], UpdateManifestScript.OUTCOME_OK, "the genuine patch verifies: %s" % result["detail"])


func test_a_patch_with_the_wrong_contents_is_refused() -> void:
	var payload: PackedByteArray = "tampered payload".to_utf8_buffer()
	var path: String = _write_file("test_patch_bad.bin", payload)
	# Correct length, wrong bytes: size alone must not be treated as proof.
	var manifest: Dictionary = {"pck_sha256": "b".repeat(64), "size_bytes": payload.size()}
	var result: Dictionary = UpdateManifestScript.verify_patch_file(path, manifest)
	assert_eq(result["outcome"], UpdateManifestScript.OUTCOME_HASH_MISMATCH, "content is checked, not just length")


func test_a_patch_of_the_wrong_size_is_refused() -> void:
	var payload: PackedByteArray = "short".to_utf8_buffer()
	var path: String = _write_file("test_patch_size.bin", payload)
	var manifest: Dictionary = {"pck_sha256": "c".repeat(64), "size_bytes": 999999}
	var result: Dictionary = UpdateManifestScript.verify_patch_file(path, manifest)
	assert_eq(result["outcome"], UpdateManifestScript.OUTCOME_SIZE_MISMATCH, "a size mismatch is refused early")


func test_a_missing_patch_file_is_refused() -> void:
	var result: Dictionary = UpdateManifestScript.verify_patch_file("user://definitely_absent.bin", {
		"pck_sha256": "d".repeat(64), "size_bytes": 10,
	})
	assert_eq(result["outcome"], UpdateManifestScript.OUTCOME_UNREADABLE, "an absent patch is not a pass")
