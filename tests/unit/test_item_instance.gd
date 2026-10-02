extends GutTest

const DefinitionScript = preload("res://shared/item_definition.gd")
const InstanceScript = preload("res://shared/item_instance.gd")


func test_active_instance_round_trips_with_pinned_definition() -> void:
	var wire: Dictionary = _instance_wire()
	var result: Dictionary = InstanceScript.from_wire_dict(wire, _definition())
	assert_eq(result.outcome, "ok")
	assert_not_null(result.instance)
	if result.instance != null:
		assert_eq(result.instance.to_wire_dict(), wire)


func _definition() -> ItemDefinition:
	return DefinitionScript.from_wire_dict({
		"schema_version": 1,
		"definition_id": "definition:steel-sword",
		"definition_revision": "edition:alpha",
		"item_class": "sword",
		"slot": "right_hand",
		"category": "mundane",
		"maximum_stack": 2,
		"binding_policy": "none",
		"base_effect": 10.0,
	}).definition


func _instance_wire() -> Dictionary:
	return {
		"schema_version": 1,
		"instance_id": "instance:one",
		"definition_id": "definition:steel-sword",
		"definition_revision": "edition:alpha",
		"quantity": 1,
		"owner": {"kind": "character", "id": "character:one"},
		"location": {"kind": "carried", "container_instance_id": "bag:one", "index": 0},
		"bound_character_id": "",
		"acquisition": {"source_id": "workshop:one", "operation_id": "craft:one", "server_tick": 10},
		"instance_revision": 0,
		"terminal": null,
	}


func test_instance_rejects_unpinned_open_or_invalid_identity() -> void:
	var changes: Array[Dictionary] = [
		{"schema_version": "1"}, {"schema_version": 2},
		{"instance_id": ""}, {"definition_id": "definition:other"},
		{"definition_revision": "edition:other"}, {"definition_revision": 1},
		{"quantity": 0}, {"quantity": -1}, {"quantity": 3}, {"quantity": 1.5},
		{"instance_revision": -1}, {"instance_revision": "0"},
		{"bound_character_id": 1}, {"durability": 100},
		{"custom_data": {}}, {"random_affixes": []},
		{"acquisition": {"source_id": "source", "operation_id": "operation", "server_tick": -1}},
		{"acquisition": {"source_id": "source", "operation_id": "operation", "server_tick": 0.5}},
		{"acquisition": {"source_id": "", "operation_id": "operation", "server_tick": 1}},
		{"acquisition": {"source_id": "source", "operation_id": "", "server_tick": 1}},
		{"acquisition": {"source_id": "source", "operation_id": "operation", "server_tick": 1, "extra": true}},
	]
	for change: Dictionary in changes:
		var wire: Dictionary = _instance_wire()
		wire.merge(change, true)
		var result: Dictionary = InstanceScript.from_wire_dict(wire, _definition())
		assert_ne(result.outcome, "ok", str(change))
		assert_null(result.instance, str(change))
	for key: String in _instance_wire():
		var wire: Dictionary = _instance_wire()
		wire.erase(key)
		assert_null(InstanceScript.from_wire_dict(wire, _definition()).instance, key)
	assert_null(InstanceScript.from_wire_dict(_instance_wire(), null).instance)
	assert_null(InstanceScript.from_wire_dict(null, _definition()).instance)


func test_instance_rejects_incompatible_or_open_owner_locations() -> void:
	var changes: Array[Dictionary] = [
		{"owner": null}, {"owner": "character:one"},
		{"owner": {"kind": "account", "id": "account:one"}},
		{"owner": {"kind": "character", "id": ""}},
		{"owner": {"kind": "character", "id": "character:one", "extra": true}},
		{"owner": {"kind": "world_container", "id": "source:one"}},
		{"location": null}, {"location": {"kind": "unknown"}},
		{"location": {"kind": "equipped", "slot": "extra_hand"}},
		{"location": {"kind": "equipped", "slot": "left_hand"}},
		{"location": {"kind": "equipped", "slot": "right_hand", "index": 0}},
		{"location": {"kind": "carried", "container_instance_id": "bag:one", "index": -1}},
		{"location": {"kind": "carried", "container_instance_id": "bag:one", "index": 1.5}},
		{"location": {"kind": "carried", "container_instance_id": "", "index": 0}},
		{"location": {"kind": "carried", "container_instance_id": "instance:one", "index": 0}},
		{"location": {"kind": "carried", "container_instance_id": "bag:one", "index": 0, "extra": true}},
		{"location": {"kind": "loot_position", "source_id": "source:one", "index": 0}},
	]
	for change: Dictionary in changes:
		var wire: Dictionary = _instance_wire()
		wire.merge(change, true)
		assert_null(InstanceScript.from_wire_dict(wire, _definition()).instance, str(change))
	var world: Dictionary = _instance_wire()
	world.owner = {"kind": "world_container", "id": "source:one"}
	world.location = {"kind": "loot_position", "source_id": "source:other", "index": 0}
	assert_null(InstanceScript.from_wire_dict(world, _definition()).instance)
	world.location = {"kind": "equipped", "slot": "right_hand"}
	assert_null(InstanceScript.from_wire_dict(world, _definition()).instance)
	var bag_definition: Dictionary = _definition().to_wire_dict()
	bag_definition.slot = "bags"
	assert_null(InstanceScript.from_wire_dict(_instance_wire(), DefinitionScript.from_wire_dict(bag_definition).definition).instance)


func test_all_fixed_slots_and_world_loot_locations_round_trip() -> void:
	var slots: PackedStringArray = [
		"head", "body", "arms", "hands", "rings", "back", "legs", "boots",
		"necklace", "earrings", "left_hand", "right_hand", "ranged_weapon", "bags",
	]
	for slot: String in slots:
		var fixed: Dictionary = _definition().to_wire_dict()
		fixed.slot = slot
		var wire: Dictionary = _instance_wire()
		wire.location = {"kind": "equipped", "slot": slot}
		var result: Dictionary = InstanceScript.from_wire_dict(wire, DefinitionScript.from_wire_dict(fixed).definition)
		assert_not_null(result.instance, slot)
		if result.instance != null:
			assert_eq(result.instance.to_wire_dict(), wire, slot)
	var world: Dictionary = _instance_wire()
	world.owner = {"kind": "world_container", "id": "source:one"}
	world.location = {"kind": "loot_position", "source_id": "source:one", "index": 0}
	var result: Dictionary = InstanceScript.from_wire_dict(world, _definition())
	assert_not_null(result.instance)
	if result.instance != null:
		assert_eq(result.instance.to_wire_dict(), world)


func test_binding_state_names_a_character_only_under_a_binding_policy() -> void:
	var wire: Dictionary = _instance_wire()
	wire.bound_character_id = "   "
	assert_null(InstanceScript.from_wire_dict(wire, _definition()).instance)
	wire.bound_character_id = "character:bound"
	assert_null(InstanceScript.from_wire_dict(wire, _definition()).instance)
	for policy: String in ["quest", "player_locked"]:
		var fixed: Dictionary = _definition().to_wire_dict()
		fixed.binding_policy = policy
		var result: Dictionary = InstanceScript.from_wire_dict(wire, DefinitionScript.from_wire_dict(fixed).definition)
		assert_not_null(result.instance, policy)
		if result.instance != null:
			assert_eq(result.instance.to_wire_dict().bound_character_id, "character:bound")


func test_retired_records_round_trip_without_live_owner_or_location() -> void:
	for reason: String in ["consumed", "destroyed", "merged"]:
		var wire: Dictionary = _instance_wire()
		wire.owner = null
		wire.location = null
		wire.terminal = {"reason": reason, "server_tick": 12, "operation_id": "retire:one"}
		var result: Dictionary = InstanceScript.from_wire_dict(wire, _definition())
		assert_not_null(result.instance, reason)
		if result.instance != null:
			assert_eq(result.instance.to_wire_dict(), wire, reason)


func test_terminal_records_reject_live_state_and_invalid_retirement_metadata() -> void:
	var terminal: Dictionary = {"reason": "consumed", "server_tick": 12, "operation_id": "retire:one"}
	var active: Dictionary = _instance_wire()
	active.terminal = terminal
	assert_null(InstanceScript.from_wire_dict(active, _definition()).instance)
	active.owner = null
	assert_null(InstanceScript.from_wire_dict(active, _definition()).instance)
	active = _instance_wire()
	active.location = null
	active.terminal = terminal
	assert_null(InstanceScript.from_wire_dict(active, _definition()).instance)
	var invalid: Array[Variant] = [
		{}, "consumed", [],
		{"reason": "revived", "server_tick": 12, "operation_id": "retire:one"},
		{"reason": "consumed", "server_tick": -1, "operation_id": "retire:one"},
		{"reason": "consumed", "server_tick": 12.5, "operation_id": "retire:one"},
		{"reason": "consumed", "server_tick": 12, "operation_id": ""},
		{"reason": "consumed", "server_tick": 12, "operation_id": "retire:one", "extra": true},
	]
	for metadata: Variant in invalid:
		var wire: Dictionary = _instance_wire()
		wire.owner = null
		wire.location = null
		wire.terminal = metadata
		assert_null(InstanceScript.from_wire_dict(wire, _definition()).instance, str(metadata))


func test_instance_snapshots_keep_nested_state_and_failures_deterministic() -> void:
	var active: Dictionary = _instance_wire()
	var retired: Dictionary = _instance_wire()
	retired.owner = null
	retired.location = null
	retired.terminal = {"reason": "merged", "server_tick": 12, "operation_id": "merge:one"}
	for original: Dictionary in [active, retired]:
		var input: Dictionary = original.duplicate(true)
		var instance: ItemInstance = InstanceScript.from_wire_dict(input, _definition()).instance
		input.acquisition.source_id = "source:changed"
		if input.owner != null:
			input.owner.id = "character:changed"
		else:
			input.terminal.operation_id = "retire:changed"
		var output: Dictionary = instance.to_wire_dict()
		output.acquisition.operation_id = "operation:changed"
		if output.location != null:
			output.location.index = 99
		assert_eq(instance.to_wire_dict(), original)
		assert_eq(JSON.stringify(instance.to_wire_dict()), JSON.stringify(original))
	var invalid: Dictionary = _instance_wire()
	invalid.definition_revision = "edition:other"
	assert_eq(InstanceScript.from_wire_dict(invalid, _definition()), InstanceScript.from_wire_dict(invalid, _definition()))
