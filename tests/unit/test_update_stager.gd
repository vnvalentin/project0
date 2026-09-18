extends GutTest
## Slice 148 (Phase 16, F-037): update staging (`client/update_stager.gd`). The
## property that matters is negative: a refused update must leave NOTHING on
## disk for the updater to find later, and a patch is only ever staged after it
## proves out against the signed manifest. Uses real RSA keys and real files.
## See docs/slices/148-https-update-staging.md.

const UpdateStagerScript: Script = preload("res://client/update_stager.gd")
const UpdateManifestScript: Script = preload("res://shared/update_manifest.gd")

const STAGING_DIR: String = "user://test_update_staging"

var _crypto: Crypto
var _key: CryptoKey
var _public_pem: String
var _patch_bytes: PackedByteArray


func before_all() -> void:
	_crypto = Crypto.new()
	_key = _crypto.generate_rsa(3072)
	_public_pem = _key.save_to_string(true)
	_patch_bytes = "pretend this is a whole Project0.pck".to_utf8_buffer()


func after_each() -> void:
	UpdateStagerScript.discard_staging(STAGING_DIR)


func _digest_of(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


func _manifest_bytes(overrides: Dictionary = {}) -> PackedByteArray:
	var manifest: Dictionary = {
		"schema_version": 1,
		"required_client_version": "0.7.0",
		"pck_sha256": _digest_of(_patch_bytes),
		"pck_url": "https://enrollment.example/patches/0.7.0/Project0.pck",
		"size_bytes": _patch_bytes.size(),
	}
	for key: String in overrides:
		manifest[key] = overrides[key]
	return JSON.stringify(manifest).to_utf8_buffer()


func _sign(raw: PackedByteArray) -> PackedByteArray:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(raw)
	return _crypto.sign(HashingContext.HASH_SHA256, context.finish(), _key)


func _staging_is_empty() -> bool:
	return not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(STAGING_DIR))


func test_urls_are_derived_from_an_https_base() -> void:
	assert_eq(
		UpdateStagerScript.manifest_url("https://enroll.example/patches/"),
		"https://enroll.example/patches/manifest.json",
		"trailing slash is normalized"
	)
	assert_eq(
		UpdateStagerScript.signature_url("https://enroll.example/patches"),
		"https://enroll.example/patches/manifest.sig",
		"signature sits beside the manifest"
	)


func test_a_plaintext_base_url_cannot_even_be_addressed() -> void:
	for insecure: String in ["http://enroll.example/patches", "ftp://x/y", "enroll.example", ""]:
		assert_eq(UpdateStagerScript.manifest_url(insecure), "", "refuses to address %s" % insecure)
		assert_eq(UpdateStagerScript.signature_url(insecure), "", "refuses to address %s" % insecure)


func test_a_genuine_update_is_staged_and_verified() -> void:
	var raw: PackedByteArray = _manifest_bytes()
	var result: Dictionary = UpdateStagerScript.stage_verified_patch(
		STAGING_DIR, raw, _sign(raw), _public_pem, _patch_bytes
	)
	assert_eq(result["outcome"], UpdateStagerScript.OUTCOME_OK, "genuine update stages: %s" % result["detail"])
	assert_true(FileAccess.file_exists(result["staged_path"]), "the verified patch is on disk")
	assert_eq(result["manifest"]["required_client_version"], "0.7.0", "the verified manifest comes back")


func test_a_tampered_manifest_stages_nothing() -> void:
	var raw: PackedByteArray = _manifest_bytes()
	var signature: PackedByteArray = _sign(raw)
	var tampered: PackedByteArray = _manifest_bytes({"pck_url": "https://evil.example/Project0.pck"})
	var result: Dictionary = UpdateStagerScript.stage_verified_patch(
		STAGING_DIR, tampered, signature, _public_pem, _patch_bytes
	)
	assert_eq(result["outcome"], UpdateManifestScript.OUTCOME_UNVERIFIED, "a tampered manifest is refused")
	assert_eq(result["staged_path"], "", "no staged path is handed back")
	assert_true(_staging_is_empty(), "nothing is left on disk for the updater to find")


func test_a_patch_that_does_not_match_the_signed_digest_is_discarded() -> void:
	# Manifest is genuinely signed, but the bytes delivered are not the ones it names.
	var raw: PackedByteArray = _manifest_bytes()
	var wrong_payload: PackedByteArray = "a different pack entirely".to_utf8_buffer()
	var result: Dictionary = UpdateStagerScript.stage_verified_patch(
		STAGING_DIR, raw, _sign(raw), _public_pem, wrong_payload
	)
	assert_ne(result["outcome"], UpdateStagerScript.OUTCOME_OK, "a substituted patch is refused")
	assert_true(_staging_is_empty(), "the bad patch is deleted, not left staged")


func test_a_foreign_key_stages_nothing() -> void:
	var raw: PackedByteArray = _manifest_bytes()
	var foreign_pem: String = _crypto.generate_rsa(3072).save_to_string(true)
	var result: Dictionary = UpdateStagerScript.stage_verified_patch(
		STAGING_DIR, raw, _sign(raw), foreign_pem, _patch_bytes
	)
	assert_eq(result["outcome"], UpdateManifestScript.OUTCOME_UNVERIFIED, "only the trusted key stages an update")
	assert_true(_staging_is_empty(), "nothing is left behind")


func test_staging_a_second_time_replaces_the_first() -> void:
	var raw: PackedByteArray = _manifest_bytes()
	assert_eq(
		UpdateStagerScript.stage_verified_patch(STAGING_DIR, raw, _sign(raw), _public_pem, _patch_bytes)["outcome"],
		UpdateStagerScript.OUTCOME_OK,
		"first staging succeeds"
	)
	var result: Dictionary = UpdateStagerScript.stage_verified_patch(
		STAGING_DIR, raw, _sign(raw), _public_pem, _patch_bytes
	)
	assert_eq(result["outcome"], UpdateStagerScript.OUTCOME_OK, "re-staging the same update is not an error")


func test_discard_is_safe_when_nothing_is_staged() -> void:
	UpdateStagerScript.discard_staging(STAGING_DIR)
	UpdateStagerScript.discard_staging(STAGING_DIR)
	assert_true(_staging_is_empty(), "discarding an absent staging directory is a no-op")
