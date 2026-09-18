extends GutTest
## Slice 138 (Phase 15, P-016-E): Biological Burnout (shared/burnout_instance.gd).
## An accepted Overload Surge burns a pathway for a bounded server-tick window,
## flattening that pathway's effective Control/DEX to zero until expiry, without
## touching base state. The lifecycle rejects impossible transitions. See
## docs/SYSTEMS-SPECIFICATION.md ("Biological Burnout").

const BurnoutScript: Script = preload("res://shared/burnout_instance.gd")
const EmbodimentTuningScript: Script = preload("res://server/embodiment_tuning.gd")


func _tuning() -> Object:
	return EmbodimentTuningScript.resolve(EmbodimentTuningScript.DEFAULT_TUNING_VERSION)["tuning"]


func _burnout(start_tick: int = 100) -> Object:
	return BurnoutScript.from_accepted_surge("b1", "spark", "surge-1", start_tick, _tuning())["burnout"]


func test_from_accepted_surge_computes_the_cooldown_window() -> void:
	var result: Dictionary = BurnoutScript.from_accepted_surge("b1", "spark", "surge-1", 100, _tuning())
	assert_eq(result["outcome"], "ok")
	var burnout: Object = result["burnout"]
	assert_eq(burnout.start_tick, 100)
	assert_eq(burnout.end_tick, 280, "end = start + duration (180)")
	assert_eq(burnout.tuning_version, _tuning().tuning_version)


func test_is_active_within_the_window_and_expires_after() -> void:
	var burnout: Object = _burnout(100)
	assert_false(burnout.is_active(99), "not active before it starts")
	assert_true(burnout.is_active(100), "active at the start tick")
	assert_true(burnout.is_active(279), "active on the last tick")
	assert_false(burnout.is_active(280), "not active at the end tick")
	assert_true(burnout.is_expired(280), "expired at the end tick")


func test_flattens_only_the_affected_pathway_while_active() -> void:
	var burnout: Object = _burnout(100)
	assert_almost_eq(burnout.control_multiplier_for("spark", 150), 0.0, 0.0001, "the burned pathway is flattened")
	assert_almost_eq(burnout.control_multiplier_for("flow", 150), 1.0, 0.0001, "other pathways are unaffected")
	assert_almost_eq(burnout.control_multiplier_for("spark", 300), 1.0, 0.0001, "restored after expiry")


func test_rejects_unsupported_pathway_and_malformed_ids() -> void:
	assert_eq(BurnoutScript.from_accepted_surge("b1", "nope", "s1", 0, _tuning())["outcome"], "unsupported_pathway")
	assert_eq(BurnoutScript.from_accepted_surge("", "spark", "s1", 0, _tuning())["outcome"], "malformed")
	assert_eq(BurnoutScript.from_accepted_surge("b1", "spark", "", 0, _tuning())["outcome"], "malformed")


func test_lifecycle_allows_the_normative_path() -> void:
	assert_true(BurnoutScript.valid_transition("READY", "SURGE_VALIDATING"))
	assert_true(BurnoutScript.valid_transition("SURGE_VALIDATING", "ACTIVE_SURGE"))
	assert_true(BurnoutScript.valid_transition("ACTIVE_SURGE", "BURNED_OUT"))
	assert_true(BurnoutScript.valid_transition("BURNED_OUT", "RECOVERED"))
	assert_true(BurnoutScript.valid_transition("RECOVERED", "READY"))
	assert_true(BurnoutScript.valid_transition("SURGE_VALIDATING", "REJECTED"))


func test_lifecycle_rejects_impossible_transitions() -> void:
	assert_false(BurnoutScript.valid_transition("READY", "BURNED_OUT"), "cannot skip validation")
	assert_false(BurnoutScript.valid_transition("ACTIVE_SURGE", "READY"), "cannot un-surge directly")
	assert_false(BurnoutScript.valid_transition("BURNED_OUT", "ACTIVE_SURGE"), "cannot re-surge from burnout")


func test_tuning_exposes_the_burnout_namespace() -> void:
	assert_eq(int(_tuning().burnout()["duration_ticks"]), 180)
