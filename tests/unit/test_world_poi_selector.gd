extends GutTest

const SelectorScript: Script = preload("res://server/world_poi_selector.gd")

func _candidate(identifier: String, elevation: float, slope: float, flatness: float) -> Dictionary:
	return {"candidate_id": identifier, "elevation": elevation, "slope": slope, "flatness": flatness}

func test_selects_highest_peak_and_deterministically_breaks_ties() -> void:
	var result: Dictionary = SelectorScript.select(SelectorScript.PREDICATE_HIGHEST_PEAK, [
		_candidate("z", 10.0, 0.2, 0.4), _candidate("a", 10.0, 0.2, 0.4), _candidate("low", 9.0, 0.1, 0.9),
	])
	assert_eq(result["outcome"], SelectorScript.OUTCOME_OK)
	assert_eq(result["candidate"]["candidate_id"], "a")

func test_selects_lowest_valley() -> void:
	var result: Dictionary = SelectorScript.select(SelectorScript.PREDICATE_VALLEY, [
		_candidate("high", 5.0, 0.1, 0.8), _candidate("low", -2.0, 0.5, 0.2),
	])
	assert_eq(result["candidate"]["candidate_id"], "low")

func test_flat_area_rejects_steep_candidates_and_ranks_flatness() -> void:
	var result: Dictionary = SelectorScript.select(SelectorScript.PREDICATE_FLAT_AREA, [
		_candidate("steep", 1.0, 0.8, 1.0), _candidate("flat", 2.0, 0.1, 0.9), _candidate("flatter", 3.0, 0.1, 0.95),
	])
	assert_eq(result["candidate"]["candidate_id"], "flatter")

func test_returns_no_feasible_candidate_without_partial_selection() -> void:
	var result: Dictionary = SelectorScript.select(SelectorScript.PREDICATE_FLAT_AREA, [_candidate("steep", 1.0, 0.8, 0.4)])
	assert_eq(result["outcome"], SelectorScript.OUTCOME_NO_FEASIBLE_CANDIDATE)
	assert_false(result.has("candidate"))

func test_rejects_malformed_candidate_or_predicate() -> void:
	var result: Dictionary = SelectorScript.select("RANDOM_COORDINATE", [])
	assert_eq(result["reason"], "unsupported_predicate")
	result = SelectorScript.select(SelectorScript.PREDICATE_VALLEY, [{"candidate_id": "bad", "elevation": 1.0, "slope": -1.0, "flatness": 0.5}])
	assert_eq(result["reason"], "candidate_metric_out_of_range")