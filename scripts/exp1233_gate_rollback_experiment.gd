extends "res://scripts/exp1232_gate_ordering_experiment.gd"
## Experiment #1233 orchestrator (Linux host only): a failed-validation or
## really rolled-back first request claims nothing, leaves the locked baseline
## intact, and does not block the next valid request.
##   godot --headless --path . -s scripts/exp1233_gate_rollback_experiment.gd

const CASES_1233: Array[Dictionary] = [
	{"id": "validation_failure_first", "next": "occluder"},
	{"id": "rollback_first", "next": "occluder"},
	{"id": "rollback_then_same_actor_retry", "next": "actor"},
]


func _experiment_id() -> int:
	return 1233


func _cases() -> Array[Dictionary]:
	return CASES_1233


func _fixture_script() -> String:
	return "scripts/exp1233_gate_fixture.gd"


func _client_script() -> String:
	return "scripts/exp1233_client.gd"


func _report_input(case: Dictionary, timestamp_ms: int, observation: Variant, actor: Variant, occluder: Variant, runtime_errors: Array, server_ready: bool) -> Dictionary:
	var obs: Dictionary = observation if observation is Dictionary else {}
	var bound: Dictionary = obs.get("bound", {})
	var records: Array = obs.get("resolutions", [])
	var clients: Dictionary = {"actor": actor if actor is Dictionary else {}, "occluder": occluder if occluder is Dictionary else {}}
	var rollback: bool = case["id"] != "validation_failure_first"
	var retry: bool = case["id"] == "rollback_then_same_actor_retry"
	var first: Dictionary = records[0] if not records.is_empty() else {}
	var next: Dictionary = records[1] if records.size() > 1 else {}
	var first_resolution: Variant = first.get("resolution")
	var assertions: Array[Dictionary] = []
	_check(assertions, "server became ready", server_ready, true)
	_check(assertions, "actor client entered world", clients["actor"].get("entered"), true)
	_check(assertions, "second actor client entered world", clients["occluder"].get("entered"), true)
	_check(assertions, "Canon store journal_mode is WAL", String((records.back().get("after", {}) if not records.is_empty() else {}).get("journal_mode", "")).to_lower(), "wal")
	_check(assertions, "server receive order", _roles(obs.get("received", [])), ["actor", "actor", "occluder"] if retry else ["actor", "occluder"])
	_check(assertions, "failed first request is not reported as success", first_resolution.get("status") if first_resolution is Dictionary else null, "rejected")
	_check(assertions, "actor client received the rejection", _client_status(clients["actor"], 0)[0] if _client_status(clients["actor"], 0) is Array else null, "rejected")
	if rollback:
		var fault: Dictionary = first.get("fault", {})
		_check(assertions, "fault armed on the Canon connection", fault.get("armed"), true)
		_check(assertions, "fault removed before the next request", fault.get("disarmed"), true)
		_check(assertions, "no fault objects remain", fault.get("temp_objects_after"), 0)
		_check(assertions, "first request failed in the transaction", first_resolution.get("reason") if first_resolution is Dictionary else null, "transaction_failed")
		_check(assertions, "rolled-back transaction attempted the unlock INSERT (not reported as zero)", _record_delta(records, 0, "attempted"), 1)
		_check(assertions, "the attempted INSERT was rolled back", _record_delta(records, 0, "rolled_back"), 1)
	else:
		_check(assertions, "first request failed validation (out of reach)", first_resolution.get("reason") if first_resolution is Dictionary else null, "out_of_reach")
		_check(assertions, "failed validation attempted no Canon INSERT/UPDATE", _record_delta(records, 0, "attempted"), 0)
	_check(assertions, "first request committed nothing", _record_delta(records, 0, "committed"), 0)
	_check(assertions, "baseline revision unchanged after the failure", first.get("after", {}).get("revision"), 0)
	_check(assertions, "baseline ledger has no unlock row after the failure", (first.get("after", {}).get("mutations", [null]) as Array).size(), 0)
	_check(assertions, "baseline gate still locked after the failure", (first.get("after", {}).get("effective_gate", {}) if first.get("after", {}).get("effective_gate") is Dictionary else {}).get("unlocked", false), false)
	_check(assertions, "next valid request evaluated the unchanged baseline", [next.get("before", {}).get("revision"), (next.get("before", {}).get("mutations", [null]) as Array).size()], [0.0, 0])
	_check(assertions, "next valid request committed exactly one INSERT", _record_delta(records, 1, "committed"), 1)
	_check(assertions, "next valid request accepted only after COMMIT", _accepted_after_commit(records, 1), true)
	var rows: Array = records.back().get("after", {}).get("mutations", []) if not records.is_empty() else []
	_check(assertions, "exactly one durable unlock_gate row", rows.size(), 1)
	_check(assertions, "committed row actor is the next valid requester", rows[0].get("actor_player_id") if rows.size() == 1 else null, bound.get(case["next"], {}).get("character_id"))
	_check(assertions, "revision advanced exactly once", records.back().get("after", {}).get("revision") if not records.is_empty() else null, 1)
	if retry:
		_check(assertions, "same actor retry received the committed success", _client_status(clients["actor"], 1), [SUCCESS_STATUS, "ok"])
		_no_op_checks(assertions, records, 2, "other actor after recovery")
		_check(assertions, "other actor client received already-unlocked success", _client_status(clients["occluder"], 0), [SUCCESS_STATUS, ALREADY_UNLOCKED])
	else:
		_check(assertions, "next requester client received the committed success", _client_status(clients["occluder"], 0), [SUCCESS_STATUS, "ok"])
	var total_committed: Variant = _delta(first.get("before", {}).get("canon_writes", {}), (records.back().get("after", {}) if not records.is_empty() else {}).get("canon_writes", {}), "committed")
	var commit: Dictionary = {}
	if total_committed is int:
		commit = {"status": ReportScript.OBSERVED, "outcome": ReportScript.COMMIT_SUCCESS if total_committed > 0 else ReportScript.COMMIT_NOT_ATTEMPTED}
	var journeys: Array = []
	for role: String in ["actor", "occluder"]:
		var entry: Dictionary = bound.get(role, {})
		journeys.append({"journey_id": entry.get("journey_id", ""), "player_guid": entry.get("character_id", ""), "role": role})
	return {
		"experiment_id": 1233,
		"timestamp_ms": timestamp_ms,
		"scenario": {"name": case["id"], "expected_commit": ReportScript.COMMIT_SUCCESS,
			"required_stages": [ReportScript.STAGE_JOURNEY_IDENTITY, ReportScript.STAGE_COMMIT, ReportScript.STAGE_CASE_ASSERTIONS],
			"fault": "TEMP deferred foreign-key violation makes the real COMMIT fail; SqliteStore rolls back" if rollback else "none (validation failure)"},
		"commit": commit,
		"sector": {"sector_id": "starting_town_hub"},
		"journeys": journeys,
		"case_assertions": assertions,
		"observations": {"server": observation, "actor_client": actor, "occluder_client": occluder},
		"runtime_errors": runtime_errors,
	}
