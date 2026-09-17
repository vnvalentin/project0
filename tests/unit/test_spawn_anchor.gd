extends GutTest
## Slice 124 (Phase 14): public-seam tests for the spawn-anchor / NPC-population
## contract. A fixed anchor refills a role after a pressure-scaled DELAY (never
## an instant clone), sourcing a silent promotion of an ambient NPC when
## available or a newly generated identity otherwise; parsing fails closed.

const SpawnAnchorScript: Script = preload("res://shared/spawn_anchor.gd")


func _wire(desired: int, current: int, delay: int) -> Dictionary:
	return {
		"schema_version": 1,
		"anchor_id": "guard_post_north",
		"role": "guard",
		"desired_capacity": desired,
		"current_occupancy": current,
		"replacement_delay_ticks": delay,
	}


func _anchor(desired: int, current: int, delay: int) -> Object:
	return SpawnAnchorScript.from_wire_dict(_wire(desired, current, delay))["anchor"]


func test_deficit_is_unfilled_slots_and_floors_at_zero() -> void:
	assert_eq(SpawnAnchorScript.deficit(3, 1), 2)
	assert_eq(SpawnAnchorScript.deficit(2, 5), 0)


func test_effective_delay_scales_with_pressure() -> void:
	# No pressure keeps the full delay; full pressure refills immediately.
	assert_eq(SpawnAnchorScript.effective_delay(100, 0.0), 100)
	assert_eq(SpawnAnchorScript.effective_delay(100, 1.0), 0)
	assert_eq(SpawnAnchorScript.effective_delay(100, 0.25), 75)


func test_is_replacement_due_needs_deficit_and_elapsed_delay() -> void:
	# No deficit -> never due.
	assert_false(SpawnAnchorScript.is_replacement_due(0, 999, 10))
	# Deficit but delay not yet elapsed.
	assert_false(SpawnAnchorScript.is_replacement_due(1, 5, 10))
	# Deficit and delay elapsed.
	assert_true(SpawnAnchorScript.is_replacement_due(1, 10, 10))


func test_replacement_source_promotes_or_generates() -> void:
	assert_eq(SpawnAnchorScript.replacement_source(true), "promote")
	assert_eq(SpawnAnchorScript.replacement_source(false), "generate")


func test_vacate_reduces_occupancy_and_floors_at_zero() -> void:
	var anchor: Object = _anchor(3, 3, 50)
	anchor.vacate(1)
	assert_eq(anchor.current_occupancy, 2)
	assert_true(anchor.is_understaffed())
	anchor.vacate(10)
	assert_eq(anchor.current_occupancy, 0)


func test_fill_increases_occupancy_and_caps_at_desired() -> void:
	var anchor: Object = _anchor(2, 0, 50)
	anchor.fill()
	assert_eq(anchor.current_occupancy, 1)
	anchor.fill()
	anchor.fill()
	assert_eq(anchor.current_occupancy, 2, "occupancy caps at desired capacity")


func test_advance_accumulates_when_understaffed_and_resets_when_full() -> void:
	var anchor: Object = _anchor(2, 1, 50)
	anchor.advance(30)
	assert_eq(anchor.ticks_since_vacancy, 30)
	# Ignores non-positive ticks.
	anchor.advance(-5)
	assert_eq(anchor.ticks_since_vacancy, 30)
	anchor.fill()
	anchor.advance(10)
	assert_eq(anchor.ticks_since_vacancy, 0, "clock resets once fully staffed")


func test_plan_replacement_not_due_before_delay() -> void:
	var anchor: Object = _anchor(2, 1, 100)
	anchor.advance(50)
	var plan: Dictionary = anchor.plan_replacement(0.0, false)
	assert_false(plan["due"])
	assert_eq(plan["source"], "none")


func test_plan_replacement_generates_new_identity_under_pressure() -> void:
	var anchor: Object = _anchor(2, 1, 100)
	anchor.advance(50)
	# Half pressure halves the delay to 50, which the clock has reached.
	var plan: Dictionary = anchor.plan_replacement(0.5, false)
	assert_true(plan["due"])
	assert_eq(plan["source"], "generate")


func test_plan_replacement_promotes_ambient_candidate() -> void:
	var anchor: Object = _anchor(2, 0, 0)
	anchor.advance(1)
	var plan: Dictionary = anchor.plan_replacement(0.0, true)
	assert_true(plan["due"])
	assert_eq(plan["source"], "promote")


func test_from_wire_dict_accepts_valid_anchor() -> void:
	var result: Dictionary = SpawnAnchorScript.from_wire_dict(_wire(3, 2, 60))
	assert_eq(result["outcome"], "ok")
	var anchor: Object = result["anchor"]
	assert_eq(anchor.role, "guard")
	assert_eq(anchor.current_deficit(), 1)


func test_from_wire_dict_rejects_unsupported_version() -> void:
	var wire: Dictionary = _wire(2, 1, 10)
	wire["schema_version"] = 2
	assert_eq(SpawnAnchorScript.from_wire_dict(wire)["outcome"], "unsupported_version")


func test_from_wire_dict_rejects_empty_role() -> void:
	var wire: Dictionary = _wire(2, 1, 10)
	wire["role"] = ""
	assert_eq(SpawnAnchorScript.from_wire_dict(wire)["outcome"], "malformed")


func test_from_wire_dict_rejects_negative_count() -> void:
	assert_eq(SpawnAnchorScript.from_wire_dict(_wire(-1, 0, 10))["outcome"], "out_of_bounds")


func test_from_wire_dict_rejects_non_dictionary() -> void:
	var result: Dictionary = SpawnAnchorScript.from_wire_dict("not a dict")
	assert_eq(result["outcome"], "malformed")
	assert_null(result["anchor"])
