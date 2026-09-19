extends GutTest
## Slice 140 (Phase 15, P-016-A/G): the server-authoritative embodiment
## progression service composing the vessel + all five subsystems into one
## presentation-safe snapshot. End-to-end, deterministic, deduplicated. This is
## the Phase 15 exit-gate assertion. See
## docs/adr/0006-versioned-embodiment-mechanics-architecture.md.

const ServiceScript: Script = preload("res://server/embodiment_progression_service.gd")
const EmbodimentTuningScript: Script = preload("res://server/embodiment_tuning.gd")
const SchemaScript: Script = preload("res://shared/embodiment_tuning_schema.gd")


func _tuning() -> Object:
	return EmbodimentTuningScript.resolve(EmbodimentTuningScript.DEFAULT_TUNING_VERSION)["tuning"]


func _service() -> Object:
	var service: Object = ServiceScript.new()
	service.create_character("hero", _tuning())
	return service


func test_baseline_snapshot_composes_all_subsystems_neutrally() -> void:
	var snapshot: Object = _service().effective_snapshot("hero", _tuning(), 0)
	var derived: Dictionary = snapshot.derived
	assert_eq(derived["friction_profile"], "none", "a balanced vessel has no friction profile")
	assert_almost_eq(float(derived["kinetic_energy_cost_factor"]), 1.0, 0.0001, "balanced kinetic flow is efficient")
	assert_eq((derived["meridian_unlocks"] as Dictionary).size(), 0, "no meridians touched yet")
	assert_eq((derived["burnout_active_pathways"] as Array).size(), 0, "no active burnout")


func test_accepted_training_shifts_the_vessel_and_snapshot() -> void:
	var service: Object = _service()
	assert_eq(service.accept_training("hero", "STR", "ev1", 6.0, _tuning())["outcome"], "ok")
	var axes: Dictionary = service.effective_snapshot("hero", _tuning(), 0).to_presentation_snapshot()["graph_axes"]
	assert_true(float(axes["STR"]) > float(axes["DEX"]), "the trained node dominates the replicated graph")


func test_training_evidence_is_deduplicated() -> void:
	var service: Object = _service()
	service.accept_training("hero", "STR", "ev1", 6.0, _tuning())
	var replay: Dictionary = service.accept_training("hero", "STR", "ev1", 6.0, _tuning())
	assert_eq(replay["outcome"], "duplicate_evidence", "a replayed training id does not double-apply")
	assert_almost_eq(float(service.effective_snapshot("hero", _tuning(), 0).effective_nodes["STR"]), 16.0, 0.0001)


func test_fragile_agility_build_shows_in_the_snapshot() -> void:
	var service: Object = _service()
	# Train DEX to the opposers' floors: DEX 40, CON 4 -> Fragile Agility.
	service.accept_training("hero", "DEX", "ev1", 30.0, _tuning())
	assert_eq(service.effective_snapshot("hero", _tuning(), 0).derived["friction_profile"], "fragile_agility")


func test_meridian_evidence_unlocks_and_shows_in_the_snapshot() -> void:
	var service: Object = _service()
	service.record_meridian_evidence("hero", "spark", "m1", 100.0, _tuning())
	var unlocks: Dictionary = service.effective_snapshot("hero", _tuning(), 0).derived["meridian_unlocks"]
	assert_true(bool(unlocks["spark"]), "the unlocked pathway shows in the snapshot")


func test_active_burnout_shows_then_clears_in_the_snapshot() -> void:
	var service: Object = _service()
	service.begin_burnout("hero", "b1", "spark", "surge-1", 100, _tuning())
	var during: Array = service.effective_snapshot("hero", _tuning(), 150).derived["burnout_active_pathways"]
	assert_true(during.has("spark"), "the burned pathway is active mid-window")
	var after: Array = service.effective_snapshot("hero", _tuning(), 400).derived["burnout_active_pathways"]
	assert_false(after.has("spark"), "the burnout has cleared after its window")


func test_magic_resolves_against_the_current_vessel() -> void:
	var service: Object = _service()
	# Baseline (insulation 20) channels a low tier.
	assert_eq(service.resolve_magic("hero", 1, _tuning())["outcome"], "CHANNELED")


func test_snapshot_derivation_is_deterministic() -> void:
	var service: Object = _service()
	service.accept_training("hero", "STR", "ev1", 6.0, _tuning())
	var a: Dictionary = service.effective_snapshot("hero", _tuning(), 50).to_presentation_snapshot()
	var b: Dictionary = service.effective_snapshot("hero", _tuning(), 50).to_presentation_snapshot()
	assert_eq(a, b, "the same state + tuning + tick derives an identical snapshot")


func test_snapshot_is_presentation_safe() -> void:
	var presentation: Dictionary = _service().effective_snapshot("hero", _tuning(), 0).to_presentation_snapshot()
	assert_false(presentation.has("effective_nodes"), "raw effective numbers never cross to the client")
	assert_true(presentation.has("graph_axes"), "only the normalized graph + derived results cross")


func test_unknown_character_fails_closed() -> void:
	var service: Object = ServiceScript.new()
	assert_eq(service.accept_training("ghost", "STR", "ev1", 1.0, _tuning())["outcome"], "unknown_character")
	assert_null(service.effective_snapshot("ghost", _tuning(), 0))
