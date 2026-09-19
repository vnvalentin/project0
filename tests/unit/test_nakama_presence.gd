extends GutTest

const PresenceScript: Script = preload("res://shared/nakama_presence.gd")


func test_snapshot_round_trip_accepts_shared_world_entries() -> void:
	var snapshot: Dictionary = PresenceScript.build([
		PresenceScript.entry(1, "user-a", "char-a", "Alice"),
		PresenceScript.entry(2, "user-b", "char-b", "Bob"),
	])
	var result: Dictionary = PresenceScript.validate(snapshot)
	assert_eq(result["outcome"], PresenceScript.OUTCOME_OK)
	assert_eq(result["snapshot"]["world_id"], "starting_town_shared")
	assert_eq((result["snapshot"]["entries"] as Array).size(), 2)


func test_snapshot_rejects_duplicate_peers_and_over_capacity() -> void:
	var duplicate: Dictionary = PresenceScript.build([
		PresenceScript.entry(1, "user-a", "char-a", "Alice"),
		PresenceScript.entry(1, "user-b", "char-b", "Bob"),
	])
	assert_eq(PresenceScript.validate(duplicate)["outcome"], PresenceScript.REASON_MALFORMED)
	var too_many: Array[Dictionary] = []
	for peer_id: int in range(PresenceScript.MAX_ENTRIES + 1):
		too_many.append(PresenceScript.entry(peer_id + 1, "user-%d" % peer_id, "char-%d" % peer_id, "Player%d" % peer_id))
	assert_eq(PresenceScript.validate(PresenceScript.build(too_many))["outcome"], PresenceScript.REASON_TOO_MANY)


func test_snapshot_rejects_missing_identity() -> void:
	var snapshot: Dictionary = PresenceScript.build([PresenceScript.entry(1, "", "char-a", "Alice")])
	assert_eq(PresenceScript.validate(snapshot)["outcome"], PresenceScript.REASON_MALFORMED)