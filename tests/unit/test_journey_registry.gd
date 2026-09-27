extends GutTest

const JourneyRegistryScript: Script = preload("res://server/journey_registry.gd")


func test_entry_disconnect_and_reclaim_keep_one_journey_identity() -> void:
	var registry: RefCounted = JourneyRegistryScript.new()
	var entered: Dictionary = registry.enter("character-1", 7, 100)
	var disconnected: Dictionary = registry.mark_disconnected("character-1", 7, 101)
	var reclaimed: Dictionary = registry.enter("character-1", 8, 102)

	assert_eq(entered["outcome"], JourneyRegistryScript.OUTCOME_OK)
	assert_eq(entered["kind"], "entry")
	assert_eq(disconnected["kind"], "disconnect")
	assert_eq(reclaimed["kind"], "reclaim")
	assert_eq(reclaimed["journey_id"], entered["journey_id"])


func test_active_character_claim_is_rejected_without_duplicate_presence() -> void:
	var registry: RefCounted = JourneyRegistryScript.new()
	var first: Dictionary = registry.enter("character-1", 7, 100)
	var conflict: Dictionary = registry.enter("character-1", 8, 101)

	assert_eq(first["journey_id"], conflict["journey_id"])
	assert_eq(conflict["outcome"], JourneyRegistryScript.REASON_CHARACTER_ACTIVE)


func test_expired_disconnect_is_cleaned_and_next_entry_gets_new_journey() -> void:
	var registry: RefCounted = JourneyRegistryScript.new()
	var first: Dictionary = registry.enter("character-1", 7, 100)
	registry.mark_disconnected("character-1", 7, 101)
	var cleaned: Array[Dictionary] = registry.cleanup(101 + JourneyRegistryScript.RECLAIM_WINDOW_SECONDS + 1)
	var next: Dictionary = registry.enter("character-1", 8, 101 + JourneyRegistryScript.RECLAIM_WINDOW_SECONDS + 1)

	assert_eq(cleaned.size(), 1)
	assert_eq(cleaned[0]["journey_id"], first["journey_id"])
	assert_ne(next["journey_id"], first["journey_id"])


func _journey_position(result: Dictionary) -> Vector3:
	var journey: Dictionary = result["journey"]
	return Vector3(float(journey["position_x"]), float(journey["position_y"]), float(journey["position_z"]))


func test_fresh_entry_keeps_server_selected_grounded_spawn() -> void:
	# #1230: a fresh journey must start at the server-selected capsule-center
	# spawn (START_POSITIONS are Y1), not the world origin at Y0.
	var registry: RefCounted = JourneyRegistryScript.new()
	var entered: Dictionary = registry.enter("character-1", 7, 100, Vector3(-3.0, 1.0, 5.0))

	assert_eq(entered["kind"], "entry")
	assert_eq(_journey_position(entered), Vector3(-3.0, 1.0, 5.0))


func test_distinct_fresh_entries_keep_their_own_spawns() -> void:
	var registry: RefCounted = JourneyRegistryScript.new()
	var first: Dictionary = registry.enter("character-1", 7, 100, Vector3(-3.0, 1.0, 5.0))
	var second: Dictionary = registry.enter("character-2", 8, 100, Vector3(3.0, 1.0, 5.0))

	assert_eq(_journey_position(first), Vector3(-3.0, 1.0, 5.0))
	assert_eq(_journey_position(second), Vector3(3.0, 1.0, 5.0))


func test_same_peer_repeated_entry_ignores_new_initial_spawn() -> void:
	var registry: RefCounted = JourneyRegistryScript.new()
	var first: Dictionary = registry.enter("character-1", 7, 100, Vector3(-3.0, 1.0, 5.0))
	var repeated: Dictionary = registry.enter("character-1", 7, 101, Vector3(9.0, 1.0, 9.0))

	assert_eq(repeated["kind"], "entry")
	assert_eq(repeated["journey_id"], first["journey_id"])
	assert_eq(_journey_position(repeated), Vector3(-3.0, 1.0, 5.0))


func test_reclaim_retains_saved_checkpoint_over_new_initial_spawn() -> void:
	for saved: Vector3 in [Vector3(12.0, 0.0, -8.0), Vector3(12.0, 4.5, -8.0)]:
		var registry: RefCounted = JourneyRegistryScript.new()
		registry.enter("character-1", 7, 100, Vector3(-3.0, 1.0, 5.0))
		registry.checkpoint("character-1", saved, 101, "sector-0-0", 1, "geometry-hash")
		registry.mark_disconnected("character-1", 7, 102)
		var reclaimed: Dictionary = registry.enter("character-1", 8, 103, Vector3(3.0, 1.0, 5.0))

		assert_eq(reclaimed["kind"], "reclaim")
		assert_eq(_journey_position(reclaimed), saved, "reclaim keeps the saved checkpoint, including Y%s" % saved.y)


func test_restored_record_reclaim_retains_persisted_position() -> void:
	var registry: RefCounted = JourneyRegistryScript.new()
	registry.restore_records([{
		"journey_id": "journey-4",
		"character_id": "character-1",
		"position_x": 12.0,
		"position_y": 0.0,
		"position_z": -8.0,
		"last_checkpoint_at": 100,
		"last_disconnected_at": 101,
	}])
	var reclaimed: Dictionary = registry.enter("character-1", 8, 102, Vector3(3.0, 1.0, 5.0))

	assert_eq(reclaimed["kind"], "reclaim")
	assert_eq(reclaimed["journey_id"], "journey-4")
	assert_eq(_journey_position(reclaimed), Vector3(12.0, 0.0, -8.0))