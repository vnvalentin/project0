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