extends GutTest
## Slice 145 (Phase 16, F-037): the pre-auth version handshake contract
## (`shared/version_handshake.gd`). The server decides; the client only declares.
## Every non-acceptable case must be refused, and an operator misconfiguration
## must never be reported as the player's client being outdated. See
## docs/slices/145-version-handshake-contract.md.

const VersionHandshakeScript: Script = preload("res://shared/version_handshake.gd")
const ClientBuildVersionScript: Script = preload("res://shared/client_build_version.gd")

const MANIFEST_URL: String = "https://enrollment.example/patches"


func after_each() -> void:
	# These are process-wide; leaking one would silently retune later tests.
	OS.set_environment(VersionHandshakeScript.REQUIRED_VERSION_ENV_VAR, "")
	OS.set_environment(VersionHandshakeScript.MANIFEST_BASE_URL_ENV_VAR, "")


func _request(version: Variant) -> Dictionary:
	return {"schema_version": VersionHandshakeScript.SCHEMA_VERSION, "client_build_version": version}


func test_request_declares_this_builds_version() -> void:
	var request: Dictionary = VersionHandshakeScript.request()
	assert_eq(request["schema_version"], VersionHandshakeScript.SCHEMA_VERSION, "carries the handshake schema version")
	assert_eq(
		request["client_build_version"],
		ClientBuildVersionScript.current(),
		"declares the running client's own build version"
	)


func test_matching_version_is_accepted() -> void:
	var result: Dictionary = VersionHandshakeScript.evaluate(_request("1.2.3"), "1.2.3", MANIFEST_URL)
	assert_eq(result["outcome"], VersionHandshakeScript.OUTCOME_ACCEPTED, "an exact match is served")


func test_a_stock_server_accepts_its_own_client() -> void:
	var result: Dictionary = VersionHandshakeScript.evaluate(
		VersionHandshakeScript.request(), VersionHandshakeScript.resolve_required_version(), ""
	)
	assert_eq(result["outcome"], VersionHandshakeScript.OUTCOME_ACCEPTED, "default configuration serves its own client")


func test_mismatched_version_is_refused_with_patch_directions() -> void:
	var result: Dictionary = VersionHandshakeScript.evaluate(_request("1.2.3"), "1.3.0", MANIFEST_URL)
	assert_eq(result["outcome"], VersionHandshakeScript.OUTCOME_CLIENT_OUTDATED, "a mismatch is refused")
	assert_eq(result["required_version"], "1.3.0", "the rejection names the required version")
	assert_eq(result["manifest_base_url"], MANIFEST_URL, "the rejection points at the update manifest")


func test_an_older_or_newer_client_is_refused_identically() -> void:
	# Exact equality, not ordering: a "newer" client cannot argue its way in.
	for declared: String in ["1.2.9", "9.9.9"]:
		var result: Dictionary = VersionHandshakeScript.evaluate(_request(declared), "1.3.0", MANIFEST_URL)
		assert_eq(
			result["outcome"],
			VersionHandshakeScript.OUTCOME_CLIENT_OUTDATED,
			"%s is refused against 1.3.0" % declared
		)


func test_structurally_wrong_requests_are_malformed() -> void:
	var bad_requests: Array = [
		null,
		"1.2.3",
		[],
		{},
		{"client_build_version": "1.2.3"},
		{"schema_version": 999, "client_build_version": "1.2.3"},
	]
	for bad: Variant in bad_requests:
		var result: Dictionary = VersionHandshakeScript.evaluate(bad, "1.2.3", MANIFEST_URL)
		assert_eq(result["outcome"], VersionHandshakeScript.OUTCOME_MALFORMED, "refuses %s" % [bad])


func test_malformed_declared_versions_are_refused() -> void:
	for declared: Variant in [null, "", "1.2", "v1.2.3", "1.2.x", 123, "1.2.3-beta"]:
		var result: Dictionary = VersionHandshakeScript.evaluate(_request(declared), "1.2.3", MANIFEST_URL)
		assert_eq(
			result["outcome"],
			VersionHandshakeScript.OUTCOME_MALFORMED,
			"refuses declared version %s" % [declared]
		)


func test_a_rejection_never_leaks_the_manifest_url_to_an_accepted_or_malformed_case() -> void:
	var accepted: Dictionary = VersionHandshakeScript.evaluate(_request("1.2.3"), "1.2.3", MANIFEST_URL)
	assert_eq(accepted["manifest_base_url"], "", "an accepted client is told nothing about patching")
	var malformed: Dictionary = VersionHandshakeScript.evaluate("nonsense", "1.2.3", MANIFEST_URL)
	assert_eq(malformed["manifest_base_url"], "", "a malformed request gets no patch directions")


func test_operator_misconfiguration_is_not_blamed_on_the_client() -> void:
	for bad_required: String in ["", "not-a-version", "1.2", "v1.2.3"]:
		var result: Dictionary = VersionHandshakeScript.evaluate(_request("1.2.3"), bad_required, MANIFEST_URL)
		assert_eq(
			result["outcome"],
			VersionHandshakeScript.OUTCOME_SERVER_MISCONFIGURED,
			"required=%s is an operator fault, not CLIENT_OUTDATED" % bad_required
		)


func test_required_version_defaults_to_this_build() -> void:
	OS.set_environment(VersionHandshakeScript.REQUIRED_VERSION_ENV_VAR, "")
	assert_eq(
		VersionHandshakeScript.resolve_required_version(),
		ClientBuildVersionScript.current(),
		"an unset override serves this build's own client version"
	)


func test_valid_required_version_override_is_used() -> void:
	OS.set_environment(VersionHandshakeScript.REQUIRED_VERSION_ENV_VAR, "2.5.1")
	assert_eq(VersionHandshakeScript.resolve_required_version(), "2.5.1", "a valid override is honored")


func test_malformed_required_version_override_resolves_empty_so_callers_fail_closed() -> void:
	OS.set_environment(VersionHandshakeScript.REQUIRED_VERSION_ENV_VAR, "2.5")
	assert_eq(VersionHandshakeScript.resolve_required_version(), "", "a malformed override never silently falls back")


func test_manifest_base_url_must_be_https() -> void:
	OS.set_environment(VersionHandshakeScript.MANIFEST_BASE_URL_ENV_VAR, MANIFEST_URL)
	assert_eq(VersionHandshakeScript.resolve_manifest_base_url(), MANIFEST_URL, "an HTTPS URL is used")
	for insecure: String in ["http://enrollment.example/patches", "ftp://x/y", "enrollment.example", ""]:
		OS.set_environment(VersionHandshakeScript.MANIFEST_BASE_URL_ENV_VAR, insecure)
		assert_eq(
			VersionHandshakeScript.resolve_manifest_base_url(),
			"",
			"a non-HTTPS update source is never advertised: %s" % insecure
		)
