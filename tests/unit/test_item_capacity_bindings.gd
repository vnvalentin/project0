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


func test_capacity_bindings_reject_malformed_sets_without_partial_value() -> void:
	for value: Variant in [null, true, {}, "profiles", [_capacity_wire(), null]]:
		var result: Dictionary = _bindings(value)
		assert_eq(result.outcome, "malformed")
		assert_null(result.bindings)
	var bad: Dictionary = _capacity_wire()
	bad.slot_count = 1025
	var bounded: Dictionary = _bindings([_capacity_wire(), bad])
	assert_eq(bounded.outcome, "out_of_bounds")
	assert_null(bounded.bindings)


func test_capacity_resolution_revalidates_definition_and_requires_bag_slot() -> void:
	var parsed: Dictionary = _bindings([_capacity_wire()])
	assert_not_null(parsed.bindings)
	if parsed.bindings == null:
		return
	var bindings: ItemCapacityBindings = parsed.bindings
	var absent: Dictionary = bindings.resolve(null)
	assert_eq(absent.outcome, "definition_mismatch")
	assert_null(absent.profile)
	var invalid: ItemDefinition = DefinitionScript.new({})
	var rejected: Dictionary = bindings.resolve(invalid)
	assert_eq(rejected.outcome, "definition_mismatch")
	assert_null(rejected.profile)
	var sword_wire: Dictionary = _bag_definition_wire()
	sword_wire.item_class = "sword"
	sword_wire.slot = "right_hand"
	var sword_result: Dictionary = DefinitionScript.from_wire_dict(sword_wire)
	assert_eq(sword_result.outcome, "ok")
	var sword: ItemDefinition = sword_result.definition
	var non_bag: Dictionary = bindings.resolve(sword)
	assert_eq(non_bag.outcome, "definition_mismatch")
	assert_null(non_bag.profile)


func test_capacity_resolution_never_falls_back_to_neighboring_revision() -> void:
	var definition: ItemDefinition = DefinitionScript.from_wire_dict(_bag_definition_wire()).definition
	var empty_result: Dictionary = _bindings([])
	assert_eq(empty_result.outcome, "ok")
	assert_not_null(empty_result.bindings)
	if empty_result.bindings == null:
		return
	var empty: ItemCapacityBindings = empty_result.bindings
	var missing: Dictionary = empty.resolve(definition)
	assert_eq(missing.outcome, "missing_profile")
	assert_null(missing.profile)
	var authored_result: Dictionary = _bindings([_capacity_wire()])
	assert_eq(authored_result.outcome, "ok")
	assert_not_null(authored_result.bindings)
	if authored_result.bindings == null:
		return
	var authored: ItemCapacityBindings = authored_result.bindings
	var other_revision: Dictionary = _bag_definition_wire()
	other_revision.definition_revision = "fixture:bag-r2"
	var other: ItemDefinition = DefinitionScript.from_wire_dict(other_revision).definition
	var neighboring: Dictionary = authored.resolve(other)
	assert_eq(neighboring.outcome, "missing_profile")
	assert_null(neighboring.profile)
	var spaced_pin: Dictionary = _bag_definition_wire()
	spaced_pin.definition_id = " definition:fixture-carry-bag "
	var spaced: ItemDefinition = DefinitionScript.from_wire_dict(spaced_pin).definition
	assert_eq(authored.resolve(spaced).outcome, "missing_profile")


func test_capacity_exact_duplicates_are_idempotent_and_conflicts_are_atomic() -> void:
	var original: Dictionary = _capacity_wire()
	var repeated: Dictionary = _bindings([original, original.duplicate(true)])
	assert_eq(repeated.outcome, "ok")
	assert_not_null(repeated.bindings)
	var definition: ItemDefinition = DefinitionScript.from_wire_dict(_bag_definition_wire()).definition
	if repeated.bindings != null:
		var resolved: Dictionary = repeated.bindings.resolve(definition)
		assert_eq(resolved.outcome, "ok")
		if resolved.profile != null:
			assert_eq(resolved.profile.to_wire_dict(), original)
	for changes: Dictionary in [
		{"slot_count": 5},
		{"profile_id": "fixture:other-profile"},
		{"profile_revision": "fixture:capacity-r2"},
		{"definition_revision": "fixture:bag-r2"},
		{"definition_id": "definition:other-bag"},
	]:
		var conflicting: Dictionary = original.duplicate(true)
		conflicting.merge(changes, true)
		for order: Array in [[original, conflicting], [conflicting, original]]:
			var result: Dictionary = _bindings(order)
			assert_eq(result.outcome, "immutable_profile_conflict")
			assert_null(result.bindings, "conflicting sets expose no partial bindings")


func test_capacity_independent_revisions_resolve_exactly_in_either_order() -> void:
	var first: Dictionary = _capacity_wire()
	var second: Dictionary = _capacity_wire()
	second.definition_revision = "fixture:bag-r2"
	second.profile_revision = "fixture:capacity-r2"
	second.slot_count = 7
	var second_definition: Dictionary = _bag_definition_wire()
	second_definition.definition_revision = "fixture:bag-r2"
	var first_bag: ItemDefinition = DefinitionScript.from_wire_dict(_bag_definition_wire()).definition
	var second_bag: ItemDefinition = DefinitionScript.from_wire_dict(second_definition).definition
	for order: Array in [[first, second], [second, first]]:
		var result: Dictionary = _bindings(order)
		assert_eq(result.outcome, "ok")
		assert_not_null(result.bindings)
		if result.bindings == null:
			continue
		var bindings: ItemCapacityBindings = result.bindings
		var first_resolution: Dictionary = bindings.resolve(first_bag)
		var second_resolution: Dictionary = bindings.resolve(second_bag)
		assert_eq(first_resolution.outcome, "ok")
		assert_eq(second_resolution.outcome, "ok")
		if first_resolution.profile != null and second_resolution.profile != null:
			assert_eq(first_resolution.profile.to_wire_dict(), first)
			assert_eq(second_resolution.profile.to_wire_dict(), second)


func test_capacity_binding_and_resolution_snapshots_do_not_alias() -> void:
	var original: Dictionary = _capacity_wire()
	var input: Dictionary = original.duplicate(true)
	var authored: Array = [input]
	var parsed: Dictionary = _bindings(authored)
	assert_eq(parsed.outcome, "ok")
	assert_not_null(parsed.bindings)
	if parsed.bindings == null:
		return
	var bindings: ItemCapacityBindings = parsed.bindings
	input.slot_count = 99
	authored.clear()
	var definition: ItemDefinition = DefinitionScript.from_wire_dict(_bag_definition_wire()).definition
	var first: Dictionary = bindings.resolve(definition)
	var second: Dictionary = bindings.resolve(definition)
	assert_eq(first.outcome, "ok")
	assert_eq(second.outcome, "ok")
	assert_not_null(first.profile)
	assert_not_null(second.profile)
	if first.profile == null or second.profile == null:
		return
	assert_ne(first.profile, second.profile, "each resolve returns an independent profile value")
	var snapshot: Dictionary = first.profile.to_wire_dict()
	snapshot.slot_count = 101
	assert_eq(first.profile.to_wire_dict(), original)
	assert_eq(second.profile.to_wire_dict(), original)
	var next: Dictionary = bindings.resolve(definition)
	assert_eq(next.outcome, "ok")
	assert_not_null(next.profile)
	if next.profile != null:
		assert_eq(next.profile.to_wire_dict(), original)


func _bindings(value: Variant) -> Dictionary:
	var script: Script = load(BINDINGS_PATH) as Script
	return script.call("from_wire_profiles", value)
