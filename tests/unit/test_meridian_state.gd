extends GutTest
## Slice 137 (Phase 15, P-016-D): Meridian pathway progress + idempotent unlock
## (shared/meridian_state.gd). Progress is driven by deduplicated cross-training
## evidence; replaying an id cannot progress or re-unlock. See
## docs/SYSTEMS-SPECIFICATION.md ("Meridian Pathways").

const MeridianStateScript: Script = preload("res://shared/meridian_state.gd")
const EmbodimentTuningScript: Script = preload("res://server/embodiment_tuning.gd")


func _tuning() -> Object:
	return EmbodimentTuningScript.resolve(EmbodimentTuningScript.DEFAULT_TUNING_VERSION)["tuning"]


func test_pathways_channel_between_two_nodes() -> void:
	assert_eq(MeridianStateScript.nodes_for("impact"), ["STR", "CON"])
	assert_eq(MeridianStateScript.nodes_for("flow"), ["DEX", "WIS"])
	assert_eq(MeridianStateScript.nodes_for("spark"), ["STR", "DEX"])


func test_evidence_accumulates_progress() -> void:
	var meridian: Object = MeridianStateScript.new("impact")
	var result: Dictionary = meridian.record_evidence("e1", 30.0, _tuning())
	assert_eq(result["outcome"], "ok")
	assert_true(result["progressed"])
	assert_almost_eq(meridian.progress, 30.0, 0.0001)
	assert_false(meridian.is_unlocked(), "below the threshold it stays locked")


func test_reaching_the_threshold_unlocks_once() -> void:
	var meridian: Object = MeridianStateScript.new("flow")
	meridian.record_evidence("e1", 60.0, _tuning())
	var crossing: Dictionary = meridian.record_evidence("e2", 40.0, _tuning())  # total 100 == threshold
	assert_true(crossing["newly_unlocked"], "crossing the threshold unlocks")
	assert_true(meridian.is_unlocked())


func test_replaying_the_same_evidence_is_idempotent() -> void:
	var meridian: Object = MeridianStateScript.new("spark")
	meridian.record_evidence("e1", 50.0, _tuning())
	var replay: Dictionary = meridian.record_evidence("e1", 50.0, _tuning())
	assert_eq(replay["outcome"], "duplicate_evidence", "a seen id is a no-op")
	assert_false(replay["progressed"])
	assert_almost_eq(meridian.progress, 50.0, 0.0001, "replay does not increment progress")


func test_unlock_is_durable_and_does_not_re_emit() -> void:
	var meridian: Object = MeridianStateScript.new("impact")
	meridian.record_evidence("e1", 100.0, _tuning())  # unlocks
	assert_true(meridian.is_unlocked())
	var after: Dictionary = meridian.record_evidence("e2", 50.0, _tuning())
	assert_false(after["newly_unlocked"], "further evidence does not re-emit the unlock")
	assert_true(meridian.is_unlocked(), "the unlock is durable")


func test_rejects_malformed_evidence() -> void:
	var meridian: Object = MeridianStateScript.new("impact")
	assert_eq(meridian.record_evidence("", 10.0, _tuning())["outcome"], "malformed")
	assert_eq(meridian.record_evidence("e1", 0.0, _tuning())["outcome"], "malformed")
	assert_eq(meridian.record_evidence("e2", -5.0, _tuning())["outcome"], "malformed")


func test_rejects_an_unsupported_pathway() -> void:
	var meridian: Object = MeridianStateScript.new("nonexistent")
	assert_eq(meridian.record_evidence("e1", 10.0, _tuning())["outcome"], "unsupported_pathway")


func test_tuning_exposes_the_meridian_namespace() -> void:
	assert_almost_eq(float(_tuning().meridian()["unlock_threshold"]), 100.0, 0.0001)
