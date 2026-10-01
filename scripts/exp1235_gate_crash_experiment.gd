extends "res://scripts/exp1234_gate_return_experiment.gd"
## Experiment #1235 orchestrator (Linux host only): kill the authoritative server
## inside a proven crash window, then recover in a new process on the preserved DBs.
## pre_commit: inside the open unlock transaction (expected rollback, locked gate).
## post_commit: after the real COMMIT, before confirmation (expected unlocked gate).
## An independent read-only sqlite3 reader observes committed rows at the barrier
## and after the kill; the barrier is never inferred from timing.
##   godot --headless --path . -s scripts/exp1235_gate_crash_experiment.gd

const CASES_1235: Array[Dictionary] = [
	{"id": "pre_commit", "expect_unlocked": false},
	{"id": "post_commit", "expect_unlocked": true},
]
const BARRIER_TIMEOUT_MSEC: int = 20000
const KILL_TIMEOUT_MSEC: int = 5000


func _experiment_id() -> int:
	return 1235


func _cases() -> Array[Dictionary]:
	return CASES_1235


func _fixture_script() -> String:
	return "scripts/exp1235_gate_fixture.gd"


func _client_script() -> String:
	return "scripts/exp1235_client.gd"


func _run_case(case: Dictionary, timestamp_ms: int) -> Dictionary:
	var case_id: String = case["id"]
	var case_dir: String = "%s/%s" % [_run_dir, case_id]
	DirAccess.make_dir_recursive_absolute(case_dir)
	var session: Dictionary = GameplayTestSessionScript.begin()
	GameplayTestSessionScript.refresh_identity()
	var occluder_token: String = OS.get_environment(GameplayTestSessionScript.ASSERTION_ENV)
	GameplayTestSessionScript.refresh_identity()
	var actor_token: String = OS.get_environment(GameplayTestSessionScript.ASSERTION_ENV)
	var canon_db: String = "exp1235_canon_%s_%d_%d.db" % [case_id, OS.get_process_id(), Time.get_ticks_usec()]
	var canon_path: String = ProjectSettings.globalize_path("user://%s" % canon_db)
	var obs1: String = "%s/server1-observation.json" % case_dir
	var obs2: String = "%s/server2-observation.json" % case_dir
	var barrier_file: String = "%s/barrier.json" % case_dir
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
		"EXP1235_BARRIER_FILE": barrier_file,
	})
	var lifecycle: Dictionary = {}
	var server1: int = _spawn(_fixture_script(), "%s/server1.log" % case_dir, {"EXP1235_ARM": "1"})
	lifecycle["server1_ready"] = await _wait_for_log("%s/server1.log" % case_dir, "Server listening on", server1, SERVER_READY_TIMEOUT_MSEC)
	if lifecycle["server1_ready"]:
		await _run_phase("establish", case_dir, obs1, actor_token, occluder_token)
		lifecycle["barrier_reached"] = await _wait_for_file(barrier_file, BARRIER_TIMEOUT_MSEC)
		lifecycle["barrier"] = _read_json(barrier_file)
		lifecycle["server1_running_at_barrier"] = OS.is_process_running(server1)
		lifecycle["observer_at_barrier"] = _observe_committed(canon_path)
		lifecycle["kill_result"] = OS.kill(server1) if lifecycle["server1_running_at_barrier"] else -1
		await _wait_for_exit(server1, KILL_TIMEOUT_MSEC)
		lifecycle["server1_terminated"] = not OS.is_process_running(server1)
		lifecycle["observer_after_kill"] = _observe_committed(canon_path)
		lifecycle["canon_db_preserved"] = FileAccess.file_exists(canon_path)
		var server2: int = _spawn(_fixture_script(), "%s/server2.log" % case_dir, {"EXP1231_OBSERVATION": obs2, "EXP1235_ARM": "0"})
		lifecycle["server2_ready"] = await _wait_for_log("%s/server2.log" % case_dir, "Server listening on", server2, SERVER_READY_TIMEOUT_MSEC)
		lifecycle["distinct_server_pids"] = server1 != server2
		if lifecycle["server2_ready"]:
			await _run_phase("return", case_dir, obs2, actor_token, occluder_token)
		lifecycle["observer_after_recovery"] = _observe_committed(canon_path)
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
	var report: Dictionary = ReportScript.build(_report_1235(case, timestamp_ms, _read_json(obs1), _read_json(obs2), results, lifecycle, runtime_errors))
	var written: Dictionary = ReportScript.write(report, case_dir)
	if written["outcome"] != ReportScript.WRITE_OK:
		_harness_errors.append("%s report write: %s" % [case_id, written["outcome"]])
	for suffix: String in ["", "-wal", "-shm", "-journal"]:
		if FileAccess.file_exists(canon_path + suffix) and DirAccess.remove_absolute(canon_path + suffix) != OK:
			_harness_errors.append("%s: failed to remove %s" % [case_id, canon_path + suffix])
	_restore_environment(saved)
	if not GameplayTestSessionScript.restore(session):
		_harness_errors.append("%s: failed to remove accounts database" % case_id)
	return {"id": case_id, "passed": report["passed"], "outcome": report["outcome"],
		"first_failing_stage": report["first_failing_stage"], "report": written.get("path"),
		"failed_assertions": (report["case_assertions"] if report["case_assertions"] is Array else []).filter(
			func(assertion: Dictionary) -> bool: return not assertion["passed"])}


func _wait_for_file(path: String, timeout_msec: int) -> bool:
	var deadline: int = Time.get_ticks_msec() + timeout_msec
	while Time.get_ticks_msec() < deadline:
		if FileAccess.file_exists(path):
			return true
		await process_frame
	return false


## Independent observer: a separate sqlite3 process opens the Canon DB read-only
## and reports only committed state.
func _observe_committed(db_path: String) -> Variant:
	var script: String = "import json,sqlite3,sys\nc=sqlite3.connect('file:'+sys.argv[1]+'?mode=ro',uri=True)\nr=c.execute(\"SELECT COUNT(*),COALESCE(MAX(applied_revision),0),GROUP_CONCAT(mutation_kind) FROM canon_mutations WHERE sector_id='starting_town_hub'\").fetchone()\nprint(json.dumps({'rows':r[0],'revision':r[1],'kinds':r[2],'journal_mode':c.execute('PRAGMA journal_mode').fetchone()[0]}))"
	var output: Array = []
	var code: int = OS.execute("python3", ["-c", script, db_path], output, true)
	var parsed: Variant = JSON.parse_string(String(output[0]).strip_edges()) if code == 0 and not output.is_empty() else null
	return parsed if parsed is Dictionary else {"error": String(output[0]) if not output.is_empty() else "no output", "exit_code": code}


func _report_1235(case: Dictionary, timestamp_ms: int, server1: Variant, server2: Variant, results: Dictionary, lifecycle: Dictionary, runtime_errors: Array) -> Dictionary:
	var unlocked: bool = case["expect_unlocked"]
	var first: Dictionary = server1 if server1 is Dictionary else {}
	var returned: Dictionary = server2 if server2 is Dictionary else {}
	var assertions: Array[Dictionary] = []
	_check(assertions, "first server ready", lifecycle.get("server1_ready"), true)
	_check(assertions, "barrier reached in the declared window", (lifecycle.get("barrier") if lifecycle.get("barrier") is Dictionary else {}).get("window"), case["id"])
	_check(assertions, "server blocked at the barrier when observed", lifecycle.get("server1_running_at_barrier"), true)
	if not unlocked:
		_check(assertions, "trigger barrier armed inside the transaction", first.get("fault", {}).get("function_registered") == true and first.get("fault", {}).get("trigger") == true, true)
		_check(assertions, "barrier fired after the real unlock INSERT", String(first.get("barrier", {}).get("detail", {}).get("event_id", "")).is_empty(), false)
	var expected_rows: int = 1 if unlocked else 0
	_check(assertions, "independent observer at barrier: committed unlock rows", (lifecycle.get("observer_at_barrier") if lifecycle.get("observer_at_barrier") is Dictionary else {}).get("rows"), expected_rows)
	_check(assertions, "server process killed (SIGKILL) and gone", [lifecycle.get("kill_result"), lifecycle.get("server1_terminated")], [OK, true])
	_check(assertions, "barrier never released without the kill", first.get("barrier", {}).get("released_without_kill"), null)
	_check(assertions, "independent observer after kill: committed unlock rows", (lifecycle.get("observer_after_kill") if lifecycle.get("observer_after_kill") is Dictionary else {}).get("rows"), expected_rows)
	_check(assertions, "Canon database preserved", lifecycle.get("canon_db_preserved"), true)
	_check(assertions, "actor never received a confirmation from the killed process", _resolution_pair((results.get("actor_establish") if results.get("actor_establish") is Dictionary else {}).get("sends", []), 0), null)
	_check(assertions, "new server process became ready", lifecycle.get("server2_ready"), true)
	_check(assertions, "recovery ran in a new process (different pid and boot id)",
		not returned.is_empty() and first.get("boot", {}).get("pid") != returned.get("boot", {}).get("pid") and first.get("boot", {}).get("boot_id") != returned.get("boot", {}).get("boot_id"), true)
	_check(assertions, "new process restored both journeys from the database", returned.get("boot", {}).get("restored_journeys", 0) >= 2, true)
	_check(assertions, "new process boot performed zero Canon INSERT/UPDATE",
		_delta({"attempted": {"canon_sectors": 0, "canon_mutations": 0}}, returned.get("boot", {}).get("after_start", {}).get("canon_writes", {}), "attempted"), 0)
	_check(assertions, "recovered committed state (independent observer)", [(lifecycle.get("observer_after_recovery") if lifecycle.get("observer_after_recovery") is Dictionary else {}).get("rows"),
		(lifecycle.get("observer_after_recovery") if lifecycle.get("observer_after_recovery") is Dictionary else {}).get("revision")], [expected_rows, expected_rows])
	for key: String in ["actor_establish", "occluder_establish", "actor_return", "occluder_return"]:
		var result: Dictionary = results.get(key) if results.get(key) is Dictionary else {}
		_check(assertions, "%s client entered and finished" % key, [result.get("entered"), result.get("failure")], [true, null])
	var reloads: Array = returned.get("reload_events", [])
	var reclaims: Dictionary = {}
	for evidence: Dictionary in returned.get("journey_evidence", []):
		if evidence.get("kind") == "reclaim":
			reclaims[String(evidence.get("character_id"))] = evidence
	var entries: Dictionary = {}
	for evidence: Dictionary in first.get("journey_evidence", []):
		if evidence.get("kind") == "entry":
			entries[String(evidence.get("character_id"))] = String(evidence.get("journey_id"))
	var journeys: Array = []
	for role: String in ["actor", "occluder"]:
		var cid: String = OS.get_environment("EXP1231_ACTOR_CID") if role == "actor" else OS.get_environment("EXP1231_OCCLUDER_CID")
		var reclaim: Dictionary = reclaims.get(cid, {})
		var own: Array = reloads.filter(func(event: Dictionary) -> bool: return String(event.get("character_id")) == cid)
		_check(assertions, "%s returned through journey reclaim with the same journey id" % role, [reclaim.get("journey_id"), reclaim.is_empty()], [entries.get(cid), false])
		journeys.append({"journey_id": String(reclaim.get("journey_id", "")), "player_guid": cid, "role": role,
			"generation_count": _window(reclaim, own[0] if own.size() == 1 else {}, "generation_count"),
			"canon_write_count": _window(reclaim, own[0] if own.size() == 1 else {}, "canon_writes"),
			"reload_events": own.map(func(event: Dictionary) -> Dictionary: return {"event_type": event.get("event_type"),
				"journey_id": event.get("journey_id"), "sector_id": event.get("sector_id"), "spatial_guid": event.get("spatial_guid")})})
	var window_start: Dictionary = {}
	for evidence: Dictionary in returned.get("journey_evidence", []):
		if evidence.get("kind") == "reclaim":
			window_start = evidence
			break
	var window_end: Dictionary = reloads.back() if not reloads.is_empty() else {}
	var expected: Dictionary = first.get("expected_snapshot", {}) if first.get("expected_snapshot") is Dictionary else {}
	var actual: Dictionary = window_end.get("snapshot", {}) if window_end.get("snapshot") is Dictionary else {}
	var gate_expected: Dictionary = {}
	var gate_actual: Dictionary = {}
	for guid: String in expected.get("entities", {}):
		if expected["entities"][guid].get("structure_id") == "gate_01":
			gate_expected = expected["entities"][guid]
			gate_actual = actual.get("entities", {}).get(guid, {})
	_check(assertions, "declared expected checkpoint (unlocked=%s, closed)" % unlocked, [gate_expected.get("unlocked"), gate_expected.get("collider_blocked_cells")], [unlocked, GATE_CELLS])
	_check(assertions, "recovered gate matches the declared scenario (unlocked=%s, closed)" % unlocked, [gate_actual.get("unlocked"), gate_actual.get("collider_blocked_cells")], [unlocked, GATE_CELLS])
	for event: Dictionary in reloads:
		_check(assertions, "reload snapshot for %s matches the declared checkpoint exactly" % String(event.get("character_id")),
			not expected.is_empty() and JSON.stringify(event.get("snapshot"), "", true) == JSON.stringify(expected, "", true), true)
	var actor_return: Dictionary = results.get("actor_return") if results.get("actor_return") is Dictionary else {}
	var probe_min: Variant = actor_return.get("closed_gate_probe", {}).get("min_z") if actor_return.get("closed_gate_probe") is Dictionary else null
	_check(assertions, "recovered gate blocks movement before any opening", probe_min is float and probe_min > -4.6 and probe_min < -3.6, true)
	if unlocked:
		var occluder_return: Dictionary = results.get("occluder_return") if results.get("occluder_return") is Dictionary else {}
		_check(assertions, "actor opened the recovered unlocked gate", _resolution_pair(actor_return.get("sends", []), 0), ["accepted", "opened"])
		_check(assertions, "second player found it already open", _resolution_pair(occluder_return.get("sends", []), 0), ["accepted", "already_open"])
		for pair: Array in [["actor", actor_return], ["occluder", occluder_return]]:
			var traverse: Variant = (pair[1] as Dictionary).get("traverse", {}).get("min_z") if (pair[1] as Dictionary).get("traverse") is Dictionary else null
			_check(assertions, "%s walked through the opened gate" % pair[0], traverse is float and traverse <= -6.5, true)
	else:
		_check(assertions, "recovered locked gate refuses opening", _resolution_pair(actor_return.get("sends", []), 0), ["rejected", "gate_locked"])
	var final_after: Dictionary = returned.get("resolutions", []).back().get("after", {}) if not returned.get("resolutions", []).is_empty() else {}
	_check(assertions, "durable state at the end (rows, revision)", [(final_after.get("mutations", []) as Array).size(), final_after.get("revision")], [expected_rows, float(expected_rows)])
	var observed_commit: Variant = (lifecycle.get("observer_after_recovery") if lifecycle.get("observer_after_recovery") is Dictionary else {}).get("rows")
	return {
		"experiment_id": 1235,
		"timestamp_ms": timestamp_ms,
		"scenario": {"name": case["id"], "expected_commit": ReportScript.COMMIT_SUCCESS if unlocked else ReportScript.COMMIT_ROLLED_BACK,
			"required_stages": ReportScript.DEFAULT_REQUIRED_STAGES + PackedStringArray([ReportScript.STAGE_CASE_ASSERTIONS]),
			"crash_window": "inside the open unlock transaction (after INSERT, before COMMIT)" if not unlocked else "after COMMIT, before client confirmation",
			"termination": "SIGKILL of the owned server process after independent observation at a published barrier"},
		"commit": {"status": ReportScript.OBSERVED, "outcome": (ReportScript.COMMIT_SUCCESS if observed_commit == 1.0 else ReportScript.COMMIT_ROLLED_BACK)}
			if (observed_commit is float or observed_commit is int) and lifecycle.get("barrier_reached") == true else {},
		"sector": {"sector_id": "starting_town_hub", "generation_count": _window(window_start, window_end, "generation_count"),
			"canon_write_count": _window(window_start, window_end, "canon_writes")},
		"journeys": journeys,
		"snapshot": {"expected": expected, "actual": actual,
			"evidence": {"base_blueprint_parity": "server1 declared checkpoint vs server2 last reload snapshot", "mutation_records_parity": "same", "reconstructed_entity_state_parity": "same"}},
		"case_assertions": assertions,
		"observations": {"server1": server1, "server2": server2, "clients": results, "lifecycle": lifecycle},
		"runtime_errors": runtime_errors,
	}
