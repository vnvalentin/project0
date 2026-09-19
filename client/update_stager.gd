extends Node
class_name UpdateStager
## Slice 148 (Phase 16, F-037): fetches an update over HTTPS and stages it, but
## only ever hands back a patch it has PROVEN is the signed one.
##
## The staging boundary exists so unverified bytes never become the running
## client. Everything is written to a scratch directory under `user://`, verified
## through `UpdateManifest`, and the whole directory is destroyed on any failure —
## so a refused or interrupted update cannot leave a half-written pack lying
## around for the updater to pick up later.
##
## Transport is HTTPS-only and follows the same bounded `HTTPRequest` +
## `await request_completed` shape as `client/enrollment_http_client.gd`. TLS is
## required but is NOT the trust anchor (ADR 0008) — the signature is. A URL is
## therefore never trusted for *what* it returns, only for reaching a host.
##
## Client-only: the server never downloads or applies a client patch.

const UpdateManifestScript: Script = preload("res://shared/update_manifest.gd")

const DEFAULT_STAGING_DIR: String = "user://update_staging"
const MANIFEST_FILE: String = "manifest.json"
const SIGNATURE_FILE: String = "manifest.sig"
const STAGED_PATCH_FILE: String = "Project0.pck"
const DEFAULT_TIMEOUT_SEC: float = 60.0

const OUTCOME_OK: String = "ok"
const OUTCOME_INSECURE_URL: String = "insecure_url"
const OUTCOME_TRANSPORT_ERROR: String = "transport_error"
const OUTCOME_TIMEOUT: String = "timeout"
const OUTCOME_HTTP_ERROR: String = "http_error"
const OUTCOME_STAGING_UNAVAILABLE: String = "staging_unavailable"

const _HTTPS_PREFIX: String = "https://"

@export var request_timeout_sec: float = DEFAULT_TIMEOUT_SEC

var _http_request: HTTPRequest = null


func _ready() -> void:
	_http_request = HTTPRequest.new()
	_http_request.timeout = request_timeout_sec
	add_child(_http_request)


## The manifest and detached-signature URLs for a base URL. Returns "" for a
## non-HTTPS base so a plaintext update source can never even be addressed.
static func manifest_url(base_url: String) -> String:
	return _child_url(base_url, MANIFEST_FILE)


static func signature_url(base_url: String) -> String:
	return _child_url(base_url, SIGNATURE_FILE)


static func _child_url(base_url: String, file_name: String) -> String:
	var base: String = base_url.strip_edges().rstrip("/")
	if not base.begins_with(_HTTPS_PREFIX):
		return ""
	return "%s/%s" % [base, file_name]


## Verify already-fetched bytes and, only if they prove out, write the patch into
## the staging directory. Anything less than a full pass leaves NOTHING behind:
## the staging directory is destroyed before returning.
## Returns {outcome, detail, manifest, staged_path}.
static func stage_verified_patch(
	staging_dir: String,
	raw_manifest: PackedByteArray,
	signature: PackedByteArray,
	public_key_pem: String,
	patch_bytes: PackedByteArray
) -> Dictionary:
	var verified: Dictionary = UpdateManifestScript.verify_and_parse(raw_manifest, signature, public_key_pem)
	if verified["outcome"] != UpdateManifestScript.OUTCOME_OK:
		discard_staging(staging_dir)
		return _fail(verified["outcome"], verified["detail"])

	var manifest: Dictionary = verified["manifest"]
	if not _ensure_staging_dir(staging_dir):
		return _fail(OUTCOME_STAGING_UNAVAILABLE, "could not create staging directory: %s" % staging_dir)

	var staged_path: String = "%s/%s" % [staging_dir.rstrip("/"), STAGED_PATCH_FILE]
	var file := FileAccess.open(staged_path, FileAccess.WRITE)
	if file == null:
		discard_staging(staging_dir)
		return _fail(OUTCOME_STAGING_UNAVAILABLE, "could not write staged patch: %s" % staged_path)
	file.store_buffer(patch_bytes)
	file.close()

	# Verify what actually landed on disk, not what we believe we wrote.
	var patch_check: Dictionary = UpdateManifestScript.verify_patch_file(staged_path, manifest)
	if patch_check["outcome"] != UpdateManifestScript.OUTCOME_OK:
		discard_staging(staging_dir)
		return _fail(patch_check["outcome"], patch_check["detail"])

	return {
		"outcome": OUTCOME_OK,
		"detail": "",
		"manifest": manifest,
		"staged_path": staged_path,
	}


## Remove the staging directory and everything in it. Safe to call when it does
## not exist, so every failure path can end with an unconditional discard.
static func discard_staging(staging_dir: String) -> void:
	var absolute: String = ProjectSettings.globalize_path(staging_dir)
	var dir := DirAccess.open(staging_dir)
	if dir == null:
		return
	for file_name: String in dir.get_files():
		DirAccess.remove_absolute("%s/%s" % [absolute, file_name])
	DirAccess.remove_absolute(absolute)


## Fetch the manifest, its detached signature, and the patch over HTTPS, then
## stage the result through stage_verified_patch. The patch URL comes from the
## SIGNED manifest, so it is only followed after the manifest proves authentic.
## Coroutine; returns the same shape as stage_verified_patch.
func fetch_and_stage(base_url: String, public_key_pem: String, staging_dir: String = DEFAULT_STAGING_DIR) -> Dictionary:
	var manifest_address: String = manifest_url(base_url)
	var signature_address: String = signature_url(base_url)
	if manifest_address.is_empty() or signature_address.is_empty():
		return _fail(OUTCOME_INSECURE_URL, "update source must be an https URL")

	var manifest_bytes: Dictionary = await _fetch(manifest_address)
	if manifest_bytes["outcome"] != OUTCOME_OK:
		return _fail(manifest_bytes["outcome"], manifest_bytes["detail"])
	var signature_bytes: Dictionary = await _fetch(signature_address)
	if signature_bytes["outcome"] != OUTCOME_OK:
		return _fail(signature_bytes["outcome"], signature_bytes["detail"])

	# Peek only to learn where the pack lives; the bytes are still untrusted until
	# stage_verified_patch re-verifies the signature over them below.
	var peeked: Dictionary = UpdateManifestScript.verify_and_parse(
		manifest_bytes["body"], signature_bytes["body"], public_key_pem
	)
	if peeked["outcome"] != UpdateManifestScript.OUTCOME_OK:
		return _fail(peeked["outcome"], peeked["detail"])

	var patch_address: String = String((peeked["manifest"] as Dictionary)["pck_url"])
	var patch_bytes: Dictionary = await _fetch(patch_address)
	if patch_bytes["outcome"] != OUTCOME_OK:
		return _fail(patch_bytes["outcome"], patch_bytes["detail"])

	return stage_verified_patch(
		staging_dir, manifest_bytes["body"], signature_bytes["body"], public_key_pem, patch_bytes["body"]
	)


## One bounded HTTPS GET. Returns {outcome, detail, body}.
func _fetch(url: String) -> Dictionary:
	if not url.begins_with(_HTTPS_PREFIX):
		return {"outcome": OUTCOME_INSECURE_URL, "detail": "refusing non-https url", "body": PackedByteArray()}
	var error: Error = _http_request.request(url)
	if error != OK:
		return {"outcome": OUTCOME_TRANSPORT_ERROR, "detail": "request failed to start", "body": PackedByteArray()}
	var response: Array = await _http_request.request_completed
	var result_code: int = response[0]
	var status: int = response[1]
	if result_code == HTTPRequest.RESULT_TIMEOUT:
		return {"outcome": OUTCOME_TIMEOUT, "detail": "request timed out", "body": PackedByteArray()}
	if result_code != HTTPRequest.RESULT_SUCCESS:
		return {"outcome": OUTCOME_TRANSPORT_ERROR, "detail": "transport result %d" % result_code, "body": PackedByteArray()}
	if status < 200 or status >= 300:
		return {"outcome": OUTCOME_HTTP_ERROR, "detail": "http status %d" % status, "body": PackedByteArray()}
	return {"outcome": OUTCOME_OK, "detail": "", "body": response[3] as PackedByteArray}


static func _ensure_staging_dir(staging_dir: String) -> bool:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(staging_dir)):
		return true
	return DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(staging_dir)) == OK


static func _fail(outcome: String, detail: String) -> Dictionary:
	return {"outcome": outcome, "detail": detail, "manifest": null, "staged_path": ""}
