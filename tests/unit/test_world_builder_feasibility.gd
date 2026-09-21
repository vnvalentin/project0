extends GutTest

const FeasibilityScript: Script = preload("res://server/world_builder_feasibility.gd")

func _directive() -> Dictionary:
	return {"directive_id": "directive-1", "schema_version": 1}

func _poi(slope: float = 0.1, clearance: float = 4.0) -> Dictionary:
	return {"poi_id": "poi-1", "candidate_id": "candidate-1", "slope": slope, "clearance_radius": clearance, "max_slope": 0.25, "required_clearance_radius": 2.0}

func _fallback() -> Dictionary:
	return {"directive_id": "fixture-1", "placements": []}

func test_accepts_feasible_selected_poi() -> void:
	var result: Dictionary = FeasibilityScript.evaluate(_directive(), [_poi()], _fallback())
	assert_eq(result["outcome"], FeasibilityScript.OUTCOME_OK)
	assert_eq(result["placements"].size(), 1)

func test_rejects_slope_and_returns_whole_fallback() -> void:
	var result: Dictionary = FeasibilityScript.evaluate(_directive(), [_poi(0.5)], _fallback())
	assert_eq(result["outcome"], FeasibilityScript.OUTCOME_FALLBACK)
	assert_eq(result["reason"], "slope_infeasible")
	assert_eq(result["directive"]["directive_id"], "fixture-1")

func test_rejects_clearance_and_malformed_input() -> void:
	var result: Dictionary = FeasibilityScript.evaluate(_directive(), [_poi(0.1, 0.5)], _fallback())
	assert_eq(result["reason"], "clearance_infeasible")
	result = FeasibilityScript.evaluate({}, [_poi()], _fallback())
	assert_eq(result["reason"], "invalid_directive")

func test_rejects_out_of_range_metrics() -> void:
	var result: Dictionary = FeasibilityScript.evaluate(_directive(), [_poi(-0.1)], _fallback())
	assert_eq(result["reason"], "slope_out_of_range")
	result = FeasibilityScript.evaluate(_directive(), [_poi(0.1, 40.0)], _fallback())
	assert_eq(result["reason"], "clearance_radius_out_of_range")