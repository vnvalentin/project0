extends GutTest
## Slice 123 (Phase 14): public-seam tests for the activity-routine contract.
## Which activity an NPC is doing is a pure function of elapsed ticks (off-screen
## simulation, route-consistent arrival, looping); an empty routine falls back to
## idle/patrol; interruptions override the current activity without losing the
## routine clock; parsing fails closed.

const ActivityRoutineScript: Script = preload("res://shared/activity_routine.gd")


func _steps() -> Array:
	return [
		{"activity_id": "forge", "duration_ticks": 10},
		{"activity_id": "market", "duration_ticks": 5},
		{"activity_id": "tavern", "duration_ticks": 15},
	]


func _routine(steps: Array = _steps(), fallback: String = "idle") -> Object:
	return ActivityRoutineScript.from_wire_dict(
		{"schema_version": 1, "steps": steps, "fallback_mode": fallback}
	)["routine"]


func test_total_duration_sums_steps() -> void:
	assert_eq(ActivityRoutineScript.total_duration(_steps()), 30)
	assert_eq(ActivityRoutineScript.total_duration([]), 0)


func test_resolve_step_at_start_and_midpoint() -> void:
	var at_start: Dictionary = ActivityRoutineScript.resolve_step(_steps(), 0)
	assert_eq(at_start["index"], 0)
	assert_eq(at_start["activity_id"], "forge")
	assert_eq(at_start["step_remaining"], 10)
	var midpoint: Dictionary = ActivityRoutineScript.resolve_step(_steps(), 4)
	assert_eq(midpoint["index"], 0)
	assert_eq(midpoint["step_elapsed"], 4)
	assert_eq(midpoint["step_remaining"], 6)


func test_resolve_step_crosses_boundary() -> void:
	# tick 10 is the first tick of the second step.
	var second: Dictionary = ActivityRoutineScript.resolve_step(_steps(), 10)
	assert_eq(second["index"], 1)
	assert_eq(second["activity_id"], "market")
	# tick 15 is the first tick of the third step.
	var third: Dictionary = ActivityRoutineScript.resolve_step(_steps(), 15)
	assert_eq(third["index"], 2)
	assert_eq(third["activity_id"], "tavern")


func test_resolve_step_loops_for_route_consistent_arrival() -> void:
	# Period is 30; tick 34 == tick 4 == mid-forge. Re-observing off-screen NPCs
	# lands exactly on the route with no drift.
	var looped: Dictionary = ActivityRoutineScript.resolve_step(_steps(), 34)
	assert_eq(looped["index"], 0)
	assert_eq(looped["activity_id"], "forge")
	assert_eq(looped["step_elapsed"], 4)


func test_resolve_step_empty_routine_has_no_step() -> void:
	var none: Dictionary = ActivityRoutineScript.resolve_step([], 7)
	assert_eq(none["index"], -1)
	assert_eq(none["activity_id"], "")


func test_current_activity_reports_routine_source() -> void:
	var routine: Object = _routine()
	var current: Dictionary = routine.current_activity(12)
	assert_eq(current["activity_id"], "market")
	assert_eq(current["source"], "routine")


func test_current_activity_falls_back_to_idle_when_empty() -> void:
	var routine: Object = _routine([], "idle")
	var current: Dictionary = routine.current_activity(999)
	assert_eq(current["activity_id"], "idle")
	assert_eq(current["source"], "fallback")


func test_current_activity_falls_back_to_patrol() -> void:
	var routine: Object = _routine([], "patrol")
	assert_eq(routine.current_activity(0)["activity_id"], "patrol")


func test_interrupt_overrides_current_activity() -> void:
	var routine: Object = _routine()
	routine.interrupt("flee_combat")
	assert_true(routine.is_interrupted())
	var current: Dictionary = routine.current_activity(4)
	assert_eq(current["activity_id"], "flee_combat")
	assert_eq(current["source"], "interrupt")


func test_resume_returns_to_route_consistent_activity() -> void:
	var routine: Object = _routine()
	routine.interrupt("flee_combat")
	routine.resume()
	assert_false(routine.is_interrupted())
	# The routine clock was untouched, so tick 4 is still mid-forge.
	assert_eq(routine.current_activity(4)["activity_id"], "forge")


func test_from_wire_dict_accepts_valid_routine() -> void:
	var result: Dictionary = ActivityRoutineScript.from_wire_dict(
		{"schema_version": 1, "steps": _steps(), "fallback_mode": "patrol"}
	)
	assert_eq(result["outcome"], "ok")
	assert_eq(result["routine"].steps.size(), 3)
	assert_eq(result["routine"].fallback_mode, "patrol")


func test_from_wire_dict_accepts_empty_routine_as_fallback() -> void:
	var result: Dictionary = ActivityRoutineScript.from_wire_dict(
		{"schema_version": 1, "steps": [], "fallback_mode": "idle"}
	)
	assert_eq(result["outcome"], "ok")
	assert_eq(result["routine"].steps.size(), 0)


func test_from_wire_dict_rejects_unsupported_version() -> void:
	var result: Dictionary = ActivityRoutineScript.from_wire_dict(
		{"schema_version": 2, "steps": _steps(), "fallback_mode": "idle"}
	)
	assert_eq(result["outcome"], "unsupported_version")


func test_from_wire_dict_rejects_unknown_fallback_mode() -> void:
	var result: Dictionary = ActivityRoutineScript.from_wire_dict(
		{"schema_version": 1, "steps": _steps(), "fallback_mode": "sprint"}
	)
	assert_eq(result["outcome"], "unsupported_fallback")


func test_from_wire_dict_rejects_non_positive_step_duration() -> void:
	var result: Dictionary = ActivityRoutineScript.from_wire_dict(
		{"schema_version": 1, "steps": [{"activity_id": "forge", "duration_ticks": 0}], "fallback_mode": "idle"}
	)
	assert_eq(result["outcome"], "out_of_bounds")


func test_from_wire_dict_rejects_non_dictionary() -> void:
	var result: Dictionary = ActivityRoutineScript.from_wire_dict("not a dict")
	assert_eq(result["outcome"], "malformed")
	assert_null(result["routine"])
