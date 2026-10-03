extends GutTest

const CapacityScript = preload("res://shared/item_capacity_profile.gd")


func test_capacity_accepts_encoding_boundaries_and_exact_pin_spelling() -> void:
	for count: int in [1, 1024]:
		var wire: Dictionary = _wire()
		wire.slot_count = count
		for pin: String in ["profile_id", "profile_revision", "definition_id", "definition_revision"]:
			wire[pin] = "p".repeat(128)
		var parsed: Dictionary = CapacityScript.from_wire_dict(wire)
		assert_eq(parsed.outcome, "ok")
		assert_eq(parsed.detail, "")
		assert_not_null(parsed.profile)
		if parsed.profile != null:
			assert_eq(parsed.profile.to_wire_dict(), wire)
	var spaced: Dictionary = _wire()
	spaced.profile_id = " fixture:capacity "
	var exact: Dictionary = CapacityScript.from_wire_dict(spaced)
	assert_eq(exact.outcome, "ok")
	if exact.profile != null:
		assert_eq(exact.profile.to_wire_dict().profile_id, " fixture:capacity ")


func test_capacity_rejects_missing_open_and_non_dictionary_payloads() -> void:
	for value: Variant in [null, true, 1, "capacity", []]:
		_assert_rejected(value, "malformed")
	for key: String in _wire():
		var wire: Dictionary = _wire()
		wire.erase(key)
		_assert_rejected(wire, "malformed")
	var extra: Dictionary = _wire()
	extra.owner = "fixture:owner"
	_assert_rejected(extra, "malformed")
	var non_string: Dictionary = _wire()
	non_string.erase("profile_id")
	non_string[7] = "fixture:capacity"
	_assert_rejected(non_string, "malformed")


func test_capacity_rejects_non_integer_or_unsupported_schema() -> void:
	for value: Variant in [null, true, 1.0, "1", 0, 2]:
		var wire: Dictionary = _wire()
		wire.schema_version = value
		_assert_rejected(wire, "unsupported_version")


func test_capacity_rejects_invalid_pins_without_normalizing() -> void:
	for pin: String in ["profile_id", "profile_revision", "definition_id", "definition_revision"]:
		for value: Variant in [null, true, 7, 1.0, "", " \t ", "p".repeat(129)]:
			var wire: Dictionary = _wire()
			wire[pin] = value
			_assert_rejected(wire, "malformed")


func test_capacity_rejects_count_coercion_and_out_of_range_integers() -> void:
	for value: Variant in [null, true, false, 1.0, "4"]:
		var wire: Dictionary = _wire()
		wire.slot_count = value
		_assert_rejected(wire, "malformed")
	for value: int in [-1, 0, 1025]:
		var wire: Dictionary = _wire()
		wire.slot_count = value
		_assert_rejected(wire, "out_of_bounds")


func test_capacity_profile_retains_independent_input_and_output_snapshots() -> void:
	var original: Dictionary = _wire()
	var input: Dictionary = original.duplicate(true)
	var parsed: Dictionary = CapacityScript.from_wire_dict(input)
	assert_eq(parsed.outcome, "ok")
	assert_not_null(parsed.profile)
	if parsed.profile == null:
		return
	var profile: ItemCapacityProfile = parsed.profile
	input.slot_count = 99
	var output: Dictionary = profile.to_wire_dict()
	output.profile_revision = "fixture:replaced"
	assert_eq(profile.to_wire_dict(), original)


func _assert_rejected(value: Variant, expected: String) -> void:
	var result: Dictionary = CapacityScript.from_wire_dict(value)
	assert_eq(result.outcome, expected)
	assert_null(result.profile)
	assert_true(result.detail is String and not String(result.detail).is_empty())


func _wire() -> Dictionary:
	return {
		"schema_version": 1,
		"profile_id": "fixture:bag-capacity",
		"profile_revision": "fixture:capacity-r1",
		"definition_id": "definition:fixture-carry-bag",
		"definition_revision": "fixture:bag-r1",
		"slot_count": 4,
	}
