extends GutTest
## Slice 144 (Phase 16, F-037): the packaged client's own build version contract
## (`shared/client_build_version.gd`). The stamped constant is the identity the
## server-owned pre-auth version gate will compare against, so a malformed or
## decorated version must never validate. See
## docs/slices/144-client-build-version-stamp.md.

const ClientBuildVersionScript: Script = preload("res://shared/client_build_version.gd")


func test_current_returns_the_stamped_constant() -> void:
	assert_eq(
		ClientBuildVersionScript.current(),
		ClientBuildVersionScript.CLIENT_BUILD_VERSION,
		"the running client reports its stamped build version"
	)


func test_the_shipped_constant_is_a_well_formed_version() -> void:
	# Guards the stamp: a release must never ship a constant the gate would refuse.
	assert_true(
		ClientBuildVersionScript.is_valid(ClientBuildVersionScript.CLIENT_BUILD_VERSION),
		"the checked-in constant is a valid MAJOR.MINOR.PATCH version"
	)


func test_well_formed_versions_are_accepted() -> void:
	for version: String in ["0.0.0", "0.6.0", "1.2.3", "10.20.30", "0.12.0"]:
		assert_true(ClientBuildVersionScript.is_valid(version), "accepts %s" % version)


func test_malformed_versions_are_refused() -> void:
	var malformed: Array = [
		"",
		"1.2",
		"1.2.3.4",
		"v1.2.3",
		"1.2.x",
		"1.2.-3",
		"1.2.+3",
		"01.2.3",
		"1.02.3",
		" 1.2.3",
		"1.2.3 ",
		"1..3",
		"1.2.3-beta",
	]
	for version: Variant in malformed:
		assert_false(ClientBuildVersionScript.is_valid(version), "refuses %s" % [version])


func test_non_string_input_is_refused() -> void:
	for value: Variant in [null, 123, 1.2, true, [], {}]:
		assert_false(ClientBuildVersionScript.is_valid(value), "refuses non-String %s" % [value])
