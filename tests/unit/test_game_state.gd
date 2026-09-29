extends GutTest
## Experiment 1 for Epic #1291: the deterministic, server-owned 11-field stat
## aggregate and its client-mutation rejection boundary.

const GameStateScript: Script = preload("res://shared/game_state.gd")
const EmbodimentTuningScript: Script = preload("res://server/embodiment_tuning.gd")


func _tuning() -> Object:
	return EmbodimentTuningScript.resolve(EmbodimentTuningScript.DEFAULT_TUNING_VERSION)["tuning"]


func _nodes(strength: float, dexterity: float, constitution: float) -> Dictionary:
	return {
		"STR": strength,
		"DEX": dexterity,
		"CON": constitution,
		"INT": 10.0,
		"WIS": 10.0,
		"CHA": 10.0,
	}


func _state(nodes: Dictionary) -> Object:
	return GameStateScript.create_stat_aggregate(nodes, _tuning())["state"]


func test_aggregate_contains_all_eleven_fields() -> void:
	var state: Object = _state(_nodes(10.0, 10.0, 10.0))
	assert_eq(state.stats.keys().size(), 11)
	for key: String in GameStateScript.STAT_KEYS:
		assert_true(state.stats.has(key), "aggregate contains %s" % key)


func test_baseline_fixture_matches_option_three() -> void:
	var stats: Dictionary = _state(_nodes(10.0, 10.0, 10.0)).stats
	assert_almost_eq(float(stats["KineticVolume"]), 10.0, 0.0001)
	assert_almost_eq(float(stats["KineticControl"]), 10.0, 0.0001)
	assert_almost_eq(float(stats["KineticOutput"]), 10.0, 0.0001)
	assert_almost_eq(float(stats["BaseHP"]), 220.0, 0.0001)
	assert_almost_eq(float(stats["BaseStamina"]), 200.0, 0.0001)


func test_hyper_bulk_fixture_matches_option_three() -> void:
	var stats: Dictionary = _state(_nodes(10.0, 5.0, 30.0)).stats
	assert_almost_eq(float(stats["BaseHP"]), 460.0, 0.0001)
	assert_almost_eq(float(stats["BaseStamina"]), 275.0, 0.0001)


func test_initialization_is_deterministic() -> void:
	var nodes: Dictionary = _nodes(12.0, 14.0, 18.0)
	var first: Dictionary = _state(nodes).to_snapshot()
	var second: Dictionary = _state(nodes).to_snapshot()
	assert_eq(first, second)


func test_negative_attributes_fail_closed() -> void:
	var nodes: Dictionary = _nodes(10.0, 10.0, -1.0)
	var result: Dictionary = GameStateScript.create_stat_aggregate(nodes, _tuning())
	assert_eq(result["outcome"], GameStateScript.OUTCOME_OUT_OF_BOUNDS)
	assert_null(result["state"])


func test_client_mutation_is_rejected_without_state_change() -> void:
	var state: Object = _state(_nodes(10.0, 10.0, 10.0))
	var before: Dictionary = state.to_snapshot()
	var rejection: Dictionary = state.reject_client_mutation({"BaseHP": 1.0})
	assert_eq(rejection["outcome"], GameStateScript.OUTCOME_CLIENT_MUTATION_REJECTED)
	assert_eq(rejection["http_status"], 422)
	assert_eq(state.to_snapshot(), before)