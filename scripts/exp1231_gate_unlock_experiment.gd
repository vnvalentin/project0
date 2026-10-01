extends SceneTree
## Experiment #1231 orchestrator (Linux host only): one fresh authoritative
## server, isolated WAL Canon DB, actor client and occluder client per case.
## Writes one exp_1137 report per case plus a run summary, then removes all
## owned processes and databases. Exit 0 = every case passed, 1 = a case
## failed, 2 = harness/evidence failure.
##   godot --headless --path . -s scripts/exp1231_gate_unlock_experiment.gd

const GameplayTestSessionScript: Script = preload("res://scripts/gameplay_test_session.gd")
const ReportScript: Script = preload("res://server/experiment_journey_report.gd")
const CASES: Array[Dictionary] = [
	{"id": "valid_in_range", "expect": "accepted"},
	{"id": "exactly_two_yards", "expect": "accepted"},
	{"id": "over_range", "expect": "out_of_reach"},
	{"id": "static_obstacle", "expect": "no_line_of_sight"},
	{"id": "dynamic_occluders", "expect": "accepted"},
	{"id": "target_gate_side_hit", "expect": "accepted"},
	{"id": "malformed_intent", "expect": "invalid_intent"},
	{"id": "wrong_owner", "expect": "invalid_intent"},
	{"id": "unbound_actor", "expect": "not_accepted"},
	{"id": "nonexistent_target", "expect": "target_not_found"},
	{"id": "not_lockable_target", "expect": "target_not_locked_gate"},
]
const SERVER_READY_TIMEOUT_MSEC: int = 20000
const ACTOR_TIMEOUT_MSEC: int = 45000
const STOP_TIMEOUT_MSEC: int = 5000
const ON_SEGMENT_TOLERANCE: float = 0.5

var _run_dir: String = ""
var _processes: Array[int] = []
var _harness_errors: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if OS.get_name() != "Linux":
		push_error("EXP%d runs only on the Linux validation host." % _experiment_id())
		quit(2)
		return
	var stamp: int = int(Time.get_unix_time_from_system() * 1000.0)
	_run_dir = ProjectSettings.globalize_path("res://logs/experiments/exp%d-%d" % [_experiment_id(), stamp])
	DirAccess.make_dir_recursive_absolute(_run_dir)
	var summary: Dictionary = {"experiment_id": _experiment_id(), "run_dir": _run_dir, "godot": Engine.get_version_info()["string"],
		"source_commit": _git_head(), "cases": [], "timeouts_msec": {"server_ready": SERVER_READY_TIMEOUT_MSEC,
		"actor": ACTOR_TIMEOUT_MSEC, "stop": STOP_TIMEOUT_MSEC}}
	var cases: Array[Dictionary] = _cases()
	for index: int in range(cases.size()):
		var outcome: Dictionary = await _run_case(cases[index], stamp + index)
		summary["cases"].append(outcome)
	summary["harness_errors"] = _harness_errors
	var all_passed: bool = summary["cases"].all(func(case: Dictionary) -> bool: return case.get("passed", false))
	summary["status"] = "PASSED" if all_passed and _harness_errors.is_empty() else "FAILED"
	_write_json("%s/summary.json" % _run_dir, summary)
	print("EXP%d summary: %s (%s)" % [_experiment_id(), summary["status"], _run_dir])
	for case: Dictionary in summary["cases"]:
		print("EXP%d case %s: %s first_failing_stage=%s" % [_experiment_id(), case["id"], case["outcome"], case.get("first_failing_stage")])
	quit(0 if summary["status"] == "PASSED" else (2 if not _harness_errors.is_empty() else 1))


func _experiment_id() -> int:
	return 1231


func _cases() -> Array[Dictionary]:
	return CASES


func _fixture_script() -> String:
	return "scripts/exp1231_gate_fixture.gd"


func _client_script() -> String:
	return "scripts/exp1231_client.gd"


## The #1231 occluder idles until the stop file, so only the actor is awaited.
func _await_clients(actor_pid: int, _occluder_pid: int) -> void:
	await _wait_for_exit(actor_pid, ACTOR_TIMEOUT_MSEC)


func _run_case(case: Dictionary, timestamp_ms: int) -> Dictionary:
	var case_id: String = case["id"]
	var case_dir: String = "%s/%s" % [_run_dir, case_id]
	DirAccess.make_dir_recursive_absolute(case_dir)
	var session: Dictionary = GameplayTestSessionScript.begin()
	GameplayTestSessionScript.refresh_identity()
	var occluder_token: String = OS.get_environment(GameplayTestSessionScript.ASSERTION_ENV)
	GameplayTestSessionScript.refresh_identity()
	var actor_token: String = OS.get_environment(GameplayTestSessionScript.ASSERTION_ENV)
	var canon_db: String = "exp%d_canon_%s_%d_%d.db" % [_experiment_id(), case_id, OS.get_process_id(), Time.get_ticks_usec()]
	var paths: Dictionary = {
		"observation": "%s/server-observation.json" % case_dir,
		"actor": "%s/actor-result.json" % case_dir,
		"occluder": "%s/occluder-result.json" % case_dir,
		"stop": "%s/stop" % case_dir,
	}
	var environment: Dictionary = {
		"PROJECT0_SERVER_PORT": str(_free_port()),
		"PROJECT0_SERVER_BIND_ADDRESS": "127.0.0.1",
		"PROJECT0_OPERATOR_CONTROL_PORT": "0",
		"PROJECT0_CANON_DB_PATH": canon_db,
		"EXP1231_CASE": case_id,
		"EXP1231_ACTOR_CID": _cid(actor_token),
		"EXP1231_OCCLUDER_CID": _cid(occluder_token),
		"EXP1231_OBSERVATION": paths["observation"],
		"EXP1231_STOP": paths["stop"],
	}
	var saved: Dictionary = _apply_environment(environment)
	var server_pid: int = _spawn(_fixture_script(), "%s/server.log" % case_dir, {})
	var ready: bool = await _wait_for_log("%s/server.log" % case_dir, "Server listening on", server_pid, SERVER_READY_TIMEOUT_MSEC)
	if ready:
		var occluder_pid: int = _spawn(_client_script(), "%s/occluder.log" % case_dir, {"EXP1231_ROLE": "occluder",
			"EXP1231_RESULT": paths["occluder"], GameplayTestSessionScript.ASSERTION_ENV: occluder_token})
		var actor_pid: int = _spawn(_client_script(), "%s/actor.log" % case_dir, {"EXP1231_ROLE": "actor",
			"EXP1231_RESULT": paths["actor"], GameplayTestSessionScript.ASSERTION_ENV: actor_token})
		await _await_clients(actor_pid, occluder_pid)
	FileAccess.open(paths["stop"], FileAccess.WRITE).close()
	await _stop_owned_processes()
	var observation: Variant = _read_json(paths["observation"])
	var actor: Variant = _read_json(paths["actor"])
	var occluder: Variant = _read_json(paths["occluder"])
	var runtime_errors: Array = []
	for log_name: String in ["server.log", "actor.log", "occluder.log"]:
		for line: String in FileAccess.get_file_as_string("%s/%s" % [case_dir, log_name]).split("\n"):
			if line.contains("SCRIPT ERROR"):
				runtime_errors.append("%s: %s" % [log_name, line.strip_edges()])
	var report_input: Dictionary = _report_input(case, timestamp_ms, observation, actor, occluder, runtime_errors, ready)
	var report: Dictionary = ReportScript.build(report_input)
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
	return {"id": case_id, "expect": case.get("expect"), "passed": report["passed"], "outcome": report["outcome"],
		"first_failing_stage": report["first_failing_stage"], "report": written.get("path"),
		"failed_assertions": (report["case_assertions"] if report["case_assertions"] is Array else []).filter(
			func(assertion: Dictionary) -> bool: return not assertion["passed"])}


func _report_input(case: Dictionary, timestamp_ms: int, observation: Variant, actor: Variant, occluder: Variant, runtime_errors: Array, server_ready: bool) -> Dictionary:
	var expect: String = case["expect"]
	var obs: Dictionary = observation if observation is Dictionary else {}
	var bound: Dictionary = obs.get("bound", {})
	var records: Array = obs.get("resolutions", [])
	var record: Dictionary = records[0] if records.size() == 1 else {}
	var before: Dictionary = record.get("before", {})
	var after: Dictionary = record.get("after", {})
	var resolution: Variant = record.get("resolution")
	var client: Dictionary = actor if actor is Dictionary else {}
	var assertions: Array[Dictionary] = []
	var accepted: bool = resolution is Dictionary and resolution.get("status") == "accepted"
	_check(assertions, "server became ready", server_ready, true)
	_check(assertions, "exactly one server-received intent", records.size(), 1)
	_check(assertions, "occluder client entered world", (occluder if occluder is Dictionary else {}).get("entered"), true)
	_check(assertions, "Canon store journal_mode is WAL", String(after.get("journal_mode", "")).to_lower(), "wal")
	var writes_before: Dictionary = before.get("canon_writes", {})
	var writes_after: Dictionary = after.get("canon_writes", {})
	var committed_delta: Variant = _delta(writes_before, writes_after, "committed")
	var attempted_delta: Variant = _delta(writes_before, writes_after, "attempted")
	var rolled_back_delta: Variant = _delta(writes_before, writes_after, "rolled_back")
	_check(assertions, "no rolled-back Canon write", rolled_back_delta, 0)
	if expect == "accepted":
		_check(assertions, "resolution accepted", resolution.get("status") if resolution is Dictionary else null, "accepted")
		_check(assertions, "exactly one committed canon_mutations INSERT", committed_delta, 1)
		_check(assertions, "revision advanced by one", int(after.get("revision", -1)) - int(before.get("revision", -1)), 1)
		var rows: Array = after.get("mutations", [])
		var row: Dictionary = rows.back() if not rows.is_empty() else {}
		_check(assertions, "committed row targets gate_01", row.get("target_guid"), after.get("gate_guid"))
		_check(assertions, "committed row actor is the bound actor Character", row.get("actor_player_id"), bound.get("actor", {}).get("character_id"))
		_check(assertions, "committed row kind is unlock_gate", row.get("mutation_kind"), "unlock_gate")
		_check(assertions, "success reported only after COMMIT (applied_revision == committed revision)",
			int(resolution.get("applied_revision", -2)) if resolution is Dictionary else null, after.get("revision"))
		_check(assertions, "effective gate unlocked after commit", (after.get("effective_gate", {}) if after.get("effective_gate") is Dictionary else {}).get("unlocked", false), true)
		_check(assertions, "client received the accepted resolution", (client.get("resolution", {}) if client.get("resolution") is Dictionary else {}).get("status"), "accepted")
	else:
		_check(assertions, "no Canon INSERT/UPDATE attempted", attempted_delta, 0)
		_check(assertions, "revision unchanged", after.get("revision", -1) == before.get("revision", -2), true)
		_check(assertions, "effective gate still locked", (after.get("effective_gate", {}) if after.get("effective_gate") is Dictionary else {}).get("unlocked", false), false)
		if expect == "not_accepted":
			_check(assertions, "no accepted resolution", accepted, false)
		else:
			_check(assertions, "rejection reason", resolution.get("reason") if resolution is Dictionary else null, expect)
			_check(assertions, "client received the same rejection", (client.get("resolution", {}) if client.get("resolution") is Dictionary else {}).get("reason"), expect)
	if case["id"] == "static_obstacle":
		_check(assertions, "declared obstacle is canonical hub content", after.get("obstacle_present"), true)
	if case["id"] == "dynamic_occluders":
		for name: String in ["player", "npc", "monster"]:
			_check(assertions, "%s occluder lies on the actor-to-gate segment" % name, _on_segment(record.get("occluders", {}).get(name), record.get("actor_position"), record.get("target_position")), true)
	var commit: Dictionary = {}
	if committed_delta is int and attempted_delta is int and rolled_back_delta is int:
		var observed_outcome: String = ReportScript.COMMIT_NOT_ATTEMPTED
		if committed_delta > 0:
			observed_outcome = ReportScript.COMMIT_SUCCESS
		elif rolled_back_delta > 0:
			observed_outcome = ReportScript.COMMIT_ROLLED_BACK
		commit = {"status": ReportScript.OBSERVED, "outcome": observed_outcome}
	var required: Array = [ReportScript.STAGE_JOURNEY_IDENTITY, ReportScript.STAGE_COMMIT, ReportScript.STAGE_CASE_ASSERTIONS]
	if case["id"] == "unbound_actor":
		required.erase(ReportScript.STAGE_JOURNEY_IDENTITY)
	var journeys: Array = []
	for role: String in ["actor", "occluder"]:
		var entry: Dictionary = bound.get(role, {})
		journeys.append({"journey_id": entry.get("journey_id", ""), "player_guid": entry.get("character_id", ""), "role": role})
	return {
		"experiment_id": 1231,
		"timestamp_ms": timestamp_ms,
		"scenario": {"name": case["id"], "expected": expect, "required_stages": required,
			"expected_commit": ReportScript.COMMIT_SUCCESS if expect == "accepted" else ReportScript.COMMIT_NOT_ATTEMPTED,
			"reach_rule": "2.0 yd inclusive, server measure as implemented", "gate_point": [0.0, 0.0, -5.0]},
		"commit": commit,
		"sector": {"sector_id": "starting_town_hub"},
		"journeys": journeys,
		"case_assertions": assertions,
		"observations": {"server": observation, "actor_client": actor, "occluder_client": occluder},
		"runtime_errors": runtime_errors,
	}


func _check(assertions: Array[Dictionary], name: String, actual: Variant, expected: Variant) -> void:
	var numeric: bool = typeof(actual) in [TYPE_INT, TYPE_FLOAT] and typeof(expected) in [TYPE_INT, TYPE_FLOAT]
	var container: bool = typeof(actual) in [TYPE_ARRAY, TYPE_DICTIONARY] and typeof(actual) == typeof(expected)
	var passed: bool = actual == null if expected == null else (actual != null and (float(actual) == float(expected) if numeric else (
		JSON.parse_string(JSON.stringify(actual)) == JSON.parse_string(JSON.stringify(expected)) if container else (typeof(actual) == typeof(expected) and actual == expected))))
	assertions.append({"name": name, "expected": expected, "actual": actual, "passed": passed})


func _delta(before: Dictionary, after: Dictionary, window: String) -> Variant:
	if not before.get(window) is Dictionary or not after.get(window) is Dictionary:
		return null
	return int(after[window].get("canon_mutations", 0)) - int(before[window].get("canon_mutations", 0)) \
		+ int(after[window].get("canon_sectors", 0)) - int(before[window].get("canon_sectors", 0))


func _on_segment(point: Variant, start: Variant, end: Variant) -> bool:
	if not (point is Array and start is Array and end is Array):
		return false
	var p: Vector2 = Vector2(point[0], point[2])
	var a: Vector2 = Vector2(start[0], start[2])
	var b: Vector2 = Vector2(end[0], end[2])
	var t: float = (p - a).dot(b - a) / (b - a).length_squared()
	return t > 0.0 and t < 1.0 and p.distance_to(a.lerp(b, t)) <= ON_SEGMENT_TOLERANCE


func _spawn(script: String, log_path: String, extra: Dictionary) -> int:
	var saved: Dictionary = _apply_environment(extra)
	var command: String = "exec '%s' --headless --path '%s' -s %s > '%s' 2>&1" % [
		OS.get_executable_path(), ProjectSettings.globalize_path("res://"), script, log_path]
	var pid: int = OS.create_process("/bin/sh", ["-c", command])
	_restore_environment(saved)
	if pid == -1:
		_harness_errors.append("failed to spawn %s" % script)
	else:
		_processes.append(pid)
	return pid


func _wait_for_log(path: String, needle: String, pid: int, timeout_msec: int) -> bool:
	var deadline: int = Time.get_ticks_msec() + timeout_msec
	while Time.get_ticks_msec() < deadline and OS.is_process_running(pid):
		if FileAccess.get_file_as_string(path).contains(needle):
			return true
		await process_frame
	return false


func _wait_for_exit(pid: int, timeout_msec: int) -> void:
	var deadline: int = Time.get_ticks_msec() + timeout_msec
	while pid != -1 and OS.is_process_running(pid) and Time.get_ticks_msec() < deadline:
		await process_frame


func _stop_owned_processes() -> void:
	# Clients exit on their own (stop file / finished intent); the server is index 0.
	for index: int in range(1, _processes.size()):
		await _wait_for_exit(_processes[index], STOP_TIMEOUT_MSEC)
	for pid: int in _processes:
		if OS.is_process_running(pid):
			OS.kill(pid)
		await _wait_for_exit(pid, STOP_TIMEOUT_MSEC)
		if OS.is_process_running(pid):
			_harness_errors.append("owned process %d did not stop" % pid)
	_processes.clear()


func _apply_environment(values: Dictionary) -> Dictionary:
	var saved: Dictionary = {}
	for key: String in values:
		saved[key] = OS.get_environment(key) if OS.has_environment(key) else null
		OS.set_environment(key, String(values[key]))
	return saved


func _restore_environment(saved: Dictionary) -> void:
	for key: String in saved:
		if saved[key] == null:
			OS.unset_environment(key)
		else:
			OS.set_environment(key, saved[key])


func _free_port() -> int:
	var socket: PacketPeerUDP = PacketPeerUDP.new()
	socket.bind(0, "127.0.0.1")
	var port: int = socket.get_local_port()
	socket.close()
	return port


func _cid(token: String) -> String:
	var claims: Variant = JSON.parse_string(Marshalls.base64_to_utf8(token.split(".")[0]))
	return String(claims.get("cid", "")) if claims is Dictionary else ""


func _git_head() -> String:
	var output: Array = []
	OS.execute("git", ["-C", ProjectSettings.globalize_path("res://"), "rev-parse", "HEAD"], output)
	return String(output[0]).strip_edges() if not output.is_empty() else ""


func _read_json(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null


func _write_json(path: String, value: Variant) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value, "\t"))
	file.close()
