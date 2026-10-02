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
