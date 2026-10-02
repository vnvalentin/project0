extends "res://scripts/exp1231_gate_unlock_experiment.gd"
## Experiment #1232 orchestrator (Linux host only): concurrent unlock
## arbitration in both receive orders and post-commit retry / subsequent-actor
## no-op windows, through the real authenticated server path.
##   godot --headless --path . -s scripts/exp1232_gate_ordering_experiment.gd

const CASES_1232: Array[Dictionary] = [
	{"id": "order_a_first", "first": "actor", "second": "occluder"},
	{"id": "order_b_first", "first": "occluder", "second": "actor"},
	{"id": "retry_after_withheld_confirmation"},
]
const SUCCESS_STATUS: String = "accepted"
const ALREADY_UNLOCKED: String = "already_unlocked"


func _experiment_id() -> int:
	return 1232


func _cases() -> Array[Dictionary]:
	return CASES_1232


func _fixture_script() -> String:
	return "scripts/exp1232_gate_fixture.gd"


func _client_script() -> String:
	return "scripts/exp1232_client.gd"


func _await_clients(actor_pid: int, occluder_pid: int) -> void:
	await _wait_for_exit(actor_pid, ACTOR_TIMEOUT_MSEC)
	await _wait_for_exit(occluder_pid, ACTOR_TIMEOUT_MSEC)


func _report_input(case: Dictionary, timestamp_ms: int, observation: Variant, actor: Variant, occluder: Variant, runtime_errors: Array, server_ready: bool) -> Dictionary:
	var obs: Dictionary = observation if observation is Dictionary else {}
	var bound: Dictionary = obs.get("bound", {})
	var records: Array = obs.get("resolutions", [])
	var received: Array = obs.get("received", [])
	var clients: Dictionary = {"actor": actor if actor is Dictionary else {}, "occluder": occluder if occluder is Dictionary else {}}
	var assertions: Array[Dictionary] = []
	_check(assertions, "server became ready", server_ready, true)
	_check(assertions, "actor client entered world", clients["actor"].get("entered"), true)
	_check(assertions, "second actor client entered world", clients["occluder"].get("entered"), true)
	var first_before: Dictionary = records[0].get("before", {}) if not records.is_empty() else {}
	var last_after: Dictionary = records.back().get("after", {}) if not records.is_empty() else {}
	_check(assertions, "Canon store journal_mode is WAL", String(last_after.get("journal_mode", "")).to_lower(), "wal")
	_check(assertions, "no rolled-back Canon write", _delta(first_before.get("canon_writes", {}), last_after.get("canon_writes", {}), "rolled_back"), 0)
	var total_committed: Variant = _delta(first_before.get("canon_writes", {}), last_after.get("canon_writes", {}), "committed")
	_check(assertions, "exactly one committed Canon INSERT in total", total_committed, 1)
	_check(assertions, "revision advanced exactly once", int(last_after.get("revision", -9)) - int(first_before.get("revision", 0)), 1)
	var rows: Array = last_after.get("mutations", [])
	_check(assertions, "exactly one durable unlock_gate row", rows.size(), 1)
	_check(assertions, "every processed request saw the receive order", records.map(func(record: Dictionary) -> int: return int(record.get("receive_seq", -1))), range(1, records.size() + 1))
	var first_role: String = case.get("first", "actor")
	_check(assertions, "committed row actor is the first-received Character", rows[0].get("actor_player_id") if rows.size() == 1 else null, bound.get(first_role, {}).get("character_id"))
	_check(assertions, "first resolution accepted only after COMMIT", _accepted_after_commit(records, 0), true)
	_check(assertions, "first request committed exactly one INSERT", _record_delta(records, 0, "committed"), 1)
	if case["id"] == "retry_after_withheld_confirmation":
		_check(assertions, "server receive order: actor, actor retry, other actor", _roles(received), ["actor", "actor", "occluder"])
		_check(assertions, "original confirmation withheld after COMMIT", records[0].get("confirmation_withheld") if not records.is_empty() else null, true)
		_check(assertions, "actor received no confirmation for the withheld original", _client_resolution(clients["actor"], 0), null)
		_no_op_checks(assertions, records, 1, "committed actor retry")
		_no_op_checks(assertions, records, 2, "other actor subsequent request")
		_check(assertions, "actor client received already-unlocked success for the retry", _client_status(clients["actor"], 1), [SUCCESS_STATUS, ALREADY_UNLOCKED])
		_check(assertions, "other actor client received already-unlocked success", _client_status(clients["occluder"], 0), [SUCCESS_STATUS, ALREADY_UNLOCKED])
	else:
		var second_role: String = case["second"]
		_check(assertions, "server receive order", _roles(received), [first_role, second_role])
		_check(assertions, "both intents pending before either was evaluated", records[0].get("pending_at_processing") if not records.is_empty() else null, 2)
		_check(assertions, "processing order equals receive order", _roles(records), [first_role, second_role])
		_no_op_checks(assertions, records, 1, "second concurrent request")
		_check(assertions, "first client received the committed success", _client_status(clients[first_role], 0), [SUCCESS_STATUS, "ok"])
		_check(assertions, "second client received already-unlocked success", _client_status(clients[second_role], 0), [SUCCESS_STATUS, ALREADY_UNLOCKED])
	var commit: Dictionary = {}
	if total_committed is int:
		commit = {"status": ReportScript.OBSERVED, "outcome": ReportScript.COMMIT_SUCCESS if total_committed > 0 else ReportScript.COMMIT_NOT_ATTEMPTED}
	var journeys: Array = []
	for role: String in ["actor", "occluder"]:
		var entry: Dictionary = bound.get(role, {})
		journeys.append({"journey_id": entry.get("journey_id", ""), "player_guid": entry.get("character_id", ""), "role": role})
	return {
		"experiment_id": 1232,
		"timestamp_ms": timestamp_ms,
		"scenario": {"name": case["id"], "expected_commit": ReportScript.COMMIT_SUCCESS,
			"required_stages": [ReportScript.STAGE_JOURNEY_IDENTITY, ReportScript.STAGE_COMMIT, ReportScript.STAGE_CASE_ASSERTIONS],
			"already_unlocked_expectation": {"status": SUCCESS_STATUS, "reason": ALREADY_UNLOCKED, "canon_insert_update": 0}},
		"commit": commit,
		"sector": {"sector_id": "starting_town_hub"},
		"journeys": journeys,
		"case_assertions": assertions,
		"observations": {"server": observation, "actor_client": actor, "occluder_client": occluder},
		"runtime_errors": runtime_errors,
	}


func _no_op_checks(assertions: Array[Dictionary], records: Array, index: int, label: String) -> void:
	var record: Dictionary = records[index] if records.size() > index else {}
	var resolution: Variant = record.get("resolution")
	_check(assertions, "%s: successful already-unlocked" % label,
		[resolution.get("status"), resolution.get("reason")] if resolution is Dictionary else null, [SUCCESS_STATUS, ALREADY_UNLOCKED])
	_check(assertions, "%s: zero Canon INSERT/UPDATE in the no-op window" % label, _record_delta(records, index, "attempted"), 0)
	_check(assertions, "%s: revision unchanged" % label,
		record.get("after", {}).get("revision") == record.get("before", {}).get("revision") and not record.is_empty(), true)


func _record_delta(records: Array, index: int, window: String) -> Variant:
	if records.size() <= index:
		return null
	return _delta(records[index].get("before", {}).get("canon_writes", {}), records[index].get("after", {}).get("canon_writes", {}), window)


func _accepted_after_commit(records: Array, index: int) -> bool:
	if records.size() <= index or not records[index].get("resolution") is Dictionary:
		return false
	var resolution: Dictionary = records[index]["resolution"]
	return resolution.get("status") == SUCCESS_STATUS and float(resolution.get("applied_revision", -1)) == float(records[index].get("after", {}).get("revision", -2))


func _roles(entries: Array) -> Array:
	return entries.map(func(entry: Dictionary) -> String: return String(entry.get("role", "")))


func _client_resolution(client: Dictionary, index: int) -> Variant:
	var sends: Array = client.get("sends", [])
	return sends[index].get("resolution") if sends.size() > index else "NOT_SENT"


func _client_status(client: Dictionary, index: int) -> Variant:
	var resolution: Variant = _client_resolution(client, index)
	return [resolution.get("status"), resolution.get("reason")] if resolution is Dictionary else null
