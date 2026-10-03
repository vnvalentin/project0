extends GutTest

const DefinitionScript = preload("res://shared/item_definition.gd")
const PROFILE_PATH: String = "res://shared/item_capacity_profile.gd"
const BINDINGS_PATH: String = "res://shared/item_capacity_bindings.gd"
const ROUND_TRIP_LABEL: String = "1440 authored capacity profile parses and resolves pinned bag definition"


func test_pinned_capacity_profile_resolves_authored_bag_definition() -> void:
	# Guard before loading: absent future modules must yield one assertion, not a script error.
	var modules_present: bool = ResourceLoader.exists(PROFILE_PATH) and ResourceLoader.exists(BINDINGS_PATH)
	assert_true(modules_present, ROUND_TRIP_LABEL)
	if not modules_present:
		return
	var profile_script: Script = load(PROFILE_PATH) as Script
	var bindings_script: Script = load(BINDINGS_PATH) as Script
	var factories_present: bool = _declares_factory(profile_script, "from_wire_dict") and _declares_factory(bindings_script, "from_wire_profiles")
	assert_true(factories_present, ROUND_TRIP_LABEL)
	if not factories_present:
		return

	var definition_result: Dictionary = DefinitionScript.from_wire_dict(_bag_definition_wire())
	assert_eq(definition_result.outcome, "ok", "fixture bag definition is valid")
	var definition: ItemDefinition = definition_result.get("definition") as ItemDefinition
	assert_not_null(definition, "fixture bag definition is available")
	if definition == null:
		return
	var wire: Dictionary = _capacity_wire()
	var parsed: Variant = profile_script.call("from_wire_dict", wire)
	assert_true(parsed is Dictionary, "capacity parser returns its bounded result")
	if not (parsed is Dictionary):
		return
	var profile_result: Dictionary = parsed
	assert_eq(profile_result.get("outcome"), "ok", "authored fixture capacity parses")
	var profile: Object = profile_result.get("profile") as Object
	assert_not_null(profile, "parsed capacity profile is available")
	if profile == null:
		return
	assert_true(profile.has_method("to_wire_dict"), "capacity profile exposes its wire snapshot")
	if not profile.has_method("to_wire_dict"):
		return
	assert_eq(profile.call("to_wire_dict"), wire, "parsed capacity round-trips exactly")

	var constructed: Variant = bindings_script.call("from_wire_profiles", [wire])
	assert_true(constructed is Dictionary, "authored binding parser returns its bounded result")
	if not (constructed is Dictionary):
		return
	var binding_result: Dictionary = constructed
	assert_eq(binding_result.get("outcome"), "ok", "authored capacity bindings validate")
	var bindings: Object = binding_result.get("bindings") as Object
	assert_not_null(bindings, "validated immutable bindings are available")
	if bindings == null:
		return
	assert_true(bindings.has_method("resolve"), "capacity bindings expose pinned resolution")
	if not bindings.has_method("resolve"):
		return
	var resolved: Variant = bindings.call("resolve", definition)
	assert_true(resolved is Dictionary, "pinned resolution returns its bounded result")
	if not (resolved is Dictionary):
		return
	var resolution: Dictionary = resolved
	assert_eq(resolution.get("outcome"), "ok", "exact authored bag definition resolves")
	var resolved_profile: Object = resolution.get("profile") as Object
	assert_not_null(resolved_profile, "exact pinned capacity profile is available")
	if resolved_profile == null:
		return
	assert_true(resolved_profile.has_method("to_wire_dict"), "resolved profile exposes its wire snapshot")
	if not resolved_profile.has_method("to_wire_dict"):
		return
	var snapshot: Variant = resolved_profile.call("to_wire_dict")
	assert_eq(snapshot, wire, ROUND_TRIP_LABEL)
	assert_true(snapshot is Dictionary, "resolved capacity snapshot is a dictionary")
	if snapshot is Dictionary:
		var resolved_wire: Dictionary = snapshot
		assert_eq(resolved_wire.get("slot_count"), 4, "authored fixture bag capacity remains four slots")


func _declares_factory(script: Script, factory: String) -> bool:
	if script == null:
		return false
	for method: Dictionary in script.get_script_method_list():
		if String(method.get("name", "")) == factory:
			return true
	return false


func _bag_definition_wire() -> Dictionary:
	return {
		"schema_version": 1,
		"definition_id": "definition:fixture-carry-bag",
		"definition_revision": "fixture:bag-r1",
		"item_class": "bag",
		"slot": "bags",
		"category": "mundane",
		"maximum_stack": 1,
		"binding_policy": "none",
		"base_effect": 0.0,
	}


func _capacity_wire() -> Dictionary:
	return {
		"schema_version": 1,
		"profile_id": "fixture:bag-capacity",
		"profile_revision": "fixture:capacity-r1",
		"definition_id": "definition:fixture-carry-bag",
		"definition_revision": "fixture:bag-r1",
		"slot_count": 4,
	}
