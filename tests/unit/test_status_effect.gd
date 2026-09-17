extends GutTest
## Slice 122 (Phase 14): public-seam tests for the status-effect contract. A
## deliberate magical/impairment effect is resistible (a strong enough
## resistance negates it at application) and removable (cleansed on demand or
## expired by duration); parsing fails closed. Ordinary damage never produces one.

const StatusEffectScript: Script = preload("res://shared/status_effect.gd")


func _wire(category: String, potency: float, magnitude: float, duration_ticks: int) -> Dictionary:
	return {
		"schema_version": 1,
		"effect_id": "slow",
		"category": category,
		"potency": potency,
		"magnitude": magnitude,
		"duration_ticks": duration_ticks,
	}


func test_is_resisted_when_resistance_meets_potency() -> void:
	# Resistance at or above potency fully resists.
	assert_true(StatusEffectScript.is_resisted(0.5, 0.5))
	assert_true(StatusEffectScript.is_resisted(0.5, 0.8))
	# Below potency, the effect is not resisted.
	assert_false(StatusEffectScript.is_resisted(0.5, 0.4))


func test_is_resisted_clamps_out_of_range_inputs() -> void:
	# Clamped inputs can never invert the comparison.
	assert_false(StatusEffectScript.is_resisted(0.5, -1.0))
	assert_true(StatusEffectScript.is_resisted(0.5, 2.0))


func test_lands_against_reflects_resistance() -> void:
	var effect: Object = StatusEffectScript.from_wire_dict(
		_wire("impairment", 0.6, 5.0, 10)
	)["effect"]
	assert_true(effect.lands_against(0.3), "weak resistance should let the effect land")
	assert_false(effect.lands_against(0.6), "strong resistance should negate the effect")


func test_advance_decrements_and_expires() -> void:
	var effect: Object = StatusEffectScript.from_wire_dict(_wire("magical", 0.5, 3.0, 5))["effect"]
	assert_false(effect.advance(2), "still active after partial duration")
	assert_eq(effect.remaining_ticks, 3)
	assert_true(effect.advance(10), "expired once duration is exhausted")
	assert_eq(effect.remaining_ticks, 0, "remaining floors at zero")


func test_advance_ignores_non_positive_ticks() -> void:
	var effect: Object = StatusEffectScript.from_wire_dict(_wire("magical", 0.5, 3.0, 5))["effect"]
	assert_false(effect.advance(0))
	assert_false(effect.advance(-4))
	assert_eq(effect.remaining_ticks, 5)


func test_remove_cleanses_immediately() -> void:
	var effect: Object = StatusEffectScript.from_wire_dict(_wire("magical", 0.5, 3.0, 100))["effect"]
	assert_true(effect.is_active())
	effect.remove()
	assert_false(effect.is_active())
	assert_true(effect.is_expired())


func test_from_wire_dict_accepts_magical_effect() -> void:
	var result: Dictionary = StatusEffectScript.from_wire_dict(_wire("magical", 0.7, 12.0, 40))
	assert_eq(result["outcome"], "ok")
	var effect: Object = result["effect"]
	assert_eq(effect.category, "magical")
	assert_eq(effect.remaining_ticks, 40)


func test_from_wire_dict_accepts_impairment_effect() -> void:
	var result: Dictionary = StatusEffectScript.from_wire_dict(_wire("impairment", 0.2, 1.0, 8))
	assert_eq(result["outcome"], "ok")
	assert_eq(result["effect"].category, "impairment")


func test_from_wire_dict_rejects_unsupported_version() -> void:
	var wire: Dictionary = _wire("magical", 0.5, 1.0, 10)
	wire["schema_version"] = 2
	assert_eq(StatusEffectScript.from_wire_dict(wire)["outcome"], "unsupported_version")


func test_from_wire_dict_rejects_unknown_category() -> void:
	assert_eq(StatusEffectScript.from_wire_dict(_wire("injury", 0.5, 1.0, 10))["outcome"], "unsupported_category")


func test_from_wire_dict_rejects_potency_out_of_range() -> void:
	assert_eq(StatusEffectScript.from_wire_dict(_wire("magical", 1.5, 1.0, 10))["outcome"], "out_of_bounds")


func test_from_wire_dict_rejects_non_positive_duration() -> void:
	assert_eq(StatusEffectScript.from_wire_dict(_wire("magical", 0.5, 1.0, 0))["outcome"], "out_of_bounds")


func test_from_wire_dict_rejects_non_dictionary() -> void:
	var result: Dictionary = StatusEffectScript.from_wire_dict("not a dict")
	assert_eq(result["outcome"], "malformed")
	assert_null(result["effect"])
