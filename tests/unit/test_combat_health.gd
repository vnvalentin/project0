extends GutTest
## Slice 120 (Phase 14): public-seam tests for the shared health/defeat/recovery
## contract. Damage floors at zero and never heals; recovery caps at max and
## never harms; defeat is zero health; the presentation fraction is 0..1; and
## parsing fails closed. No injury subsystem is modeled.

const CombatHealthScript: Script = preload("res://shared/combat_health.gd")


func _wire(max_health: float, current_health: float) -> Dictionary:
	return {"schema_version": 1, "max_health": max_health, "current_health": current_health}


func test_apply_damage_reduces_and_floors_at_zero() -> void:
	assert_almost_eq(CombatHealthScript.apply_damage(100.0, 30.0), 70.0, 0.0001)
	assert_almost_eq(CombatHealthScript.apply_damage(20.0, 100.0), 0.0, 0.0001)
	# Negative "damage" never heals.
	assert_almost_eq(CombatHealthScript.apply_damage(50.0, -10.0), 50.0, 0.0001)


func test_apply_recovery_heals_and_caps_at_max() -> void:
	assert_almost_eq(CombatHealthScript.apply_recovery(40.0, 100.0, 30.0), 70.0, 0.0001)
	assert_almost_eq(CombatHealthScript.apply_recovery(90.0, 100.0, 50.0), 100.0, 0.0001)
	# Negative "recovery" never harms.
	assert_almost_eq(CombatHealthScript.apply_recovery(50.0, 100.0, -10.0), 50.0, 0.0001)


func test_is_defeated_at_zero() -> void:
	assert_false(CombatHealthScript.is_defeated(1.0))
	assert_true(CombatHealthScript.is_defeated(0.0))


func test_health_fraction_is_bounded_and_fails_safe() -> void:
	assert_almost_eq(CombatHealthScript.health_fraction(50.0, 100.0), 0.5, 0.0001)
	assert_almost_eq(CombatHealthScript.health_fraction(200.0, 100.0), 1.0, 0.0001)
	assert_almost_eq(CombatHealthScript.health_fraction(10.0, 0.0), 0.0, 0.0001)


func test_instance_take_damage_and_heal_mutate_and_report_defeat() -> void:
	var h: Object = CombatHealthScript.from_wire_dict(_wire(100.0, 100.0))["health"]
	assert_false(h.take_damage(40.0))
	assert_almost_eq(h.current_health, 60.0, 0.0001)
	assert_true(h.take_damage(60.0), "reaching zero reports defeat")
	assert_true(h.is_now_defeated())
	h.heal(25.0)
	assert_almost_eq(h.current_health, 25.0, 0.0001)
	assert_false(h.is_now_defeated())
	assert_almost_eq(h.fraction(), 0.25, 0.0001)


func test_from_wire_dict_accepts_valid_pool() -> void:
	var result: Dictionary = CombatHealthScript.from_wire_dict(_wire(120.0, 80.0))
	assert_eq(result["outcome"], "ok")
	assert_almost_eq(result["health"].max_health, 120.0, 0.0001)


func test_from_wire_dict_rejects_unsupported_version() -> void:
	var wire: Dictionary = _wire(100.0, 100.0)
	wire["schema_version"] = 999
	var result: Dictionary = CombatHealthScript.from_wire_dict(wire)
	assert_eq(result["outcome"], "unsupported_version")
	assert_null(result["health"])


func test_from_wire_dict_rejects_non_positive_max() -> void:
	var result: Dictionary = CombatHealthScript.from_wire_dict(_wire(0.0, 0.0))
	assert_eq(result["outcome"], "out_of_bounds")


func test_from_wire_dict_rejects_current_above_max() -> void:
	var result: Dictionary = CombatHealthScript.from_wire_dict(_wire(100.0, 150.0))
	assert_eq(result["outcome"], "out_of_bounds")


func test_from_wire_dict_rejects_negative_current() -> void:
	var result: Dictionary = CombatHealthScript.from_wire_dict(_wire(100.0, -5.0))
	assert_eq(result["outcome"], "out_of_bounds")


func test_from_wire_dict_rejects_non_finite() -> void:
	var wire: Dictionary = _wire(100.0, 100.0)
	wire["current_health"] = INF
	var result: Dictionary = CombatHealthScript.from_wire_dict(wire)
	assert_eq(result["outcome"], "out_of_bounds")


func test_from_wire_dict_rejects_non_dictionary() -> void:
	var result: Dictionary = CombatHealthScript.from_wire_dict("nope")
	assert_eq(result["outcome"], "malformed")
