extends GutTest

const DefinitionScript = preload("res://shared/item_definition.gd")


func test_pinned_definition_round_trips_at_public_seam() -> void:
	var wire: Dictionary = _definition_wire()
	var result: Dictionary = DefinitionScript.from_wire_dict(wire)
	assert_eq(result.outcome, "ok")
	assert_not_null(result.definition)
	if result.definition != null:
		assert_eq(result.definition.to_wire_dict(), wire)


func _definition_wire() -> Dictionary:
	return {
		"schema_version": 1,
		"definition_id": "definition:steel-sword",
		"definition_revision": "edition:alpha",
		"item_class": "sword",
		"slot": "right_hand",
		"category": "mundane",
		"maximum_stack": 1,
		"binding_policy": "none",
		"base_effect": 10.0,
	}


func test_definition_rejects_unpinned_open_or_invalid_metadata() -> void:
	var changes: Array[Dictionary] = [
		{"schema_version": "1"}, {"schema_version": 2},
		{"definition_id": ""}, {"definition_revision": ""},
		{"definition_revision": 1}, {"maximum_stack": 0},
		{"maximum_stack": 1.5}, {"slot": "extra_hand"},
		{"item_class": ""}, {"category": "unknown"},
		{"binding_policy": "unknown"}, {"base_effect": -1.0},
		{"durability": 100}, {"owner": "character:one"},
	]
	for change: Dictionary in changes:
		var wire: Dictionary = _definition_wire()
		wire.merge(change, true)
		var result: Dictionary = DefinitionScript.from_wire_dict(wire)
		assert_ne(result.outcome, "ok", str(change))
		assert_null(result.definition, str(change))
	for key: String in _definition_wire():
		var wire: Dictionary = _definition_wire()
		wire.erase(key)
		assert_null(DefinitionScript.from_wire_dict(wire).definition, key)


func test_definition_snapshot_survives_input_and_output_mutation() -> void:
	var original: Dictionary = _definition_wire()
	var input: Dictionary = original.duplicate(true)
	var definition: ItemDefinition = DefinitionScript.from_wire_dict(input).definition
	input.definition_revision = "edition:replacement"
	var output: Dictionary = definition.to_wire_dict()
	output.maximum_stack = 99
	assert_eq(definition.to_wire_dict(), original)
	assert_eq(JSON.stringify(definition.to_wire_dict()), JSON.stringify(original))
