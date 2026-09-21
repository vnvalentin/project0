extends GutTest

const OrderingScript: Script = preload("res://server/world_directive_ordering.gd")

func _directive(identifier: String, sequence: int, priority: int, scope: String = "world") -> Dictionary:
	return {
		"directive_id": identifier, "canonical_event_sequence": sequence,
		"policy_priority": priority, "source_scope": scope,
		"target_sector_x": 2, "target_sector_z": -1, "base_revision": 3,
		"input_snapshot_hash": "snapshot-1", "schema_version": 1,
		"builder_version": "builder-v1", "tuning_version": "tuning-v1",
		"resource_set_version": "resources-v1",
	}

func test_orders_by_event_priority_scope_then_id() -> void:
	var result: Dictionary = OrderingScript.order([
		_directive("z", 2, 1), _directive("b", 1, 2), _directive("a", 1, 2), _directive("c", 1, 1),
	])
	assert_eq(result["outcome"], OrderingScript.OUTCOME_OK)
	assert_eq(result["directives"].map(func(item: Dictionary) -> String: return item["directive_id"]), ["c", "a", "b", "z"])

func test_replay_identity_is_stable_and_server_input_bound() -> void:
	var directive: Dictionary = _directive("a", 1, 2)
	var first: Dictionary = OrderingScript.replay_identity(directive, "world-seed")
	var second: Dictionary = OrderingScript.replay_identity(directive, "world-seed")
	assert_eq(first["outcome"], OrderingScript.OUTCOME_OK)
	assert_eq(first["replay_key"], second["replay_key"])
	assert_true(not first["replay_key"].is_empty())

func test_rejects_missing_identity_inputs_and_world_seed() -> void:
	var directive: Dictionary = _directive("a", 1, 2)
	directive.erase("base_revision")
	var result: Dictionary = OrderingScript.replay_identity(directive, "world-seed")
	assert_eq(result["reason"], "missing_base_revision")
	result = OrderingScript.replay_identity(_directive("a", 1, 2), "")
	assert_eq(result["reason"], "missing_world_seed")