extends GutTest
## Slice 139 (Phase 15, P-016-F): magic equilibrium (shared/magic_equilibrium.gd).
## Physical bulk (STR + CON) insulates and grounds magic; higher tiers demand a
## leaner vessel. A validated attempt resolves as CHANNELED/FIZZLE/BACKLASH/
## REJECTED with a bounded reason, never a client success. See
## docs/SYSTEMS-SPECIFICATION.md ("Magic Equilibrium And Opportunity Cost").

const MagicScript: Script = preload("res://shared/magic_equilibrium.gd")
const EmbodimentTuningScript: Script = preload("res://server/embodiment_tuning.gd")


func _tuning() -> Object:
	return EmbodimentTuningScript.resolve(EmbodimentTuningScript.DEFAULT_TUNING_VERSION)["tuning"]


func _nodes(str_v: float, con_v: float) -> Dictionary:
	return {"STR": str_v, "DEX": 10.0, "CON": con_v, "INT": 10.0, "WIS": 10.0, "CHA": 10.0}


func test_a_lean_vessel_channels_a_low_tier() -> void:
	# Insulation 20 (STR10+CON10) <= tier-1 ceiling 40.
	var result: Dictionary = MagicScript.resolve(_nodes(10, 10), 1, _tuning())
	assert_eq(result["outcome"], "CHANNELED")
	assert_eq(result["reason"], "")


func test_a_bulked_brute_fizzles_a_low_tier() -> void:
	# Insulation 50 (STR25+CON25): tier-1 ceiling 40, +12 margin = 52 -> fizzle.
	var result: Dictionary = MagicScript.resolve(_nodes(25, 25), 1, _tuning())
	assert_eq(result["outcome"], "FIZZLE")
	assert_eq(result["reason"], "insufficient_equilibrium")


func test_a_hyper_bulked_juggernaut_backlashes() -> void:
	# Insulation 60 (STR30+CON30) > ceiling 40 + margin 12 = 52 -> backlash.
	var result: Dictionary = MagicScript.resolve(_nodes(30, 30), 1, _tuning())
	assert_eq(result["outcome"], "BACKLASH")
	assert_eq(result["reason"], "insulation_overload")


func test_high_tier_demands_leaning_out() -> void:
	var tuning: Object = _tuning()
	# Tier-5 ceiling = 40 - 4*8 = 8. A baseline vessel (insulation 20) cannot
	# channel it (20 > 8; within margin 20 -> fizzle).
	assert_eq(MagicScript.resolve(_nodes(10, 10), 5, tuning)["outcome"], "FIZZLE")
	# A drastically leaned-out vessel (insulation 8) channels the high tier.
	assert_eq(MagicScript.resolve(_nodes(4, 4), 5, tuning)["outcome"], "CHANNELED")


func test_out_of_range_tier_is_rejected_never_silent() -> void:
	var tuning: Object = _tuning()
	assert_eq(MagicScript.resolve(_nodes(10, 10), 0, tuning)["outcome"], "REJECTED")
	assert_eq(MagicScript.resolve(_nodes(10, 10), 6, tuning)["outcome"], "REJECTED")
	assert_eq(MagicScript.resolve(_nodes(10, 10), 6, tuning)["reason"], "unsupported_tier")


func test_every_attempt_returns_an_explicit_outcome() -> void:
	var tuning: Object = _tuning()
	for tier: int in [1, 2, 3, 4, 5]:
		var result: Dictionary = MagicScript.resolve(_nodes(10, 10), tier, tuning)
		assert_true(result["outcome"] in ["CHANNELED", "FIZZLE", "BACKLASH", "REJECTED"], "tier %d yields an explicit outcome" % tier)


func test_insulation_comes_from_bulk() -> void:
	assert_almost_eq(MagicScript.insulation_for(_nodes(12, 18), _tuning()), 30.0, 0.0001, "insulation = STR + CON")


func test_tuning_exposes_the_magic_namespace() -> void:
	var params: Dictionary = _tuning().magic()
	assert_almost_eq(float(params["base_channel_ceiling"]), 40.0, 0.0001)
	assert_eq(int(params["max_tier"]), 5)
