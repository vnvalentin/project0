extends GutTest
## Slice 133 (Phase 15, P-016-A): the durable vessel and its fixed-budget
## redistribution (shared/vessel_progression_state.gd). Every gain preserves the
## budget by compressing opposers (weighted, floored, re-spread), rejects
## atomically when impossible, and stays pinned to its tuning. See
## docs/adr/0006-versioned-embodiment-mechanics-architecture.md.

const VesselScript: Script = preload("res://shared/vessel_progression_state.gd")
const EmbodimentTuningScript: Script = preload("res://server/embodiment_tuning.gd")
const SchemaScript: Script = preload("res://shared/embodiment_tuning_schema.gd")


func _tuning() -> Object:
	return EmbodimentTuningScript.resolve(EmbodimentTuningScript.DEFAULT_TUNING_VERSION)["tuning"]


func _sum(vessel: Object) -> float:
	return SchemaScript.sum_over_nodes(vessel.base_nodes)


func test_create_baseline_is_balanced_and_pinned() -> void:
	var tuning: Object = _tuning()
	var vessel: Object = VesselScript.create_baseline(tuning)
	assert_eq(vessel.tuning_version, tuning.tuning_version, "the vessel is pinned to its build tuning")
	assert_almost_eq(_sum(vessel), 60.0, 0.0001, "the baseline sums to the budget")
	for key: String in SchemaScript.NODE_KEYS:
		assert_almost_eq(float(vessel.base_nodes[key]), 10.0, 0.0001, "each node starts balanced")


func test_train_adds_gain_and_preserves_budget() -> void:
	var tuning: Object = _tuning()
	var vessel: Object = VesselScript.create_baseline(tuning)
	assert_eq(vessel.train("STR", 6.0, tuning)["outcome"], "ok")
	assert_almost_eq(float(vessel.base_nodes["STR"]), 16.0, 0.0001, "the trained node gains the full amount")
	assert_almost_eq(_sum(vessel), 60.0, 0.0001, "the budget is preserved")


func test_train_compresses_opposers_uniformly() -> void:
	var tuning: Object = _tuning()
	var vessel: Object = VesselScript.create_baseline(tuning)
	vessel.train("STR", 6.0, tuning)
	for opp: String in ["DEX", "CON", "INT", "WIS", "CHA"]:
		assert_almost_eq(float(vessel.base_nodes[opp]), 8.8, 0.0001, "%s is compressed equally (6/5)" % opp)


func test_train_at_exact_capacity_floors_all_opposers() -> void:
	var tuning: Object = _tuning()
	var vessel: Object = VesselScript.create_baseline(tuning)
	# Each opposer has capacity 10 - 4 = 6; five opposers = 30 total capacity.
	assert_eq(vessel.train("STR", 30.0, tuning)["outcome"], "ok")
	assert_almost_eq(float(vessel.base_nodes["STR"]), 40.0, 0.0001)
	for opp: String in ["DEX", "CON", "INT", "WIS", "CHA"]:
		assert_almost_eq(float(vessel.base_nodes[opp]), 4.0, 0.0001, "%s is floored" % opp)
	assert_almost_eq(_sum(vessel), 60.0, 0.0001)


func test_train_rejects_beyond_capacity_atomically() -> void:
	var tuning: Object = _tuning()
	var vessel: Object = VesselScript.create_baseline(tuning)
	# 31 > 30 total capacity: impossible to preserve the budget above floors.
	assert_eq(vessel.train("STR", 31.0, tuning)["outcome"], "rejected_at_capacity")
	assert_almost_eq(float(vessel.base_nodes["STR"]), 10.0, 0.0001, "a rejected gain is an atomic no-op")
	assert_almost_eq(_sum(vessel), 60.0, 0.0001)


func test_train_floors_a_low_opposer_and_respreads_the_deficit() -> void:
	var tuning: Object = _tuning()
	# Asymmetric earned vessel: DEX is already low (5), so training STR floors it
	# and re-spreads the leftover across the other opposers.
	var wire: Dictionary = {
		"schema_version": 1, "tuning_version": tuning.tuning_version,
		"base_nodes": {"STR": 10, "DEX": 5, "CON": 15, "INT": 10, "WIS": 10, "CHA": 10},
	}
	var vessel: Object = VesselScript.from_wire_dict(wire, tuning)["vessel"]
	assert_eq(vessel.train("STR", 8.0, tuning)["outcome"], "ok")
	assert_almost_eq(float(vessel.base_nodes["DEX"]), 4.0, 0.0001, "DEX is clamped at its floor, not below")
	assert_almost_eq(float(vessel.base_nodes["STR"]), 18.0, 0.0001)
	assert_almost_eq(_sum(vessel), 60.0, 0.0001, "the budget is still preserved after re-spread")
	for key: String in SchemaScript.NODE_KEYS:
		assert_true(float(vessel.base_nodes[key]) >= 4.0 - 0.0001, "no node is pushed below the floor: %s" % key)


func test_train_rejects_an_unsupported_node() -> void:
	var tuning: Object = _tuning()
	var vessel: Object = VesselScript.create_baseline(tuning)
	assert_eq(vessel.train("ZZZ", 1.0, tuning)["outcome"], "unsupported_node")


func test_train_rejects_non_positive_evidence() -> void:
	var tuning: Object = _tuning()
	var vessel: Object = VesselScript.create_baseline(tuning)
	assert_eq(vessel.train("STR", 0.0, tuning)["outcome"], "malformed")
	assert_eq(vessel.train("STR", -3.0, tuning)["outcome"], "malformed")


func test_train_rejects_a_tuning_mismatch() -> void:
	var tuning: Object = _tuning()
	var vessel: Object = VesselScript.create_baseline(tuning)
	var other_tuning: Object = EmbodimentTuningScript.new("some-other-version", 60.0, 4.0, 1.0)
	assert_eq(vessel.train("STR", 1.0, other_tuning)["outcome"], "tuning_mismatch")
	assert_almost_eq(float(vessel.base_nodes["STR"]), 10.0, 0.0001, "a mismatched tuning changes nothing")


func test_from_wire_dict_accepts_valid_and_rejects_budget_violation() -> void:
	var tuning: Object = _tuning()
	var ok: Dictionary = VesselScript.from_wire_dict({
		"schema_version": 1, "tuning_version": tuning.tuning_version,
		"base_nodes": {"STR": 20, "DEX": 8, "CON": 8, "INT": 8, "WIS": 8, "CHA": 8},
	}, tuning)
	assert_eq(ok["outcome"], "ok")
	var bad: Dictionary = VesselScript.from_wire_dict({
		"schema_version": 1, "tuning_version": tuning.tuning_version,
		"base_nodes": {"STR": 20, "DEX": 20, "CON": 20, "INT": 20, "WIS": 20, "CHA": 20},
	}, tuning)
	assert_eq(bad["outcome"], "budget_violation", "a base that breaks the fixed budget is refused")


func test_from_wire_dict_rejects_unsupported_version() -> void:
	var tuning: Object = _tuning()
	var result: Dictionary = VesselScript.from_wire_dict({
		"schema_version": 2, "tuning_version": tuning.tuning_version,
		"base_nodes": {"STR": 10, "DEX": 10, "CON": 10, "INT": 10, "WIS": 10, "CHA": 10},
	}, tuning)
	assert_eq(result["outcome"], "unsupported_version")
	assert_null(result["vessel"])
