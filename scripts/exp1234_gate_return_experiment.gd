extends "res://scripts/exp1232_gate_ordering_experiment.gd"
## Experiment #1234 orchestrator (Linux host only): committed unlocked-but-closed
## gate, both players leave, then return (a) to the same server process and
## (b) to a new server process after an orderly shutdown on the preserved DBs.
##   godot --headless --path . -s scripts/exp1234_gate_return_experiment.gd

const CASES_1234: Array[Dictionary] = [
	{"id": "reconnect_without_restart", "restart": false},
	{"id": "orderly_restart", "restart": true},
]
const SHUTDOWN_TIMEOUT_MSEC: int = 10000
const GATE_CELLS: int = 3


func _experiment_id() -> int:
	return 1234


func _cases() -> Array[Dictionary]:
	return CASES_1234


func _fixture_script() -> String:
	return "scripts/exp1234_gate_fixture.gd"


func _client_script() -> String:
	return "scripts/exp1234_client.gd"


func _run_case(case: Dictionary, timestamp_ms: int) -> Dictionary:
	var case_id: String = case["id"]
	var case_dir: String = "%s/%s" % [_run_dir, case_id]
	DirAccess.make_dir_recursive_absolute(case_dir)
	var session: Dictionary = GameplayTestSessionScript.begin()
	GameplayTestSessionScript.refresh_identity()
	var occluder_token: String = OS.get_environment(GameplayTestSessionScript.ASSERTION_ENV)
	GameplayTestSessionScript.refresh_identity()
	var actor_token: String = OS.get_environment(GameplayTestSessionScript.ASSERTION_ENV)
	var canon_db: String = "exp1234_canon_%s_%d_%d.db" % [case_id, OS.get_process_id(), Time.get_ticks_usec()]
	var obs1: String = "%s/server1-observation.json" % case_dir
	var obs2: String = "%s/server2-observation.json" % case_dir
	var saved: Dictionary = _apply_environment({
		"PROJECT0_SERVER_PORT": str(_free_port()),
		"PROJECT0_SERVER_BIND_ADDRESS": "127.0.0.1",
		"PROJECT0_OPERATOR_CONTROL_PORT": "0",
		"PROJECT0_CANON_DB_PATH": canon_db,
		"EXP1231_CASE": case_id,
		"EXP1231_ACTOR_CID": _cid(actor_token),
		"EXP1231_OCCLUDER_CID": _cid(occluder_token),
		"EXP1231_OBSERVATION": obs1,
		"EXP1231_STOP": "%s/stop" % case_dir,
		"EXP1234_SHUTDOWN": "%s/shutdown" % case_dir,
	})
	var lifecycle: Dictionary = {"restart": case["restart"]}
	var server1: int = _spawn(_fixture_script(), "%s/server1.log" % case_dir, {})
	lifecycle["server1_ready"] = await _wait_for_log("%s/server1.log" % case_dir, "Server listening on", server1, SERVER_READY_TIMEOUT_MSEC)
	var return_observation: String = obs1
	if lifecycle["server1_ready"]:
		await _run_phase("establish", case_dir, obs1, actor_token, occluder_token)
		if case["restart"]:
			FileAccess.open("%s/shutdown" % case_dir, FileAccess.WRITE).close()
			await _wait_for_exit(server1, SHUTDOWN_TIMEOUT_MSEC)
			lifecycle["server1_exited_on_request"] = not OS.is_process_running(server1)
			lifecycle["canon_db_preserved"] = FileAccess.file_exists(ProjectSettings.globalize_path("user://%s" % canon_db))
			var server2: int = _spawn(_fixture_script(), "%s/server2.log" % case_dir, {"EXP1231_OBSERVATION": obs2, "EXP1234_SHUTDOWN": ""})
			lifecycle["server2_ready"] = await _wait_for_log("%s/server2.log" % case_dir, "Server listening on", server2, SERVER_READY_TIMEOUT_MSEC)
			lifecycle["distinct_server_pids"] = server1 != server2
			return_observation = obs2
		if not case["restart"] or lifecycle.get("server2_ready", false):
			await _run_phase("return", case_dir, return_observation, actor_token, occluder_token)
	FileAccess.open("%s/stop" % case_dir, FileAccess.WRITE).close()
	await _stop_owned_processes()
	var results: Dictionary = {}
	for phase: String in ["establish", "return"]:
		for role: String in ["actor", "occluder"]:
			results["%s_%s" % [role, phase]] = _read_json("%s/%s-%s.json" % [case_dir, role, phase])
	var runtime_errors: Array = []
	for log_path: String in DirAccess.get_files_at(case_dir):
		if log_path.ends_with(".log"):
			for line: String in FileAccess.get_file_as_string("%s/%s" % [case_dir, log_path]).split("\n"):
				if line.contains("SCRIPT ERROR"):
					runtime_errors.append("%s: %s" % [log_path, line.strip_edges()])
	var report: Dictionary = ReportScript.build(_report_1234(case, timestamp_ms, _read_json(obs1), _read_json(obs2) if case["restart"] else null,
		results, lifecycle, runtime_errors))
	var written: Dictionary = ReportScript.write(report, case_dir)
	if written["outcome"] != ReportScript.WRITE_OK:
		_harness_errors.append("%s report write: %s" % [case_id, written["outcome"]])
	for suffix: String in ["", "-wal", "-shm", "-journal"]:
		var db_path: String = ProjectSettings.globalize_path("user://%s%s" % [canon_db, suffix])
		if FileAccess.file_exists(db_path) and DirAccess.remove_absolute(db_path) != OK:
			_harness_errors.append("%s: failed to remove %s" % [case_id, db_path])
	_restore_environment(saved)
	if not GameplayTestSessionScript.restore(session):
		_harness_errors.append("%s: failed to remove accounts database" % case_id)
	return {"id": case_id, "passed": report["passed"], "outcome": report["outcome"],
		"first_failing_stage": report["first_failing_stage"], "report": written.get("path"),
		"failed_assertions": (report["case_assertions"] if report["case_assertions"] is Array else []).filter(
			func(assertion: Dictionary) -> bool: return not assertion["passed"])}


func _run_phase(phase: String, case_dir: String, observation: String, actor_token: String, occluder_token: String) -> void:
	var pids: Array[int] = []
	for role: String in ["occluder", "actor"]:
		pids.append(_spawn(_client_script(), "%s/%s-%s.log" % [case_dir, role, phase], {"EXP1231_ROLE": role, "EXP1234_PHASE": phase,
			"EXP1231_OBSERVATION": observation, "EXP1231_RESULT": "%s/%s-%s.json" % [case_dir, role, phase],
			GameplayTestSessionScript.ASSERTION_ENV: actor_token if role == "actor" else occluder_token}))
	for pid: int in pids:
		await _wait_for_exit(pid, ACTOR_TIMEOUT_MSEC)


func _report_1234(case: Dictionary, timestamp_ms: int, server1: Variant, server2: Variant, results: Dictionary, lifecycle: Dictionary, runtime_errors: Array) -> Dictionary:
	var first: Dictionary = server1 if server1 is Dictionary else {}
	var returned: Dictionary = (server2 if server2 is Dictionary else {}) if case["restart"] else first
	var assertions: Array[Dictionary] = []
	_check(assertions, "server process ready", lifecycle.get("server1_ready"), true)
	for key: String in ["actor_establish", "occluder_establish", "actor_return", "occluder_return"]:
		var result: Dictionary = results.get(key) if results.get(key) is Dictionary else {}
		_check(assertions, "%s client entered and finished" % key, [result.get("entered"), result.get("failure")], [true, null])
	var unlock: Variant = ((results.get("actor_establish") if results.get("actor_establish") is Dictionary else {}).get("sends", [{}]) as Array)
	_check(assertions, "unlock committed before the players left", _resolution_pair(unlock, 0), ["accepted", "ok"])
	if case["restart"]:
		_check(assertions, "orderly shutdown requested and the first process exited on its own", lifecycle.get("server1_exited_on_request"), true)
		_check(assertions, "Canon database preserved across restart", lifecycle.get("canon_db_preserved"), true)
		_check(assertions, "new server process became ready", lifecycle.get("server2_ready"), true)
		_check(assertions, "recovery ran in a new process (different pid and boot id)",
			first.get("boot", {}).get("boot_id") != returned.get("boot", {}).get("boot_id") and first.get("boot", {}).get("pid") != returned.get("boot", {}).get("pid") and not returned.is_empty(), true)
		_check(assertions, "new process restored both journeys from the database", returned.get("boot", {}).get("restored_journeys", 0) >= 2, true)
		_check(assertions, "new process boot performed zero Canon INSERT/UPDATE",
			_delta({"attempted": {"canon_sectors": 0, "canon_mutations": 0}}, returned.get("boot", {}).get("after_start", {}).get("canon_writes", {}), "attempted"), 0)
	var entries: Dictionary = {}
	for evidence: Dictionary in first.get("journey_evidence", []):
		if evidence.get("kind") == "entry":
			entries[String(evidence.get("character_id"))] = String(evidence.get("journey_id"))
	var reclaims: Dictionary = {}
	for evidence: Dictionary in returned.get("journey_evidence", []):
		if evidence.get("kind") == "reclaim":
			reclaims[String(evidence.get("character_id"))] = evidence
	var reloads: Array = returned.get("reload_events", [])
	var cids: Dictionary = {"actor": OS.get_environment("EXP1231_ACTOR_CID"), "occluder": OS.get_environment("EXP1231_OCCLUDER_CID")}
	var journeys: Array = []
	for role: String in ["actor", "occluder"]:
		var cid: String = cids[role]
		var reclaim: Dictionary = reclaims.get(cid, {})
		var own: Array = reloads.filter(func(event: Dictionary) -> bool: return String(event.get("character_id")) == cid)
		var reload: Dictionary = own[0] if own.size() == 1 else {}
		_check(assertions, "%s returned through journey reclaim with the same journey id" % role, [reclaim.get("journey_id"), reclaim.is_empty()], [entries.get(cid), false])
		journeys.append({
			"journey_id": String(reclaim.get("journey_id", "")), "player_guid": cid, "role": role,
			"generation_count": _window(reclaim, reload, "generation_count"),
			"canon_write_count": _window(reclaim, reload, "canon_writes"),
			"reload_events": own.map(func(event: Dictionary) -> Dictionary: return {"event_type": event.get("event_type"),
				"journey_id": event.get("journey_id"), "sector_id": event.get("sector_id"), "spatial_guid": event.get("spatial_guid")}),
		})
	var window_start: Dictionary = {}
	for evidence: Dictionary in returned.get("journey_evidence", []):
		if evidence.get("kind") == "reclaim":
			window_start = evidence
			break
	var window_end: Dictionary = reloads.back() if not reloads.is_empty() else {}
	var expected: Dictionary = first.get("expected_snapshot", {}) if first.get("expected_snapshot") is Dictionary else {}
	var actual: Dictionary = window_end.get("snapshot", {}) if window_end.get("snapshot") is Dictionary else {}
	var gate_guid: String = ""
	for guid: String in expected.get("entities", {}):
		if expected["entities"][guid].get("structure_id") == "gate_01":
			gate_guid = guid
	var gate_expected: Dictionary = expected.get("entities", {}).get(gate_guid, {})
	var gate_actual: Dictionary = actual.get("entities", {}).get(gate_guid, {})
	_check(assertions, "checkpoint is unlocked-but-closed (unlocked, all gate cells solid)", [gate_expected.get("unlocked"), gate_expected.get("collider_blocked_cells")], [true, GATE_CELLS])
	_check(assertions, "returned gate is unlocked-but-closed before opening", [gate_actual.get("unlocked"), gate_actual.get("collider_blocked_cells")], [true, GATE_CELLS])
	for event: Dictionary in reloads:
		_check(assertions, "reload snapshot for %s matches the checkpoint exactly" % String(event.get("character_id")),
			JSON.stringify(event.get("snapshot"), "", true) == JSON.stringify(expected, "", true) and not expected.is_empty(), true)
	var actor_return: Dictionary = results.get("actor_return") if results.get("actor_return") is Dictionary else {}
	var occluder_return: Dictionary = results.get("occluder_return") if results.get("occluder_return") is Dictionary else {}
	var probe_min: Variant = actor_return.get("closed_gate_probe", {}).get("min_z") if actor_return.get("closed_gate_probe") is Dictionary else null
	_check(assertions, "closed gate still blocks: movement stops at the gate face",
		probe_min is float and probe_min > -4.6 and probe_min < -3.6, true)
	_check(assertions, "actor opened the gate with the separate interaction", _resolution_pair(actor_return.get("sends", []), 0), ["accepted", "opened"])
	_check(assertions, "second player found it already open", _resolution_pair(occluder_return.get("sends", []), 0), ["accepted", "already_open"])
	for pair: Array in [["actor", actor_return], ["occluder", occluder_return]]:
		var traverse: Variant = (pair[1] as Dictionary).get("traverse", {}).get("min_z") if (pair[1] as Dictionary).get("traverse") is Dictionary else null
		_check(assertions, "%s walked through the opened gate" % pair[0], traverse is float and traverse <= -6.5, true)
	var open_records: Array = returned.get("resolutions", []).filter(func(record: Dictionary) -> bool: return String((record.get("resolution") if record.get("resolution") is Dictionary else {}).get("reason", "")) in ["opened", "already_open"])
	_check(assertions, "two opening interactions observed by the server", open_records.size(), 2)
	for index: int in range(open_records.size()):
		_check(assertions, "opening interaction %d made zero Canon INSERT/UPDATE" % (index + 1), _record_delta(open_records, index, "attempted"), 0)
	var final_after: Dictionary = (returned.get("resolutions", []).back().get("after", {})) if not returned.get("resolutions", []).is_empty() else {}
	_check(assertions, "no second unlock: one durable row and revision 1 at the end", [(final_after.get("mutations", []) as Array).size(), final_after.get("revision")], [1, 1.0])
	var unlock_record: Dictionary = first.get("resolutions", [{}])[0] if not first.get("resolutions", []).is_empty() else {}
	var committed: Variant = _delta(unlock_record.get("before", {}).get("canon_writes", {}), unlock_record.get("after", {}).get("canon_writes", {}), "committed")
	return {
		"experiment_id": 1234,
		"timestamp_ms": timestamp_ms,
		"scenario": {"name": case["id"], "expected_commit": ReportScript.COMMIT_SUCCESS,
			"required_stages": ReportScript.DEFAULT_REQUIRED_STAGES + PackedStringArray([ReportScript.STAGE_CASE_ASSERTIONS]),
			"replay_window": "first returning reclaim -> last CANON_SECTOR_RELOADED; per player: own reclaim -> own reload",
			"session_writes": "journey/session rows live in the accounts DB and are not Canon writes"},
		"commit": {"status": ReportScript.OBSERVED, "outcome": ReportScript.COMMIT_SUCCESS if committed is int and committed > 0 else ReportScript.COMMIT_NOT_ATTEMPTED} if committed is int else {},
		"sector": {"sector_id": "starting_town_hub", "generation_count": _window(window_start, window_end, "generation_count"),
			"canon_write_count": _window(window_start, window_end, "canon_writes")},
		"journeys": journeys,
		"snapshot": {"expected": expected, "actual": actual,
			"evidence": {"base_blueprint_parity": "server1 expected_snapshot vs last reload snapshot", "mutation_records_parity": "same", "reconstructed_entity_state_parity": "same"}},
		"case_assertions": assertions,
		"observations": {"server1": server1, "server2": server2, "clients": results, "lifecycle": lifecycle},
		"runtime_errors": runtime_errors,
	}


## Delta between two stamped observations: Canon INSERT/UPDATE attempts or generation count.
func _window(start: Dictionary, end: Dictionary, field: String) -> Variant:
	if not start.get("counters") is Dictionary or not end.get("counters") is Dictionary:
		return null
	if field == "generation_count":
		var from: Variant = start["counters"].get("generation_count")
		var to: Variant = end["counters"].get("generation_count")
		return int(to) - int(from) if (from is int or from is float) and (to is int or to is float) else null
	return _delta(start["counters"].get("canon_writes", {}), end["counters"].get("canon_writes", {}), "attempted")


func _resolution_pair(sends: Variant, index: int) -> Variant:
	if not sends is Array or (sends as Array).size() <= index or not sends[index].get("resolution") is Dictionary:
		return null
	return [sends[index]["resolution"].get("status"), sends[index]["resolution"].get("reason")]
