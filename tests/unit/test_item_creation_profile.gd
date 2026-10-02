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
