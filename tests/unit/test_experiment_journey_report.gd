extends GutTest
## Slice 1325: #1137 consolidated experiment report semantics. Missing
## observations fail as OBSERVATION_FAILED and are never coerced to zero;
## parity comes from direct comparisons, not hashes or counts.

const ReportScript: Script = preload("res://server/experiment_journey_report.gd")
const CanonEntityGuidScript: Script = preload("res://shared/canon_entity_guid.gd")

var _dir: String = ""


func before_each() -> void:
	_dir = "user://test_experiment_journey_report_%d_%d" % [Time.get_ticks_usec(), randi()]


func after_each() -> void:
	var absolute: String = ProjectSettings.globalize_path(_dir)
	for name: String in DirAccess.get_files_at(absolute):
		DirAccess.remove_absolute("%s/%s" % [absolute, name])
	DirAccess.remove_absolute(absolute)


func _journey_id(name: String) -> String:
	return CanonEntityGuidScript.uuid_v5(CanonEntityGuidScript.NAMESPACE_URL_UUID, name)


func _reload(journey_id: String) -> Dictionary:
	return {"event_type": "CANON_SECTOR_RELOADED", "journey_id": journey_id, "sector_id": "starting_town_hub", "spatial_guid": "spatial-1"}


func _snapshot() -> Dictionary:
	return {
		"base_json": "{\"sector_id\":\"starting_town_hub\"}",
		"mutations": [{"applied_revision": 1, "mutation_kind": "unlock_gate", "target_guid": "structure-gate", "payload": {"unlocked": true}}],
		"entities": {"structure-gate": {"kind": "locked_gate", "x": 0, "y": -5, "unlocked": true}},
	}


func _report_input() -> Dictionary:
	var a: String = _journey_id("a")
	var b: String = _journey_id("b")
	return {
		"experiment_id": 1234,
		"timestamp_ms": 1000,
		"scenario": {"name": "orderly_restart", "expected_commit": ReportScript.COMMIT_SUCCESS},
		"commit": {"status": ReportScript.OBSERVED, "outcome": ReportScript.COMMIT_SUCCESS},
		"sector": {"sector_id": "starting_town_hub", "generation_count": 0, "canon_write_count": 0},
		"journeys": [
			{"journey_id": a, "player_guid": "character-a", "generation_count": 0, "canon_write_count": 0, "reload_events": [_reload(a)]},
			{"journey_id": b, "player_guid": "character-b", "generation_count": 0, "canon_write_count": 0, "reload_events": [_reload(b)]},
		],
		"snapshot": {"expected": _snapshot(), "actual": _snapshot()},
		"runtime_errors": [],
	}


func test_complete_matching_recovery_passes() -> void:
	var report: Dictionary = ReportScript.build(_report_input())
	assert_true(report["passed"])
	assert_eq(report["outcome"], ReportScript.OUTCOME_PASSED)
	assert_eq(report["recovery_outcome"], ReportScript.RECOVERY_PARITY_MATCH)
	assert_null(report["first_failing_stage"])
	assert_false(report.has("journey_id"), "no shared top-level journey id")
	assert_eq(report["journey_entries"].size(), 2)
	for domain: String in ["base_blueprint_parity", "mutation_records_parity", "reconstructed_entity_state_parity"]:
		assert_true(report["snapshot_comparison"][domain]["exact_match"], domain)


func test_missing_player_count_is_not_coerced_to_zero() -> void:
	var input: Dictionary = _report_input()
	input["journeys"][1].erase("canon_write_count")
	var report: Dictionary = ReportScript.build(input)
	assert_false(report["passed"])
	assert_eq(report["outcome"], ReportScript.OUTCOME_OBSERVATION_FAILED)
	assert_eq(report["first_failing_stage"], ReportScript.STAGE_PLAYER_COUNTS)
	assert_null(report["journey_entries"][1]["canon_write_count"])
	assert_eq(report["journey_entries"][1]["observation_status"], ReportScript.NOT_OBSERVED)


func test_shared_or_legacy_journey_ids_fail_identity() -> void:
	var input: Dictionary = _report_input()
	input["journeys"][1]["journey_id"] = input["journeys"][0]["journey_id"]
	assert_eq(ReportScript.build(input)["first_failing_stage"], ReportScript.STAGE_JOURNEY_IDENTITY)
	input = _report_input()
	input["journeys"][0]["journey_id"] = "journey-4"
	var report: Dictionary = ReportScript.build(input)
	assert_eq(report["first_failing_stage"], ReportScript.STAGE_JOURNEY_IDENTITY)
	assert_eq(report["journey_entries"][0]["journey_id"], "journey-4", "observed ids are reported, never rewritten")


func test_reordered_mutations_fail_parity_with_ordered_comparison() -> void:
	var input: Dictionary = _report_input()
	var second: Dictionary = {"applied_revision": 2, "mutation_kind": "loot", "target_guid": "x", "payload": {}}
	input["snapshot"]["expected"]["mutations"].append(second)
	input["snapshot"]["actual"]["mutations"].push_front(second)
	var report: Dictionary = ReportScript.build(input)
	var parity: Dictionary = report["snapshot_comparison"]["mutation_records_parity"]
	assert_false(parity["exact_match"])
	assert_eq(parity["status"], ReportScript.MISMATCH)
	assert_eq(report["recovery_outcome"], ReportScript.RECOVERY_FAILED)
	assert_eq(report["first_failing_stage"], ReportScript.STAGE_MUTATION_PARITY)


func test_entity_field_difference_is_listed() -> void:
	var input: Dictionary = _report_input()
	input["snapshot"]["actual"]["entities"]["structure-gate"]["unlocked"] = false
	var parity: Dictionary = ReportScript.build(input)["snapshot_comparison"]["reconstructed_entity_state_parity"]
	assert_false(parity["exact_match"])
	assert_eq(parity["entity_diffs"], [{"guid": "structure-gate", "field": "unlocked", "expected": true, "actual": false}])


func test_missing_snapshot_is_observation_failure_not_mismatch() -> void:
	var input: Dictionary = _report_input()
	input["snapshot"]["actual"].erase("entities")
	var report: Dictionary = ReportScript.build(input)
	var parity: Dictionary = report["snapshot_comparison"]["reconstructed_entity_state_parity"]
	assert_eq(parity["status"], ReportScript.NOT_OBSERVED)
	assert_eq(report["recovery_outcome"], ReportScript.OUTCOME_OBSERVATION_FAILED)


func test_rollback_passes_only_for_declared_pre_commit_scenario() -> void:
	var input: Dictionary = _report_input()
	input["scenario"]["expected_commit"] = ReportScript.COMMIT_ROLLED_BACK
	input["commit"]["outcome"] = ReportScript.COMMIT_ROLLED_BACK
	assert_true(ReportScript.build(input)["passed"], "expected pre-commit rollback passes")
	input = _report_input()
	input["commit"]["outcome"] = ReportScript.COMMIT_ROLLED_BACK
	var report: Dictionary = ReportScript.build(input)
	assert_false(report["passed"], "rollback after a confirmed commit fails")
	assert_eq(report["first_failing_stage"], ReportScript.STAGE_COMMIT)


func test_unobserved_commit_is_not_inferred_as_rollback() -> void:
	var input: Dictionary = _report_input()
	input["commit"] = {}
	var report: Dictionary = ReportScript.build(input)
	assert_eq(report["commit_outcome"], ReportScript.OUTCOME_OBSERVATION_FAILED)
	assert_eq(report["first_failing_stage"], ReportScript.STAGE_COMMIT)


func test_unattributed_sector_canon_write_fails_even_when_players_are_zero() -> void:
	var input: Dictionary = _report_input()
	input["sector"]["canon_write_count"] = 1
	var report: Dictionary = ReportScript.build(input)
	assert_false(report["passed"])
	assert_eq(report["first_failing_stage"], ReportScript.STAGE_SECTOR_TOTALS)


func test_each_player_needs_exactly_one_own_reload_event() -> void:
	var input: Dictionary = _report_input()
	input["journeys"][0]["reload_events"].append(_reload(input["journeys"][0]["journey_id"]))
	assert_eq(ReportScript.build(input)["first_failing_stage"], ReportScript.STAGE_RELOAD_EVENTS)
	input = _report_input()
	input["journeys"][1]["reload_events"] = [_reload(input["journeys"][0]["journey_id"])]
	assert_eq(ReportScript.build(input)["first_failing_stage"], ReportScript.STAGE_RELOAD_EVENTS)


func test_unrequired_stages_are_not_exercised_and_cannot_claim_recovery() -> void:
	var input: Dictionary = _report_input()
	input["scenario"]["required_stages"] = [ReportScript.STAGE_JOURNEY_IDENTITY, ReportScript.STAGE_COMMIT]
	input.erase("snapshot")
	var report: Dictionary = ReportScript.build(input)
	assert_true(report["passed"])
	assert_eq(report["recovery_outcome"], ReportScript.NOT_EXERCISED)
	assert_eq(report["snapshot_comparison"]["base_blueprint_parity"]["status"], ReportScript.NOT_EXERCISED)


func test_write_uses_contract_name_and_never_overwrites() -> void:
	var report: Dictionary = ReportScript.build(_report_input())
	var written: Dictionary = ReportScript.write(report, _dir)
	assert_eq(written["outcome"], ReportScript.WRITE_OK)
	assert_eq(String(written["path"]).get_file(), "exp_1137_journey_report_1000.json")
	assert_eq(JSON.parse_string(FileAccess.get_file_as_string(written["path"]))["outcome"], ReportScript.OUTCOME_PASSED)
	assert_eq(ReportScript.write(report, _dir)["outcome"], ReportScript.WRITE_EXISTS)


func test_required_case_assertions_fail_when_any_assertion_fails_or_is_missing() -> void:
	var input: Dictionary = _report_input()
	input["scenario"]["required_stages"] = [ReportScript.STAGE_JOURNEY_IDENTITY, ReportScript.STAGE_COMMIT, ReportScript.STAGE_CASE_ASSERTIONS]
	input["case_assertions"] = [{"name": "rejected", "passed": true}, {"name": "no write", "passed": false}]
	assert_eq(ReportScript.build(input)["first_failing_stage"], ReportScript.STAGE_CASE_ASSERTIONS)
	input.erase("case_assertions")
	assert_eq(ReportScript.build(input)["outcome"], ReportScript.OUTCOME_OBSERVATION_FAILED)
	input["case_assertions"] = [{"name": "rejected", "passed": true}]
	input["commit"] = {"status": ReportScript.OBSERVED, "outcome": ReportScript.COMMIT_NOT_ATTEMPTED}
	input["scenario"]["expected_commit"] = ReportScript.COMMIT_NOT_ATTEMPTED
	assert_true(ReportScript.build(input)["passed"], "an observed non-attempt passes a declared rejection case")


func test_case_assertions_are_not_required_by_default() -> void:
	assert_eq(ReportScript.build(_report_input())["stage_status"][ReportScript.STAGE_CASE_ASSERTIONS], ReportScript.NOT_EXERCISED)
