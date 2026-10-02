extends GutTest

const Fixture = preload("res://tests/fixtures/item_creation_profile.gd")
const PROFILE_PATH: String = "res://server/item_creation_profile.gd"


func test_authored_profile_derives_fixed_creation_properties() -> void:
	var available: bool = ResourceLoader.exists(PROFILE_PATH)
	assert_true(available, "authored creation profile public seam exists")
	if not available:
		return
	var profile_script: Script = load(PROFILE_PATH)
	var parsed: Dictionary = profile_script.from_wire_dict(Fixture.authored())
	assert_eq(parsed.outcome, "ok")
	if parsed.profile == null:
		return
	var inputs: Dictionary = {
		"material_purity": 81, "catalyst_quality": 60, "workstation_parameter": 40,
	}
	var result: Dictionary = parsed.profile.derive(inputs)
	assert_eq(result.outcome, "ok")
	if result.properties == null:
		return
	# Independently worked fixture: purity81; floor(262/4)=65; floor(413/2)=206.
	assert_eq(result.properties.values, {"purity": 81, "quality": 65, "durability": 206})
	assert_eq(result.properties.tuning_version, "fixture:creation-v1")
	assert_eq(result.properties.blueprint_id, "fixture:sword")
	assert_eq(result.properties.blueprint_revision, "fixture:b1")
	assert_eq(result.properties.inputs, inputs)
	assert_eq(parsed.profile.to_wire_dict(), Fixture.authored())


func test_rejects_invalid_closed_authored_rules() -> void:
	var profile_script: Script = load(PROFILE_PATH)
	var changes: Array[Dictionary] = [
		{"path": [], "key": "profile_id", "value": ""},
		{"path": [], "key": "profile_revision", "value": " r1 "},
		{"path": [], "key": "blueprint_id", "value": 1},
		{"path": [], "key": "blueprint_revision", "value": true},
		{"path": [], "key": "tuning_version", "value": "bad\nversion"},
		{"path": [], "key": "arithmetic_version", "value": 2},
		{"path": ["inputs"], "key": "material_purity", "value": "open"},
		{"path": ["inputs", "material_purity"], "key": "unit", "value": ""},
		{"path": ["inputs", "material_purity"], "key": "extra", "value": true},
		{"path": ["inputs", "material_purity"], "key": "minimum", "value": -1},
		{"path": ["inputs", "material_purity"], "key": "minimum", "value": 101},
		{"path": ["inputs", "material_purity"], "key": "maximum", "value": 100.0},
		{"path": ["inputs", "material_purity"], "key": "maximum", "value": 1000001},
		{"path": ["outputs"], "key": "durability", "value": []},
		{"path": ["outputs", "durability"], "key": "unit", "value": true},
		{"path": ["outputs", "durability"], "key": "minimum", "value": 1001},
		{"path": ["outputs", "durability"], "key": "maximum", "value": 1000001},
		{"path": ["outputs", "durability"], "key": "offset", "value": -1},
		{"path": ["outputs", "durability"], "key": "divisor", "value": 0},
		{"path": ["outputs", "durability"], "key": "divisor", "value": "2"},
		{"path": ["outputs", "durability"], "key": "extra", "value": 1},
		{"path": ["outputs", "durability", "weights"], "key": "material_purity", "value": -1},
		{"path": ["outputs", "durability", "weights"], "key": "material_purity", "value": 1.0},
		{"path": ["outputs", "durability", "weights"], "key": "material_purity", "value": 1000001},
		{"path": ["outputs", "durability", "weights"], "key": "untrusted", "value": 1},
	]
	for change: Dictionary in changes:
		var wire: Dictionary = Fixture.authored()
		var target: Dictionary = wire
		for key: String in change.path:
			target = target[key]
		target[change.key] = change.value
		var parsed: Dictionary = profile_script.from_wire_dict(wire)
		assert_null(parsed.profile, "reject malformed authored rule: " + str(change))


func test_derivation_rejects_noninteger_or_out_of_authored_range_inputs() -> void:
	var profile_script: Script = load(PROFILE_PATH)
	var parsed: Dictionary = profile_script.from_wire_dict(Fixture.authored())
	assert_eq(parsed.outcome, "ok")
	if parsed.profile == null:
		return
	var invalid: Array = [true, 81.0, "81", -1, 101, 1000001]
	for key: String in ["material_purity", "catalyst_quality", "workstation_parameter"]:
		for bad: Variant in invalid:
			var inputs: Dictionary = {
				"material_purity": 81, "catalyst_quality": 60, "workstation_parameter": 40,
			}
			inputs[key] = bad
			var result: Dictionary = parsed.profile.derive(inputs)
			assert_eq(result.outcome, "malformed", "reject invalid creation input: " + key + "=" + str(bad))
			assert_null(result.properties)


func test_authored_clamps_and_maximum_encoding_use_worked_integer_results() -> void:
	var profile_script: Script = load(PROFILE_PATH)
	var wire: Dictionary = Fixture.authored()
	wire.outputs.purity.minimum = 7
	wire.outputs.purity.weights.material_purity = 0
	wire.outputs.quality.maximum = 60
	wire.outputs.durability.maximum = 150
	var parsed: Dictionary = profile_script.from_wire_dict(wire)
	assert_eq(parsed.outcome, "ok")
	if parsed.profile == null:
		return
	var result: Dictionary = parsed.profile.derive({
		"material_purity": 81, "catalyst_quality": 60, "workstation_parameter": 40,
	})
	assert_eq(result.properties.values, {"purity": 7, "quality": 60, "durability": 150})
	wire = Fixture.authored()
	for key: String in ["material_purity", "catalyst_quality", "workstation_parameter"]:
		wire.inputs[key].maximum = 1000000
		wire.outputs.durability.weights[key] = 1000000
	wire.outputs.durability.offset = 1000000
	wire.outputs.durability.divisor = 1000000
	wire.outputs.durability.maximum = 1000000
	parsed = profile_script.from_wire_dict(wire)
	assert_eq(parsed.outcome, "ok")
	if parsed.profile == null:
		return
	result = parsed.profile.derive({
		"material_purity": 1000000, "catalyst_quality": 1000000, "workstation_parameter": 1000000,
	})
	# floor(3000001000000/1000000)=3000001; authored clamp limits it to1000000.
	assert_eq(result.properties.values.durability, 1000000)


func test_profile_and_creation_results_do_not_alias_caller_owned_data() -> void:
	var profile_script: Script = load(PROFILE_PATH)
	var wire: Dictionary = Fixture.authored()
	var parsed: Dictionary = profile_script.from_wire_dict(wire)
	assert_eq(parsed.outcome, "ok")
	if parsed.profile == null:
		return
	wire.outputs.quality.weights.material_purity = 99
	wire.tuning_version = "fixture:unaccepted-change"
	var exported: Dictionary = parsed.profile.to_wire_dict()
	exported.outputs.quality.maximum = 0
	var inputs: Dictionary = {
		"material_purity": 81, "catalyst_quality": 60, "workstation_parameter": 40,
	}
	var result: Dictionary = parsed.profile.derive(inputs)
	inputs.material_purity = 0
	assert_eq(result.properties.inputs.material_purity, 81)
	assert_eq(result.properties.values, {"purity": 81, "quality": 65, "durability": 206})
	assert_eq(result.properties.tuning_version, "fixture:creation-v1")
	result.properties.values.quality = 0
	result.properties.inputs.material_purity = 0
	result.properties.units.quality = "fixture:changed"
	var repeated: Dictionary = parsed.profile.derive({
		"material_purity": 81, "catalyst_quality": 60, "workstation_parameter": 40,
	})
	assert_eq(repeated.properties.values, {"purity": 81, "quality": 65, "durability": 206})
	assert_eq(repeated.properties.units.quality, "fixture_points")
	assert_eq(parsed.profile.to_wire_dict(), Fixture.authored())


func test_creation_provenance_is_order_stable_and_pins_authored_tuning() -> void:
	var profile_script: Script = load(PROFILE_PATH)
	var original: Dictionary = profile_script.from_wire_dict(Fixture.authored())
	var reordered: Dictionary = profile_script.from_wire_dict(_reverse_dictionary_order(Fixture.authored()))
	assert_eq(original.outcome, "ok")
	assert_eq(reordered.outcome, "ok")
	if original.profile == null or reordered.profile == null:
		return
	var inputs: Dictionary = {
		"material_purity": 81, "catalyst_quality": 60, "workstation_parameter": 40,
	}
	var first: Dictionary = original.profile.derive(inputs)
	var second: Dictionary = reordered.profile.derive(inputs)
	assert_eq(first.properties, second.properties)
	assert_eq(first.properties.profile_id, "fixture:forge-creation")
	assert_eq(first.properties.profile_revision, "fixture:r1")
	assert_eq(first.properties.arithmetic_version, 1)
	var updated: Dictionary = Fixture.authored()
	updated.tuning_version = "fixture:creation-v2"
	var parsed: Dictionary = profile_script.from_wire_dict(updated)
	assert_eq(parsed.outcome, "ok")
	if parsed.profile == null:
		return
	var changed: Dictionary = parsed.profile.derive(inputs)
	assert_ne(changed.properties.profile_sha256, first.properties.profile_sha256)
	assert_eq(changed.properties.tuning_version, "fixture:creation-v2")
	assert_eq(original.profile.derive(inputs).properties, first.properties)


func test_closed_profile_and_input_protocols_reject_unrepresentable_values() -> void:
	var profile_script: Script = load(PROFILE_PATH)
	for raw: Variant in [null, [], "profile", {"schema_version": 1}]:
		assert_null(profile_script.from_wire_dict(raw).profile)
	for version: Variant in [true, 1.0, "1", 2]:
		var wire: Dictionary = Fixture.authored()
		wire.schema_version = version
		assert_null(profile_script.from_wire_dict(wire).profile)
	var parsed: Dictionary = profile_script.from_wire_dict(Fixture.authored())
	assert_eq(parsed.outcome, "ok")
	if parsed.profile == null:
		return
	for bad: Variant in [null, [], {}, NAN, INF, -INF]:
		var inputs: Dictionary = {
			"material_purity": bad, "catalyst_quality": 60, "workstation_parameter": 40,
		}
		var result: Dictionary = parsed.profile.derive(inputs)
		assert_eq(result.outcome, "malformed")
		assert_null(result.properties)
	for raw: Variant in [null, [], "inputs", {}, {
		"material_purity": 81, "catalyst_quality": 60, "workstation_parameter": 40, "extra": 1,
	}]:
		assert_null(parsed.profile.derive(raw).properties)


func _reverse_dictionary_order(value: Variant) -> Variant:
	if not (value is Dictionary):
		return value
	var source: Dictionary = value
	var keys: Array = source.keys()
	keys.reverse()
	var result: Dictionary = {}
	for key: Variant in keys:
		result[key] = _reverse_dictionary_order(source[key])
	return result
