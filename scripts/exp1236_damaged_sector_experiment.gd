extends "res://scripts/exp1231_gate_unlock_experiment.gd"
## Experiment #1236 orchestrator (Linux host only): damaged-sector quarantine
## with healthy-sector continuity. Per case: one fresh server with an isolated
## WAL Canon DB, an observer moving in the healthy hub for the whole case, and
## two sequential actor admissions at the target sector. A read-only sqlite3
## process verifies the faulted rows after the server exits.
##   godot --headless --path . -s scripts/exp1236_damaged_sector_experiment.gd

const TARGET: String = "sector-0-0"
const HUB: String = "starting_town_hub"
const TARGET_POSITION: Array = [200.0, 1.0, 200.0]
## intact_control is a declared harness control: undamaged Canon must present.
const CASES_1236: Array[Dictionary] = [
	{"id": "intact_control", "failure_class": null},
	{"id": "base_unavailable", "failure_class": "base_missing"},
	{"id": "blueprint_corrupt", "failure_class": "blueprint_corrupt"},
	{"id": "mutation_corrupt", "failure_class": "mutation_corrupt"},
	{"id": "replay_inconsistent", "failure_class": "replay_inconsistent"},
]
const TIMEOUTS_1236: Dictionary = {
	"server_ready": 20000, "setup": 10000, "observer_moving": 30000, "actor": 45000,
	"readmission_gap": 1500, "continuity": 3000, "finalize": 10000, "stop": 5000,
}
const MIN_PATH_YARDS: float = 1.0
const MAX_UPDATE_GAP_MSEC: int = 1000
const MIN_OBSERVER_UPDATES: int = 20
const BLOCKED_TOLERANCE: float = 0.5


func _experiment_id() -> int:
	return 1236


func _cases() -> Array[Dictionary]:
	return CASES_1236


func _fixture_script() -> String:
	return "scripts/exp1236_sector_fixture.gd"


func _client_script() -> String:
	return "scripts/exp1236_client.gd"


func _run_case(case: Dictionary, timestamp_ms: int) -> Dictionary:
	if not FileAccess.file_exists("%s/manifest.json" % _run_dir):
		_write_json("%s/manifest.json" % _run_dir, {"experiment_id": 1236, "cases": CASES_1236, "timeouts_msec": TIMEOUTS_1236,
			"thresholds": {"min_path_yards": MIN_PATH_YARDS, "max_update_gap_msec": MAX_UPDATE_GAP_MSEC,
				"min_observer_updates": MIN_OBSERVER_UPDATES, "blocked_tolerance": BLOCKED_TOLERANCE}})
	var case_id: String = case["id"]
	var case_dir: String = "%s/%s" % [_run_dir, case_id]
	DirAccess.make_dir_recursive_absolute(case_dir)
	var session: Dictionary = GameplayTestSessionScript.begin()
	GameplayTestSessionScript.refresh_identity()
	var observer_token: String = OS.get_environment(GameplayTestSessionScript.ASSERTION_ENV)
	GameplayTestSessionScript.refresh_identity()
	var actor_token: String = OS.get_environment(GameplayTestSessionScript.ASSERTION_ENV)
	var canon_db: String = "exp1236_canon_%s_%d_%d.db" % [case_id, OS.get_process_id(), Time.get_ticks_usec()]
	var canon_path: String = ProjectSettings.globalize_path("user://%s" % canon_db)
	var obs: String = "%s/server-observation.json" % case_dir
	var saved: Dictionary = _apply_environment({
		"PROJECT0_SERVER_PORT": str(_free_port()),
		"PROJECT0_SERVER_BIND_ADDRESS": "127.0.0.1",
		"PROJECT0_OPERATOR_CONTROL_PORT": "0",
		"PROJECT0_CANON_DB_PATH": canon_db,
		"EXP1236_CASE": case_id,
		"EXP1236_ACTOR_CID": _cid(actor_token),
		"EXP1236_OBSERVER_CID": _cid(observer_token),
		"EXP1236_OBSERVATION": obs,
		"EXP1236_FINALIZE": "%s/finalize" % case_dir,
		"EXP1236_STOP": "%s/stop" % case_dir,
	})
	var lifecycle: Dictionary = {}
	var server: int = _spawn(_fixture_script(), "%s/server.log" % case_dir, {})
	lifecycle["server_ready"] = await _wait_for_log("%s/server.log" % case_dir, "Server listening on", server, TIMEOUTS_1236["server_ready"])
	lifecycle["setup_complete"] = false
	if lifecycle["server_ready"]:
		lifecycle["setup_complete"] = await _wait_observation(obs, func(o: Dictionary) -> bool: return o.has("window_start"), TIMEOUTS_1236["setup"])
	if lifecycle["setup_complete"]:
		_spawn(_client_script(), "%s/observer.log" % case_dir, {"EXP1236_ROLE": "observer",
			"EXP1236_RESULT": "%s/observer-result.json" % case_dir, GameplayTestSessionScript.ASSERTION_ENV: observer_token})
		var moving: Callable = func(o: Dictionary) -> bool: return _path_length(o.get("samples", []), "observer", -1) >= MIN_PATH_YARDS
		lifecycle["observer_moving"] = await _wait_observation(obs, moving, TIMEOUTS_1236["observer_moving"])
		for phase: String in ["first", "second"]:
			var actor: int = _spawn(_client_script(), "%s/actor-%s.log" % [case_dir, phase], {"EXP1236_ROLE": "actor", "EXP1236_PHASE": phase,
				"EXP1236_RESULT": "%s/actor-%s-result.json" % [case_dir, phase], GameplayTestSessionScript.ASSERTION_ENV: actor_token})
			await _wait_for_exit(actor, TIMEOUTS_1236["actor"])
			lifecycle["actor_%s_exited" % phase] = not OS.is_process_running(actor)
			await _pause(TIMEOUTS_1236["readmission_gap"])
		await _pause(TIMEOUTS_1236["continuity"])
		FileAccess.open("%s/finalize" % case_dir, FileAccess.WRITE).close()
		await _wait_for_exit(server, TIMEOUTS_1236["finalize"])
		lifecycle["server_exited_after_finalize"] = not OS.is_process_running(server)
	FileAccess.open("%s/stop" % case_dir, FileAccess.WRITE).close()
	await _stop_owned_processes()
	lifecycle["independent_rows"] = _observe_rows(canon_path)
	var results: Dictionary = {}
	for name: String in ["observer", "actor-first", "actor-second"]:
		results[name] = _read_json("%s/%s-result.json" % [case_dir, name])
	var runtime_errors: Array = []
	for log_name: String in ["server.log", "observer.log", "actor-first.log", "actor-second.log"]:
		for line: String in FileAccess.get_file_as_string("%s/%s" % [case_dir, log_name]).split("\n"):
			if line.contains("SCRIPT ERROR"):
				runtime_errors.append("%s: %s" % [log_name, line.strip_edges()])
	var server_log: String = FileAccess.get_file_as_string("%s/server.log" % case_dir)
	var report: Dictionary = ReportScript.build(_report_1236(case, timestamp_ms, _read_json(obs), results, lifecycle, server_log, runtime_errors))
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


func _report_1236(case: Dictionary, timestamp_ms: int, observation: Variant, results: Dictionary, lifecycle: Dictionary, server_log: String, runtime_errors: Array) -> Dictionary:
	var obs: Dictionary = observation if observation is Dictionary else {}
	var setup: Dictionary = obs.get("setup", {}) if obs.get("setup") is Dictionary else {}
	var final: Dictionary = obs.get("final", {}) if obs.get("final") is Dictionary else {}
	var expected_class: Variant = case["failure_class"]
	var damaged: bool = expected_class != null
	var observer: Dictionary = results["observer"] if results["observer"] is Dictionary else {}
	var actors: Array = [results["actor-first"], results["actor-second"]].map(func(value: Variant) -> Dictionary: return value if value is Dictionary else {})
	var bound: Array = obs.get("bound", [])
	var actor_binds: Array = bound.filter(func(entry: Dictionary) -> bool: return entry.get("role") == "actor")
	var observer_binds: Array = bound.filter(func(entry: Dictionary) -> bool: return entry.get("role") == "observer")
	var actor_peers: Array = actor_binds.map(func(entry: Dictionary) -> int: return int(entry.get("peer_id", -1)))
	var events: Array = (final.get("quarantine", {}) if final.get("quarantine") is Dictionary else {}).get("events", []) if final.get("quarantine") is Dictionary else []
	var quarantined: Dictionary = final.get("quarantine", {}).get("quarantined", {}) if final.get("quarantine") is Dictionary else {}
	var target_events: Array = events.filter(func(event: Dictionary) -> bool: return event.get("sector_id") == TARGET)
	var telemetry: Array = obs.get("telemetry", [])
	var writes: Variant = _delta(obs.get("window_start", {}).get("canon_writes", {}) if obs.get("window_start") is Dictionary else {},
		final.get("counters", {}).get("canon_writes", {}) if final.get("counters") is Dictionary else {}, "attempted")
	var generation: Variant = null
	if obs.get("window_start") is Dictionary and final.get("counters") is Dictionary:
		generation = int(final["counters"].get("generation_count", -1)) - int(obs["window_start"].get("generation_count", -1))
	var target_presented_to_actor: Array = obs.get("presentations", []).filter(func(entry: Dictionary) -> bool: return entry.get("sector_id") == TARGET and actor_peers.has(int(entry.get("peer_id", -2))))
	var target_reloads: Array = obs.get("reload_events", []).filter(func(event: Dictionary) -> bool: return event.get("sector_id") == TARGET)
	var expected_rows: Variant = setup.get("faulted_rows")
	var independent: Dictionary = lifecycle.get("independent_rows") if lifecycle.get("independent_rows") is Dictionary else {}
	var assertions: Array[Dictionary] = []
	_check(assertions, "server became ready", lifecycle.get("server_ready"), true)
	_check(assertions, "fixture setup completed before the measured window", lifecycle.get("setup_complete"), true)
	_check(assertions, "setup: target canonicalized through the real repository", setup.get("target_canonicalize"), "ok")
	_check(assertions, "setup: target mutation history applied", setup.get("target_mutation"), "ok")
	_check(assertions, "setup: healthy hub mutation history applied", setup.get("control_mutation"), "ok")
	_check(assertions, "setup: Canon store journal_mode is WAL", String(setup.get("journal_mode", "")).to_lower(), "wal")
	_check(assertions, "setup: declared fault applied to owned rows", setup.get("fault_applied"), true)
	_check(assertions, "fault input changed the owned rows" if damaged else "control left the rows unchanged",
		JSON.stringify(setup.get("faulted_rows")) != JSON.stringify(setup.get("original_rows")), damaged)
	_check(assertions, "observer entered the healthy hub", [observer.get("entered"), observer.get("failure")], [true, null])
	_check(assertions, "observer was moving before the first actor admission", lifecycle.get("observer_moving"), true)
	_check(assertions, "actor admitted twice (second admission after the first decision)",
		[actor_binds.size(), actors[0].get("entered"), actors[1].get("entered"), actors[0].get("failure"), actors[1].get("failure")], [2, true, true, null, null])
	var decision_frame: int = _last_decision_frame(obs, actor_peers, damaged)
	_check(assertions, "observer kept moving after the last target decision (server samples)",
		_path_length(obs.get("samples", []), "observer", decision_frame) >= MIN_PATH_YARDS if decision_frame >= 0 else null, true)
	var movement: Dictionary = observer.get("movement", {}) if observer.get("movement") is Dictionary else {}
	_check(assertions, "observer received continuous authoritative updates",
		[int(movement.get("updates", 0)) >= MIN_OBSERVER_UPDATES, movement.get("max_gap_msec") != null and int(movement.get("max_gap_msec")) <= MAX_UPDATE_GAP_MSEC], [true, true])
	_check(assertions, "global loop advanced after the last target decision",
		int(final.get("tick", -1)) > _tick_at_frame(obs, decision_frame) if decision_frame >= 0 else null, true)
	_check(assertions, "server finalized orderly with the observer still connected",
		[lifecycle.get("server_exited_after_finalize"), int(final.get("connected_players", 0)) >= 1], [true, true])
	var observer_peers: Array = observer_binds.map(func(bind: Dictionary) -> int: return int(bind["peer_id"]))
	_check(assertions, "healthy hub presented to the observer", obs.get("presentations", []).any(func(entry: Dictionary) -> bool: return entry.get("sector_id") == HUB and observer_peers.has(int(entry.get("peer_id", -1)))), true)
	_check(assertions, "healthy hub never quarantined", quarantined.has(HUB), false)
	_check(assertions, "no Canon INSERT/UPDATE attempted in the measured window", writes, 0)
	_check(assertions, "no content generation requested in the measured window", generation, 0)
	_check(assertions, "no generation request logged", server_log.contains("Requested provisional sector"), false)
	_check(assertions, "Canon rows preserved exactly (in-process read at finalize)", final.get("rows"), expected_rows)
	_check(assertions, "Canon rows preserved exactly (independent read-only sqlite3 after exit)",
		{"canon_sectors": independent.get("canon_sectors"), "canon_mutations": independent.get("canon_mutations")}, expected_rows)
	_check(assertions, "independent observer saw WAL journal mode", String(independent.get("journal_mode", "")).to_lower(), "wal")
	_check(assertions, "no inability-to-observe diagnostic (damage was observed)",
		telemetry.filter(func(entry: Dictionary) -> bool: return entry.get("event_type") == "canon.sector_unobservable").size(), 0)
	if damaged:
		var record: Dictionary = quarantined.get(TARGET, {}) if quarantined.get(TARGET) is Dictionary else {}
		_check(assertions, "target quarantined with the declared failure class and high severity", [record.get("failure_class"), record.get("severity")], [expected_class, "high"])
		_check(assertions, "exactly one quarantine event for the target",
			target_events.filter(func(event: Dictionary) -> bool: return event.get("event_type") == "CANON_SECTOR_QUARANTINED").size(), 1)
		_check(assertions, "one entry denial per actor admission",
			target_events.filter(func(event: Dictionary) -> bool: return event.get("event_type") == "CANON_SECTOR_ENTRY_DENIED").map(func(event: Dictionary) -> int: return int(event.get("peer_id", -1))), actor_peers)
		_check(assertions, "high-severity telemetry names the sector and failure class", _telemetry_summary(telemetry),
			{"canon.sector_quarantined": 1, "canon.sector_entry_denied": 2, "all_high": true, "all_target": true, "all_class": expected_class})
		for index: int in range(2):
			var denials: Array = actors[index].get("denials", []).map(func(entry: Dictionary) -> Variant: return entry.get("denial"))
			_check(assertions, "actor admission %d received exactly one explicit denial" % (index + 1), denials,
				[{"sector_id": TARGET, "reason_code": "sector_quarantined", "failure_class": expected_class}])
			_check(assertions, "actor admission %d received no target blueprint" % (index + 1),
				actors[index].get("blueprints", []).filter(func(entry: Dictionary) -> bool: return entry.get("sector_id") == TARGET).size(), 0)
		_check(assertions, "target never presented to the actor", target_presented_to_actor.size(), 0)
		_check(assertions, "no CANON_SECTOR_RELOADED recorded for the target", target_reloads.size(), 0)
		_check(assertions, "no CANON_SECTOR_RELOADED logged for the target", server_log.contains("CANON_SECTOR_RELOADED sector_id=%s" % TARGET), false)
		_check(assertions, "actor movement stayed blocked at the target (server samples)", _max_offset(obs.get("samples", []), "actor") <= BLOCKED_TOLERANCE, true)
	else:
		_check(assertions, "intact target not quarantined and no denial", [quarantined.has(TARGET), target_events.size(), _telemetry_summary(telemetry)["canon.sector_entry_denied"]], [false, 0, 0])
		_check(assertions, "intact target presented on each actor admission", target_presented_to_actor.size(), 2)
		_check(assertions, "one CANON_SECTOR_RELOADED per actor admission", target_reloads.map(func(event: Dictionary) -> int: return int(event.get("peer_id", -1))), actor_peers)
		for index: int in range(2):
			_check(assertions, "actor admission %d received the target blueprint and no denial" % (index + 1),
				[actors[index].get("blueprints", []).any(func(entry: Dictionary) -> bool: return entry.get("sector_id") == TARGET), actors[index].get("denials", []).size()], [true, 0])
	var commit: Dictionary = {}
	if writes is int:
		commit = {"status": ReportScript.OBSERVED, "outcome": ReportScript.COMMIT_NOT_ATTEMPTED if writes == 0 else ReportScript.COMMIT_SUCCESS}
	var journeys: Array = []
	for binds: Array in [actor_binds, observer_binds]:
		var entry: Dictionary = binds[0] if not binds.is_empty() else {}
		# Per-journey counts are bounded by the measured window totals; zero totals mean zero for each journey.
		journeys.append({"journey_id": entry.get("journey_id", ""), "player_guid": entry.get("character_id", ""), "role": entry.get("role", ""),
			"generation_count": generation if generation is int and generation == 0 else null,
			"canon_write_count": writes if writes is int and writes == 0 else null})
	return {
		"experiment_id": 1236,
		"timestamp_ms": timestamp_ms,
		"scenario": {"name": case["id"], "expected_failure_class": expected_class,
			"expected": "quarantine_and_deny" if damaged else "present_intact_control",
			"required_stages": [ReportScript.STAGE_JOURNEY_IDENTITY, ReportScript.STAGE_COMMIT, ReportScript.STAGE_SECTOR_TOTALS,
				ReportScript.STAGE_PLAYER_COUNTS, ReportScript.STAGE_CASE_ASSERTIONS],
			"expected_commit": ReportScript.COMMIT_NOT_ATTEMPTED, "target_sector": TARGET, "control_sector": HUB,
			"target_position": TARGET_POSITION},
		"commit": commit,
		"sector": {"sector_id": TARGET, "generation_count": generation, "canon_write_count": writes},
		"journeys": journeys,
		"case_assertions": assertions,
		"observations": {"server": observation, "clients": results, "lifecycle": lifecycle,
			"fault_input": {"sql": setup.get("fault_sql"), "original_rows": setup.get("original_rows"), "faulted_rows": setup.get("faulted_rows")}},
		"runtime_errors": runtime_errors,
	}


## Frame of the last server decision about the target for an actor peer: denial events in
## damaged cases, target presentations in the intact control. -1 when none was observed.
func _last_decision_frame(obs: Dictionary, actor_peers: Array, damaged: bool) -> int:
	var frame: int = -1
	if damaged:
		for event: Dictionary in obs.get("telemetry", []):
			if event.get("event_type") == "canon.sector_entry_denied" and actor_peers.has(int(event.get("peer_id", -2))):
				frame = maxi(frame, _frame_at_tick(obs, int(event.get("tick", -1))))
	else:
		for entry: Dictionary in obs.get("presentations", []):
			if entry.get("sector_id") == TARGET and actor_peers.has(int(entry.get("peer_id", -2))):
				frame = maxi(frame, int(entry.get("frame", -1)))
	return frame


## Server ticks and fixture frames advance together; map a tick to the first sample frame at or after it.
func _frame_at_tick(obs: Dictionary, tick: int) -> int:
	for sample: Dictionary in obs.get("samples", []):
		if int(sample.get("tick", -1)) >= tick:
			return int(sample.get("frame", -1))
	return -1


func _tick_at_frame(obs: Dictionary, frame: int) -> int:
	for sample: Dictionary in obs.get("samples", []):
		if int(sample.get("frame", -1)) >= frame:
			return int(sample.get("tick", -1))
	return 1 << 62


func _path_length(samples: Array, role: String, after_frame: int) -> float:
	var length: float = 0.0
	var previous: Variant = null
	for sample: Dictionary in samples:
		if sample.get("role") != role or int(sample.get("frame", -1)) <= after_frame:
			continue
		var position: Vector3 = Vector3(sample["position"][0], sample["position"][1], sample["position"][2])
		if previous is Vector3:
			length += (previous as Vector3).distance_to(position)
		previous = position
	return length


func _max_offset(samples: Array, role: String) -> Variant:
	var target: Vector3 = Vector3(TARGET_POSITION[0], TARGET_POSITION[1], TARGET_POSITION[2])
	var largest: float = -1.0
	for sample: Dictionary in samples:
		if sample.get("role") == role:
			largest = maxf(largest, Vector2(sample["position"][0] - target.x, sample["position"][2] - target.z).length())
	return largest if largest >= 0.0 else INF


func _telemetry_summary(telemetry: Array) -> Dictionary:
	var summary: Dictionary = {"canon.sector_quarantined": 0, "canon.sector_entry_denied": 0, "all_high": true, "all_target": true, "all_class": null}
	var classes: Dictionary = {}
	for entry: Dictionary in telemetry:
		var event_type: String = String(entry.get("event_type", ""))
		if summary.has(event_type):
			summary[event_type] += 1
		var payload: Dictionary = entry.get("payload", {}) if entry.get("payload") is Dictionary else {}
		summary["all_high"] = summary["all_high"] and payload.get("severity") == "high"
		summary["all_target"] = summary["all_target"] and payload.get("sector_id") == TARGET
		classes[payload.get("failure_class")] = true
	if classes.size() == 1:
		summary["all_class"] = classes.keys()[0]
	return summary


func _wait_observation(path: String, predicate: Callable, timeout_msec: int) -> bool:
	var deadline: int = Time.get_ticks_msec() + timeout_msec
	while Time.get_ticks_msec() < deadline:
		var observation: Variant = _read_json(path)
		if observation is Dictionary and predicate.call(observation):
			return true
		await process_frame
	return false


func _pause(msec: int) -> void:
	var deadline: int = Time.get_ticks_msec() + msec
	while Time.get_ticks_msec() < deadline:
		await process_frame


## Independent observer: a separate read-only sqlite3 process reads the committed rows.
func _observe_rows(db_path: String) -> Variant:
	var script: String = "\n".join([
		"import json, sqlite3, sys",
		"c = sqlite3.connect('file:' + sys.argv[1] + '?mode=ro', uri=True)",
		"c.row_factory = sqlite3.Row",
		"rows = lambda q: [dict(r) for r in c.execute(q)]",
		"print(json.dumps({'canon_sectors': rows('SELECT * FROM canon_sectors ORDER BY sector_id'),",
		"  'canon_mutations': rows('SELECT * FROM canon_mutations ORDER BY sector_id, event_id'),",
		"  'journal_mode': c.execute('PRAGMA journal_mode').fetchone()[0]}))",
	])
	var script_path: String = db_path.get_base_dir().path_join("exp1236_observer.py")
	var file: FileAccess = FileAccess.open(script_path, FileAccess.WRITE)
	file.store_string(script)
	file.close()
	var output: Array = []
	var code: int = OS.execute("python3", [script_path, db_path], output, true)
	DirAccess.remove_absolute(script_path)
	var parsed: Variant = JSON.parse_string(String(output[0]).strip_edges()) if code == 0 and not output.is_empty() else null
	return parsed if parsed is Dictionary else {"error": String(output[0]) if not output.is_empty() else "no output", "exit_code": code}
