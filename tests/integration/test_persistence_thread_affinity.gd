extends GutTest

const FIXTURE_PATH: String = "res://tests/fixtures/persistence_thread_affinity_fixture.gd"
const MODES: Array[String] = ["candidate", "main_sqlite_control", "main_wait_control"]
const NOT_OBSERVED: String = "NOT_OBSERVED"
const MAX_REPORT_BYTES: int = 262144
const MAX_TOTAL_SPANS: int = 576

# Preserve unfinished owner objects for controller containment; never close on main.
var _unfinished_owners: Array[RefCounted] = []


func test_direct_sqlite_worker_lifecycle_has_complete_fixture_coverage() -> void:
	var fixture_exists: bool = FileAccess.file_exists(FIXTURE_PATH)
	assert_true(fixture_exists, "1444 affinity experiment fixture exists before lifecycle qualification")
	if not fixture_exists:
		return
	var fixture_script: Script = load(FIXTURE_PATH) as Script
	assert_not_null(fixture_script, "1444 bounded affinity fixture loads")
	if fixture_script == null:
		return
	var report: Dictionary = {"schema_version": 1, "experiment": "1444", "modes": [], "clock": {"units": "us", "samples_usec": []},
		"loaded_addon": {}, "source_fixture_sha256": "", "limits": {"spans_per_mode": 256, "spans_total": 576, "mailbox_bytes": 65536, "thread_return_bytes": 131072, "report_bytes": 262144,
		"proc_line_bytes": 8192, "proc_total_bytes": 1048576}, "exact_target_futex_identity": NOT_OBSERVED,
		"continuous_wait_duration": NOT_OBSERVED, "production_acceptance": NOT_OBSERVED}
	for mode: String in MODES:
		var fixture: RefCounted = fixture_script.new()
		var directory: String = ProjectSettings.globalize_path("user://affinity-1444-" + mode)
		var initial: Dictionary = fixture.call("initialize", mode, directory)
		assert_true(initial["initialized"], "1444 isolated owner initializes")
		if not initial["initialized"]:
			report["modes"].append(fixture.call("finalize_completed"))
			break
		if report["clock"]["samples_usec"].is_empty():
			report["clock"]["samples_usec"] = initial["clock_samples_usec"]
			report["loaded_addon"] = initial["loaded_addon"]
			report["source_fixture_sha256"] = initial["source_fixture_sha256"]
		else:
			assert_true(initial["loaded_addon"] == report["loaded_addon"], "1444 all modes observe the same loaded member")
			assert_true(initial["source_fixture_sha256"] == report["source_fixture_sha256"], "1444 fixture source stays fixed")
		var ready: bool = false
		var deadline: int = Time.get_ticks_usec() + 1000000
		while not ready and Time.get_ticks_usec() < deadline:
			var polled: Dictionary = fixture.call("poll_once")
			ready = polled["state"] == "ready"
			if not ready:
				await get_tree().process_frame
		assert_true(ready, "1444 prestarted owner reaches readiness")
		var submitted: bool = false
		deadline = Time.get_ticks_usec() + 150000
		while ready and not submitted and Time.get_ticks_usec() < deadline:
			var reply: Dictionary = fixture.call("try_submit", "affinity-1444")
			submitted = reply["state"] == "submitted"
			if not submitted:
				await get_tree().process_frame
		assert_true(submitted, "1444 one bounded request is accepted")
		var complete: bool = false
		while submitted and not complete and Time.get_ticks_usec() < deadline:
			var polled: Dictionary = fixture.call("poll_once")
			complete = polled["state"] == "complete"
			if not complete:
				await get_tree().process_frame
		assert_true(complete, "1444 request includes release and observed owner termination within its bound")
		# A missed request bound stays failed, while owner-local cleanup gets its fixed bound.
		deadline = Time.get_ticks_usec() + 3000000
		while not complete and Time.get_ticks_usec() < deadline:
			var polled: Dictionary = fixture.call("poll_once")
			complete = polled["state"] == "complete"
			if not complete:
				await get_tree().process_frame
		var outcome: Dictionary = fixture.call("finalize_completed")
		report["modes"].append(outcome)
		_check_mode(outcome)
		if not outcome["worker_joined"]:
			_unfinished_owners.append(fixture)
			break
	assert_true(report["modes"].size() == 3, "1444 exactly three fixed modes execute once")
	var positive_clock_step: bool = false
	var previous: int = -1
	for sample: int in report["clock"]["samples_usec"]:
		assert_true(sample >= previous, "1444 raw clock samples stay monotonic")
		positive_clock_step = positive_clock_step or (previous >= 0 and sample > previous)
		previous = sample
	assert_true(positive_clock_step, "1444 clock calibration actually observes a positive step")
	assert_true(report["loaded_addon"].get("selected_mode", NOT_OBSERVED) in ["debug", "release"], "1444 exactly one known addon member is mapped")
	assert_true(report["loaded_addon"].get("mapped_member_sha256", "").length() == 64, "1444 mapped resource bytes are hashed")
	var total_spans: int = 0
	for outcome: Dictionary in report["modes"]:
		total_spans += outcome["spans"].size()
	assert_true(total_spans <= MAX_TOTAL_SPANS, "1444 complete paired-span evidence fits its fixed aggregate bound")
	var evidence_path: String = OS.get_environment("PROJECT0_AFFINITY_EVIDENCE_PATH")
	if not evidence_path.is_empty():
		assert_true(_retain_evidence(evidence_path, report), "1444 bounded primitive evidence is retained after teardown")


func _check_mode(outcome: Dictionary) -> void:
	assert_true(outcome["status"] == "complete", _mode_failure_message(outcome))
	if outcome["status"] != "complete":
		return
	assert_true(outcome["owned_state_removed"], "1444 only known owned disposable files are removed")
	assert_true(outcome["worker_joined"], "1444 complete trace is acquired after termination")
	assert_true(outcome["worker_caller"] != outcome["main_caller"], "1444 worker has its own caller identity")
	assert_true(outcome["window_begin_usec"] <= outcome["worker_return_usec"], "1444 request covers the owner's final trace return")
	assert_true(outcome["worker_return_usec"] <= outcome["termination_observed_usec"], "1444 owner return precedes observed termination")
	assert_true(outcome["termination_observed_usec"] <= outcome["window_end_usec"], "1444 window includes termination observation")
	assert_true(outcome["window_end_usec"] < outcome["teardown_begin_usec"], "1444 join and file work remain outside the request")
	var native_main_elapsed: int = 0
	var native_main_entries: int = 0
	var blocking_main_entries: int = 0
	for span: Dictionary in outcome["spans"]:
		assert_true(span.has("operation"), "1444 trace never silently truncates")
		if not span.has("operation"):
			continue
		assert_true(span["end_usec"] >= span["begin_usec"], "1444 every raw span remains monotonic")
		assert_true(span["caller_begin"] == span["caller_end"], "1444 supported call preserves its actual caller")
		assert_true(span["caller_begin"] == span["owner"], "1444 supported call executes on its declared owner")
		if span["phase"] == "request" and span["caller_begin"] == outcome["main_caller"]:
			if span["operation"].begins_with("sqlite."):
				native_main_entries += 1
				native_main_elapsed += span["end_usec"] - span["begin_usec"]
			if span["operation"] in ["mutex.lock", "thread.wait_to_finish", "os.delay_usec"]:
				blocking_main_entries += 1
	for lifecycle: Dictionary in outcome["lifecycles"]:
		assert_true(lifecycle["success"], "1444 fixed native commit/rollback/reopen lifecycle succeeds")
		assert_true(lifecycle["cycles"].size() == (2 if lifecycle["role"] == "worker" else 1), "1444 each role completes its fixed native cycle inventory")
		for cycle: Dictionary in lifecycle["cycles"]:
			assert_true(cycle["committed_rows"] == [[7]], "1444 authored committed row persists")
			assert_true(cycle["rolled_back_rows"] == [], "1444 rolled back row never persists")
			assert_true(cycle["release"].get("weakref_null", false), "1444 last native owning reference is released on its owner")
	if outcome["mode"] == "candidate":
		assert_true(native_main_entries == 0, "1444 candidate forbids every supported main SQLite entry even at equal ticks")
		assert_true(blocking_main_entries == 0, "1444 candidate forbids every supported main blocking entry even at equal ticks")
	elif outcome["mode"] == "main_sqlite_control":
		assert_true(native_main_entries > 0 and native_main_elapsed > 0, "1444 fixed main SQLite control exposes positive raw synchronous call work")
	else:
		var wait: Dictionary = outcome["wait"]
		assert_true(wait.get("failed_try_lock", false), "1444 wait control actually encounters the owned locked mutex")
		assert_true(wait["futex_class"] == "APPROVED_FUTEX_WAIT", "1444 wait control corroborates generic main futex sleep")
		assert_true(wait["main_lock_end_usec"] > wait["main_lock_begin_usec"], "1444 wait control has a positive elapsed lock-call span")
		assert_true(wait["main_lock_begin_usec"] <= wait["observation_begin_usec"] and wait["observation_begin_usec"] <= wait["observation_end_usec"], "1444 sleep sample belongs to the direct lock interval")
		assert_true(wait["observation_end_usec"] < wait["worker_unlock_begin_usec"] and wait["worker_unlock_begin_usec"] < wait["main_lock_end_usec"], "1444 owner retains control until observed sleep before unlocking")
		assert_true(wait["exact_target_identity"] == NOT_OBSERVED, "1444 sleep corroboration claims no exact target-futex identity")
		assert_true(wait["continuous_wait_duration"] == NOT_OBSERVED, "1444 elapsed lock-call time is not continuous waiting time")


func _mode_failure_message(outcome: Dictionary) -> String:
	if outcome.get("status", "") == "complete":
		return "1444 encountered native lifecycle failures remain failures"
	if not MODES.has(outcome.get("mode", "")) or not outcome.get("status", "") in ["failed", "unqualified"]:
		return "1444 failure category remains unknown"
	for field: String in ["worker_terminated", "worker_joined", "owned_state_removed"]:
		if typeof(outcome.get(field)) != TYPE_BOOL:
			return "1444 failure category remains unknown"
	if outcome["worker_joined"] and not outcome["worker_terminated"]:
		return "1444 failure category remains unknown"
	if not outcome["worker_terminated"] or not outcome["worker_joined"]:
		return "1444 owner termination or join remains unqualified"
	var lifecycles: Variant = outcome.get("lifecycles")
	if typeof(lifecycles) != TYPE_ARRAY or lifecycles.is_empty() or lifecycles.size() > 2:
		return "1444 failure category remains unknown"
	var native_failed: bool = false
	var lifecycles_succeeded: bool = true
	for lifecycle: Variant in lifecycles:
		if typeof(lifecycle) != TYPE_DICTIONARY or typeof(lifecycle.get("success")) != TYPE_BOOL:
			return "1444 failure category remains unknown"
		var cycles: Variant = lifecycle.get("cycles")
		if typeof(cycles) != TYPE_ARRAY or cycles.is_empty() or cycles.size() > 2:
			return "1444 failure category remains unknown"
		lifecycles_succeeded = lifecycles_succeeded and lifecycle["success"]
		var cycle_failed: bool = false
		for cycle: Variant in cycles:
			if typeof(cycle) != TYPE_DICTIONARY or typeof(cycle.get("success")) != TYPE_BOOL:
				return "1444 failure category remains unknown"
			cycle_failed = cycle_failed or not cycle["success"]
		if cycle_failed and lifecycle["success"]:
			return "1444 failure category remains unknown"
		native_failed = native_failed or cycle_failed
	if native_failed:
		return "1444 native lifecycle observation remains unqualified"
	if not outcome["owned_state_removed"] or outcome.get("failure_class", "") == "teardown_or_trace_unqualified":
		return "1444 teardown or trace remains unqualified"
	if lifecycles_succeeded and outcome.get("mode", "") == "main_wait_control" and outcome.get("failure_class", "") == "owner_lifecycle_unqualified":
		var wait: Variant = outcome.get("wait")
		if typeof(wait) == TYPE_DICTIONARY and wait.get("futex_class", "") == NOT_OBSERVED:
			return "1444 wait observation remains unqualified"
	return "1444 failure category remains unknown"


func _retain_evidence(path: String, report: Dictionary) -> bool:
	if not path.is_absolute_path() or path.get_file() != "affinity-evidence.json" or FileAccess.file_exists(path):
		return false
	var parent: DirAccess = DirAccess.open(path.get_base_dir())
	if parent == null or parent.is_link(path.get_file()):
		return false
	var total_spans: int = 0
	for outcome: Dictionary in report["modes"]:
		total_spans += outcome["spans"].size()
	if total_spans > MAX_TOTAL_SPANS:
		return false
	var payload: String = JSON.stringify(report)
	if payload.to_utf8_buffer().size() > MAX_REPORT_BYTES:
		return false
	var stream: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if stream == null:
		return false
	stream.store_string(payload)
	var written: bool = stream.get_error() == OK
	stream.close()
	return written and FileAccess.get_file_as_string(path) == payload
