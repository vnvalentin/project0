extends GutTest
## Slice 135 (Phase 15, P-016-B): inverse biological friction derivation
## (shared/friction_modifier.gd). Massive Bulk (high STR + high CON) and Fragile
## Agility (high DEX + low CON) are derived deterministically from the effective
## nodes under the current friction tuning. See docs/SYSTEMS-SPECIFICATION.md.

const FrictionScript: Script = preload("res://shared/friction_modifier.gd")
const EmbodimentTuningScript: Script = preload("res://server/embodiment_tuning.gd")


func _tuning() -> Object:
	return EmbodimentTuningScript.resolve(EmbodimentTuningScript.DEFAULT_TUNING_VERSION)["tuning"]


func _nodes(str_v: float, dex_v: float, con_v: float) -> Dictionary:
	return {"STR": str_v, "DEX": dex_v, "CON": con_v, "INT": 10.0, "WIS": 10.0, "CHA": 10.0}


func test_balanced_vessel_has_no_friction_profile() -> void:
	var result: Dictionary = FrictionScript.derive(_nodes(10, 10, 10), _tuning())
	assert_eq(result["profile"], "none")
	assert_almost_eq(float(result["dodge_distance_factor"]), 1.0, 0.0001, "no dodge penalty")
	assert_almost_eq(float(result["windup_recovery_factor"]), 1.0, 0.0001)
	assert_eq(result["water_behavior"], "float")


func test_massive_bulk_shrinks_dodge_and_lengthens_recovery_and_sinks() -> void:
	# High STR and high CON (>= 16 each).
	var result: Dictionary = FrictionScript.derive(_nodes(18, 8, 18), _tuning())
	assert_eq(result["profile"], "massive_bulk")
	assert_almost_eq(float(result["dodge_distance_factor"]), 0.5, 0.0001, "dodge distance shrinks")
	assert_almost_eq(float(result["windup_recovery_factor"]), 1.5, 0.0001, "wind-down/recovery lengthen")
	assert_eq(result["water_behavior"], "sink", "buoyancy is removed")


func test_fragile_agility_regens_fast_and_zeroes_stagger_and_skips_water() -> void:
	# High DEX (>= 16) with shed structural mass (CON <= 6).
	var result: Dictionary = FrictionScript.derive(_nodes(8, 18, 4), _tuning())
	assert_eq(result["profile"], "fragile_agility")
	assert_almost_eq(float(result["stamina_regen_factor"]), 3.0, 0.0001, "stamina regenerates fast")
	assert_almost_eq(float(result["stagger_resistance_factor"]), 0.0, 0.0001, "stagger resistance is ~zero")
	assert_eq(result["water_behavior"], "skip_then_sink")


func test_high_str_without_high_con_is_not_massive_bulk() -> void:
	var result: Dictionary = FrictionScript.derive(_nodes(20, 8, 8), _tuning())
	assert_eq(result["profile"], "none", "bulk needs BOTH STR and CON high")


func test_high_dex_without_low_con_is_not_fragile() -> void:
	var result: Dictionary = FrictionScript.derive(_nodes(8, 20, 12), _tuning())
	assert_eq(result["profile"], "none", "fragile needs shed structural mass (low CON)")


func test_thresholds_are_boundaries() -> void:
	var tuning: Object = _tuning()
	# Exactly at the bulk threshold qualifies.
	assert_eq(FrictionScript.derive(_nodes(16, 8, 16), tuning)["profile"], "massive_bulk")
	# Just below does not.
	assert_eq(FrictionScript.derive(_nodes(15.9, 8, 16), tuning)["profile"], "none")


func test_tuning_exposes_the_friction_namespace() -> void:
	var params: Dictionary = _tuning().friction()
	assert_almost_eq(float(params["massive_bulk_threshold"]), 16.0, 0.0001)
	assert_almost_eq(float(params["fragile_con_ceiling"]), 6.0, 0.0001)
	assert_almost_eq(float(params["fragile_stamina_regen_factor"]), 3.0, 0.0001)
