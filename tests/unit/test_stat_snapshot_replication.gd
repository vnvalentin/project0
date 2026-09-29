extends GutTest
## Experiment 1 for Epic #1293: admission/change-driven stat snapshots and
## client-side fail-closed retention.

const PlayerStateScript: Script = preload("res://server/server_player_state.gd")
const NetworkClientScript: Script = preload("res://client/network_client.gd")
const GameStateScript: Script = preload("res://shared/game_state.gd")


func _nodes(strength: float, dexterity: float, constitution: float) -> Dictionary:
	return {
		"STR": strength,
		"DEX": dexterity,
		"CON": constitution,
		"INT": 10.0,
		"WIS": 10.0,
		"CHA": 10.0,
	}


func _snapshot(strength: float, dexterity: float, constitution: float) -> Dictionary:
	var tuning_script: Script = preload("res://server/embodiment_tuning.gd")
	var tuning: Object = tuning_script.resolve(tuning_script.DEFAULT_TUNING_VERSION)["tuning"]
	var state: Object = GameStateScript.create_stat_aggregate(_nodes(strength, dexterity, constitution), tuning)["state"]
	return state.to_snapshot(tuning.tuning_version)


func test_player_state_emits_one_admission_snapshot_and_one_change_snapshot() -> void:
	var player: Node = PlayerStateScript.new()
	add_child_autofree(player)
	watch_signals(player)
	player.start_for_peer(7, Vector3.ZERO)
	assert_signal_emitted(player, "authoritative_stats_ready")
	assert_eq(get_signal_emit_count(player, "authoritative_stats_ready"), 1)
	var admission: Dictionary = get_signal_parameters(player, "authoritative_stats_ready", 0)[1]
	assert_eq((admission["stats"] as Dictionary).size(), 11)
	assert_eq(player.update_authoritative_stats(_nodes(12.0, 8.0, 14.0))["outcome"], GameStateScript.OUTCOME_OK)
	assert_eq(get_signal_emit_count(player, "authoritative_stats_ready"), 2)


func test_client_accepts_valid_snapshot_and_preserves_it_on_rejection() -> void:
	var client: Node = NetworkClientScript.new()
	add_child_autofree(client)
	watch_signals(client)
	var valid: Dictionary = _snapshot(10.0, 10.0, 10.0)
	client.receive_stat_snapshot(valid)
	assert_eq(client.latest_authoritative_stats, valid)
	assert_signal_emitted_with_parameters(client, "stat_sync_diagnostic", [GameStateScript.EVENT_STAT_SYNC_PARITY_VERIFIED])
	var malformed: Dictionary = valid.duplicate(true)
	malformed["stats"].erase("BaseHP")
	client.receive_stat_snapshot(malformed)
	assert_eq(client.latest_authoritative_stats, valid)
	assert_signal_emitted_with_parameters(client, "stat_sync_diagnostic", [GameStateScript.EVENT_LAST_KNOWN_STATE_PRESERVED])


func test_client_rejects_version_and_derived_mismatch() -> void:
	var client: Node = NetworkClientScript.new()
	add_child_autofree(client)
	watch_signals(client)
	var valid: Dictionary = _snapshot(10.0, 10.0, 10.0)
	client.receive_stat_snapshot(valid)
	var version_mismatch: Dictionary = valid.duplicate(true)
	version_mismatch["tuning_version"] = "future-tuning"
	client.receive_stat_snapshot(version_mismatch)
	var derived_mismatch: Dictionary = valid.duplicate(true)
	derived_mismatch["stats"]["BaseHP"] = 999.0
	client.receive_stat_snapshot(derived_mismatch)
	assert_eq(client.latest_authoritative_stats, valid)
	assert_true(get_signal_emit_count(client, "stat_sync_diagnostic") >= 4)