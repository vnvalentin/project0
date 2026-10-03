extends RefCounted
## Disposable direct-native experiment only; no application executor or routing.

const MODES: Array[String] = ["candidate", "main_sqlite_control", "main_wait_control"]
const MAX_SPANS: int = 256
const MAX_MESSAGE_BYTES: int = 65536
const MAX_THREAD_RETURN_BYTES: int = 131072
const INIT_LIMIT_US: int = 1000000
const REQUEST_LIMIT_US: int = 150000
const WORKER_LIMIT_US: int = 3000000
const WAIT_HOLD_US: int = 20000
const PROC_LINE_BYTES: int = 8192
const PROC_TOTAL_BYTES: int = 1048576
const NOT_OBSERVED: String = "NOT_OBSERVED"

var _mode: String = ""
var _directory: String = ""
var _main_owner: int = 0
var _worker_owner: int = 0
var _mailbox: Mutex
var _control: Mutex
var _thread: Thread
var _mailbox_id: int = 0
var _control_id: int = 0
var _thread_id: int = 0
var _state_created: bool = false
var _started: bool = false
var _ready: bool = false
var _requested: bool = false
var _completion_ready: bool = false
var _completion: Dictionary = {}
var _consumed: bool = false
var _submitted: bool = false
var _window_begin: int = 0
var _window_end: int = 0
var _initialization_begin: int = 0
var _initialization_end: int = 0
var _termination_tick: int = 0
var _main_spans: Array[Dictionary] = []
var _main_lifecycle: Dictionary = {}
var _main_wait: Dictionary = {}
var _initial: Dictionary = {}


func initialize(mode: String, owned_directory: String) -> Dictionary:
	_initialization_begin = Time.get_ticks_usec()
	_main_owner = OS.get_thread_caller_id()
	_mode = mode
	_directory = owned_directory
	var samples: Array[int] = []
	for _index: int in range(32):
		samples.append(Time.get_ticks_usec())
	_initial = {"initialized": false, "failure_class": "initialization_unqualified",
		"clock_samples_usec": samples, "source_fixture_sha256": _hash_file("res://tests/fixtures/persistence_thread_affinity_fixture.gd"),
		"loaded_addon": _mapped_addon()}
	if not MODES.has(mode) or _main_owner != OS.get_main_thread_id() or _started:
		return _initial.duplicate(true)
	var positive_clock_step: bool = false
	for index: int in range(1, samples.size()):
		positive_clock_step = positive_clock_step or samples[index] > samples[index - 1]
	if not positive_clock_step or _initial["source_fixture_sha256"].length() != 64 or not _initial["loaded_addon"]["selected_mode"] in ["debug", "release"] or _initial["loaded_addon"]["mapped_member_sha256"].length() != 64:
		return _initial.duplicate(true)
	if owned_directory != ProjectSettings.globalize_path("user://affinity-1444-" + mode):
		return _initial.duplicate(true)
	if DirAccess.dir_exists_absolute(owned_directory) or DirAccess.make_dir_absolute(owned_directory) != OK:
		return _initial.duplicate(true)
	_state_created = true
	var span: Dictionary = _begin("sync.mailbox.new", "mutex.new", "init", "none", "main", 0, _main_owner, 1)
	# AFFINITY_SITE sync.mailbox.new mutex.new
	_mailbox = Mutex.new()
	_end(span, _main_spans, 0, "ok")
	var identity: Dictionary = _begin("sync.mailbox.identity", "object.get_instance_id", "init", "none", "main", 0, _main_owner, 1)
	# AFFINITY_SITE sync.mailbox.identity object.get_instance_id
	_mailbox_id = _mailbox.get_instance_id()
	_end(identity, _main_spans, _mailbox_id, "observed")
	span["object_end"] = _mailbox_id
	span = _begin("sync.control.new", "mutex.new", "init", "none", "main", 0, _main_owner, 1)
	# AFFINITY_SITE sync.control.new mutex.new
	_control = Mutex.new()
	_end(span, _main_spans, 0, "ok")
	identity = _begin("sync.control.identity", "object.get_instance_id", "init", "none", "main", 0, _main_owner, 1)
	# AFFINITY_SITE sync.control.identity object.get_instance_id
	_control_id = _control.get_instance_id()
	_end(identity, _main_spans, _control_id, "observed")
	span["object_end"] = _control_id
	span = _begin("sync.thread.new", "thread.new", "init", "none", "main", 0, _main_owner, 1)
	# AFFINITY_SITE sync.thread.new thread.new
	_thread = Thread.new()
	_end(span, _main_spans, 0, "ok")
	identity = _begin("sync.thread.identity", "object.get_instance_id", "init", "none", "main", 0, _main_owner, 1)
	# AFFINITY_SITE sync.thread.identity object.get_instance_id
	_thread_id = _thread.get_instance_id()
	_end(identity, _main_spans, _thread_id, "observed")
	span["object_end"] = _thread_id
	span = _begin("sync.thread.start", "thread.start", "init", "none", "main", _thread_id, _main_owner, 1)
	# AFFINITY_SITE sync.thread.start thread.start
	var start_error: Error = _thread.start(_worker_main)
	_end(span, _main_spans, _thread_id, "ok" if start_error == OK else "failed")
	_started = start_error == OK
	_initial["initialized"] = _started
	_initial["failure_class"] = "none" if _started else "thread_start_failed"
	return _initial.duplicate(true)


func try_submit(request_id: String) -> Dictionary:
	if _window_begin == 0:
		_window_begin = Time.get_ticks_usec()
	if not _started or _submitted or request_id != "affinity-1444":
		return {"state": "rejected"}
	if not _main_mailbox_try("request"):
		return {"state": "not_submitted"}
	var ready: bool = _ready
	if ready:
		_requested = true
		_submitted = true
	_main_mailbox_unlock("request")
	if not ready:
		return {"state": "not_submitted"}
	if _mode == "main_sqlite_control":
		_main_lifecycle = _owner_lifecycle(_directory.path_join("main-control.db"), _main_owner, "main_control")
	if _mode == "main_wait_control":
		_run_main_wait()
	return {"state": "submitted"}


func poll_once() -> Dictionary:
	if not _started:
		return {"state": "failed"}
	var phase: String = "init" if _window_begin == 0 else "request"
	if not _main_mailbox_try(phase):
		return {"state": "pending"}
	var ready: bool = _ready
	_worker_owner = _completion.get("worker_caller", _worker_owner)
	if _completion_ready and not _consumed:
		_completion = _completion.duplicate(true)
		_consumed = _closed(_completion)
	_main_mailbox_unlock(phase)
	if _consumed and not _thread_alive("request"):
		_termination_tick = Time.get_ticks_usec()
		_window_end = Time.get_ticks_usec()
		return {"state": "complete"}
	if ready and not _submitted:
		_initialization_end = Time.get_ticks_usec()
		return {"state": "ready"}
	return {"state": "pending"}


func finalize_completed() -> Dictionary:
	var teardown_begin: int = Time.get_ticks_usec()
	var result: Dictionary = {"mode": _mode, "status": "unqualified", "failure_class": "unfinished_owner",
		"main_caller": _main_owner, "worker_caller": _worker_owner,
		"window_begin_usec": _window_begin, "window_end_usec": _window_end,
		"initialization_begin_usec": _initialization_begin, "initialization_end_usec": _initialization_end,
		"termination_observed_usec": _termination_tick, "worker_return_usec": 0, "completion_published_usec": 0, "teardown_begin_usec": teardown_begin, "teardown_end_usec": 0,
		"submitted_once": _submitted, "result_consumed": _consumed, "worker_terminated": false, "worker_joined": false,
		"owned_state_removed": false, "lifecycles": [], "spans": [], "wait": {}}
	if not _started:
		_release_sync()
		result["owned_state_removed"] = _remove_owned_state() if _state_created else true
		result["spans"] = _main_spans.duplicate(true)
		result["teardown_end_usec"] = Time.get_ticks_usec()
		return result
	if _window_end == 0 or _thread_alive("teardown"):
		result["teardown_end_usec"] = Time.get_ticks_usec()
		return result
	result["worker_terminated"] = true
	var span: Dictionary = _begin("sync.thread.join", "thread.wait_to_finish", "teardown", "none", "main", _thread_id, _main_owner, 1)
	# AFFINITY_SITE sync.thread.join thread.wait_to_finish
	var returned: Variant = _thread.wait_to_finish()
	_end(span, _main_spans, _thread_id, "ok")
	result["worker_joined"] = true
	var worker: Dictionary = {}
	if typeof(returned) == TYPE_DICTIONARY and _closed(returned) and JSON.stringify(returned).to_utf8_buffer().size() <= MAX_THREAD_RETURN_BYTES:
		worker = returned
	if not worker.is_empty():
		result["worker_caller"] = worker["worker_caller"]
		var summary: Dictionary = worker["lifecycle"].duplicate(true)
		summary.erase("spans")
		result["lifecycles"] = [summary]
		if not _main_lifecycle.is_empty():
			summary = _main_lifecycle.duplicate(true)
			summary.erase("spans")
			result["lifecycles"].append(summary)
		result["worker_return_usec"] = worker["worker_return_usec"]
		result["completion_published_usec"] = worker["completion_published_usec"]
		result["wait"] = worker["wait"].duplicate(true)
		result["wait"].merge(_main_wait, true)
		result["spans"] = _main_spans.duplicate(true)
		result["spans"].append_array(worker["spans"])
		if not _main_lifecycle.is_empty():
			result["spans"].append_array(_main_lifecycle["spans"])
		result["spans"].append_array(worker["lifecycle"]["spans"])
		var successful: bool = worker["lifecycle"]["success"] and worker["failure_class"] == "none"
		if not _main_lifecycle.is_empty():
			successful = successful and _main_lifecycle["success"]
		result["status"] = "complete" if successful else "failed"
		result["failure_class"] = "none" if successful else "owner_lifecycle_unqualified"
	_release_sync()
	if not worker.is_empty():
		# Rebuild after the teardown events; no owner trace aliases cross a mailbox.
		result["spans"] = _main_spans.duplicate(true)
		result["spans"].append_array(worker["spans"])
		result["spans"].append_array(worker["lifecycle"]["spans"])
		if not _main_lifecycle.is_empty():
			result["spans"].append_array(_main_lifecycle["spans"])
	var native_custody: bool = not worker.is_empty() and _native_cleanup_known(worker["lifecycle"])
	if not _main_lifecycle.is_empty():
		native_custody = native_custody and _native_cleanup_known(_main_lifecycle)
	result["owned_state_removed"] = native_custody and _remove_owned_state()
	result["teardown_end_usec"] = Time.get_ticks_usec()
	if not result["owned_state_removed"] or result["spans"].size() > MAX_SPANS or not _closed(result):
		result["status"] = "unqualified"
		result["failure_class"] = "teardown_or_trace_unqualified"
	return result


func _release_sync() -> void:
	if _thread != null:
		var span: Dictionary = _begin("sync.thread.release", "thread.release", "teardown", "none", "main", _thread_id, _main_owner, 1)
		# AFFINITY_SITE sync.thread.release thread.release
		_thread = null
		_end(span, _main_spans, _thread_id, "released")
	if _mailbox != null:
		var span: Dictionary = _begin("sync.mailbox.release", "mutex.release", "teardown", "none", "main", _mailbox_id, _main_owner, 1)
		# AFFINITY_SITE sync.mailbox.release mutex.release
		_mailbox = null
		_end(span, _main_spans, _mailbox_id, "released")
	if _control != null:
		var span: Dictionary = _begin("sync.control.release", "mutex.release", "teardown", "none", "main", _control_id, _main_owner, 1)
		# AFFINITY_SITE sync.control.release mutex.release
		_control = null
		_end(span, _main_spans, _control_id, "released")


func _worker_main() -> Dictionary:
	var owner: int = OS.get_thread_caller_id()
	var events: Array[Dictionary] = []
	var wait: Dictionary = {"armed_attempt": 0, "observation_attempt": 0,
		"state_before_sleeping": false, "state_after_sleeping": false, "futex_class": NOT_OBSERVED,
		"observation_begin_usec": 0, "observation_end_usec": 0, "worker_unlock_begin_usec": 0,
		"source_attribution": "INFERENCE", "exact_target_identity": NOT_OBSERVED, "continuous_wait_duration": NOT_OBSERVED}
	var held: bool = _mode == "main_wait_control"
	if held:
		var span: Dictionary = _begin("sync.control.worker_lock", "mutex.lock", "init", "none", "worker", _control_id, owner, 1)
		# AFFINITY_SITE sync.control.worker_lock mutex.lock
		_control.lock()
		_end(span, events, _control_id, "ok")
	_worker_mailbox_lock(events, "init", owner)
	_ready = true
	_completion = {"worker_caller": owner}
	_worker_mailbox_unlock(events, "init", owner)
	var deadline: int = Time.get_ticks_usec() + WORKER_LIMIT_US
	var requested: bool = false
	while not requested and Time.get_ticks_usec() < deadline:
		_worker_mailbox_lock(events, "init", owner)
		requested = _requested
		_worker_mailbox_unlock(events, "init", owner)
		if not requested:
			_worker_delay(events, "init", owner)
	var failure: String = "none" if requested else "request_not_observed"
	if held:
		if requested:
			wait = _observe_main_wait(events, owner)
			if wait["futex_class"] != "APPROVED_FUTEX_WAIT":
				failure = "contention_observation_missing"
		var span: Dictionary = _begin("sync.control.worker_unlock", "mutex.unlock", "request" if requested else "init", "none", "worker", _control_id, owner, 1)
		wait["worker_unlock_begin_usec"] = span["begin_usec"]
		# AFFINITY_SITE sync.control.worker_unlock mutex.unlock
		_control.unlock()
		_end(span, events, _control_id, "ok")
	var lifecycle: Dictionary = {"role": "worker", "success": false, "cycles": [], "spans": []}
	if requested:
		lifecycle = _owner_lifecycle(_directory.path_join("affinity.db"), owner, "worker")
		if not lifecycle["success"]:
			failure = "owner_lifecycle_unqualified"
	var publication: Dictionary = {"worker_caller": owner, "failure_class": failure, "native_released": lifecycle["success"], "cycles": lifecycle["cycles"].duplicate(true)}
	_worker_mailbox_lock(events, "request" if requested else "init", owner)
	_completion = publication.duplicate(true)
	_completion_ready = _closed(publication) and JSON.stringify(publication).to_utf8_buffer().size() <= MAX_MESSAGE_BYTES
	var publication_tick: int = Time.get_ticks_usec()
	_worker_mailbox_unlock(events, "request" if requested else "init", owner)
	var result: Dictionary = {"worker_caller": owner, "failure_class": failure, "lifecycle": lifecycle, "wait": wait, "spans": events, "completion_published_usec": publication_tick, "worker_return_usec": 0}
	if events.size() + lifecycle["spans"].size() > MAX_SPANS or not _closed(result) or JSON.stringify(result).to_utf8_buffer().size() > MAX_THREAD_RETURN_BYTES:
		return {}
	result["worker_return_usec"] = Time.get_ticks_usec()
	return result


func _owner_lifecycle(path: String, owner: int, role: String) -> Dictionary:
	var result: Dictionary = {"role": role, "success": true, "cycles": [], "spans": []}
	var events: Array[Dictionary] = []
	var cycles: Array[String] = ["first", "reopen"] if role == "worker" else ["first"]
	for cycle: String in cycles:
		var value: Dictionary = _native_cycle(path, owner, role, cycle, events)
		result["cycles"].append(value)
		result["success"] = result["success"] and value["success"]
		if not value["success"]:
			break
	result["spans"] = events
	result["success"] = result["success"] and events.size() <= MAX_SPANS
	return result


func _native_cycle(path: String, owner: int, role: String, cycle: String, events: Array[Dictionary]) -> Dictionary:
	var data: Dictionary = {"cycle": cycle, "success": false, "journal_mode_rows": [], "foreign_keys_rows": [], "user_version_rows": [],
		"committed_rows": [], "rolled_back_rows": [], "control_rows": [], "autocommit_values": [], "release": {}}
	var span: Dictionary = _begin("native.new", "sqlite.new", "request", cycle, role, 0, owner, 1)
	# AFFINITY_SITE native.new sqlite.new
	var database: SQLite = SQLite.new()
	_end(span, events, 0, "ok" if database != null else "failed")
	if database == null:
		return data
	var identity: Dictionary = _begin("native.identity", "object.get_instance_id", "request", cycle, role, 0, owner, 1)
	# AFFINITY_SITE native.identity object.get_instance_id
	var object_id: int = database.get_instance_id()
	_end(identity, events, object_id, "observed")
	span["object_end"] = object_id
	span = _begin("native.path", "sqlite.path.set", "request", cycle, role, object_id, owner, 1)
	# AFFINITY_SITE native.path sqlite.path.set
	database.path = path
	_end(span, events, object_id, "ok")
	span = _begin("native.foreign_keys", "sqlite.foreign_keys.set", "request", cycle, role, object_id, owner, 1)
	# AFFINITY_SITE native.foreign_keys sqlite.foreign_keys.set
	database.foreign_keys = true
	_end(span, events, object_id, "ok")
	span = _begin("native.read_only", "sqlite.read_only.set", "request", cycle, role, object_id, owner, 1)
	# AFFINITY_SITE native.read_only sqlite.read_only.set
	database.read_only = false
	_end(span, events, object_id, "ok")
	span = _begin("native.verbosity", "sqlite.verbosity_level.set", "request", cycle, role, object_id, owner, 1)
	# AFFINITY_SITE native.verbosity sqlite.verbosity_level.set
	database.verbosity_level = SQLite.QUIET
	_end(span, events, object_id, "ok")
	span = _begin("native.open", "sqlite.open_db", "request", cycle, role, object_id, owner, 1)
	# AFFINITY_SITE native.open sqlite.open_db
	var success: bool = database.open_db()
	_end(span, events, object_id, "ok" if success else "failed")
	if success:
		for action: Dictionary in _actions(cycle):
			if not success:
				break
			if action["kind"] == "autocommit":
				var actual: int = _autocommit(database, events, owner, object_id, role, cycle, action["ordinal"])
				data["autocommit_values"].append(actual)
				success = actual == action["expected"]
			else:
				success = _query(database, action, events, owner, object_id, role, cycle)
				if success and not action["result"].is_empty():
					data[action["result"]] = _rows(database, action["column"], events, owner, object_id, role, cycle, action["row_ordinal"])
		if success and role == "main_control" and cycle == "first":
			for index: int in range(32):
				var action: Dictionary = {"kind": "bound", "sql": "SELECT ? AS value;", "bindings": [7], "ordinal": index + 5}
				var queried: bool = _query(database, action, events, owner, object_id, role, cycle)
				var rows: Array = _rows(database, "value", events, owner, object_id, role, cycle, index + 6) if queried else []
				data["control_rows"].append(rows)
				success = success and queried and rows == [[7]]
				if not success:
					break
		success = success and data["journal_mode_rows"] == [["wal"]] and data["foreign_keys_rows"] == [[1]] and data["user_version_rows"] == [[1444]]
		success = success and data["committed_rows"] == [[7]] and data["rolled_back_rows"] == []
	# Owner-local epilogue runs after every encountered native failure; no main fallback.
	span = _begin("native.close", "sqlite.close_db", "request", cycle, role, object_id, owner, 1)
	# AFFINITY_SITE native.close sqlite.close_db
	var closed: bool = database.close_db()
	_end(span, events, object_id, "ok" if closed else "failed")
	span = _begin("native.weakref", "weakref.new", "request", cycle, role, object_id, owner, 1)
	# AFFINITY_SITE native.weakref weakref.new
	var native_weak: WeakRef = weakref(database)
	_end(span, events, object_id, "observed")
	span = _begin("native.release", "sqlite.release", "request", cycle, role, object_id, owner, 1)
	# AFFINITY_SITE native.release sqlite.release
	database = null
	_end(span, events, object_id, "released")
	span = _begin("native.weakref_check", "weakref.get_ref", "request", cycle, role, object_id, owner, 1)
	# AFFINITY_SITE native.weakref_check weakref.get_ref
	var released: bool = native_weak.get_ref() == null
	_end(span, events, object_id, "null" if released else "retained")
	data["release"] = {"object_id": object_id, "weakref_null": released, "observed_caller": span["caller_end"], "tick_usec": span["end_usec"]}
	data["success"] = success and closed and released
	return data


func _actions(cycle: String) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	if cycle == "first":
		actions = [
			{"kind": "query", "sql": "PRAGMA journal_mode = WAL;", "ordinal": 1, "result": "journal_mode_rows", "column": "journal_mode", "row_ordinal": 1},
			{"kind": "query", "sql": "PRAGMA foreign_keys = ON;", "ordinal": 2, "result": ""},
			{"kind": "query", "sql": "PRAGMA foreign_keys;", "ordinal": 3, "result": "foreign_keys_rows", "column": "foreign_keys", "row_ordinal": 2},
			{"kind": "query", "sql": "PRAGMA user_version = 1444;", "ordinal": 4, "result": ""},
			{"kind": "query", "sql": "PRAGMA user_version;", "ordinal": 5, "result": "user_version_rows", "column": "user_version", "row_ordinal": 3},
			{"kind": "query", "sql": "CREATE TABLE affinity_fixture(id TEXT PRIMARY KEY, value INTEGER NOT NULL);", "ordinal": 6, "result": ""},
			{"kind": "autocommit", "ordinal": 1, "expected": 1},
			{"kind": "query", "sql": "BEGIN;", "ordinal": 7, "result": ""},
			{"kind": "autocommit", "ordinal": 2, "expected": 0},
			{"kind": "bound", "sql": "INSERT INTO affinity_fixture(id, value) VALUES (?, ?);", "bindings": ["committed", 7], "ordinal": 1, "result": ""},
			{"kind": "query", "sql": "COMMIT;", "ordinal": 8, "result": ""},
			{"kind": "autocommit", "ordinal": 3, "expected": 1},
			{"kind": "query", "sql": "BEGIN;", "ordinal": 9, "result": ""},
			{"kind": "autocommit", "ordinal": 4, "expected": 0},
			{"kind": "bound", "sql": "INSERT INTO affinity_fixture(id, value) VALUES (?, ?);", "bindings": ["rolled_back", 11], "ordinal": 2, "result": ""},
			{"kind": "query", "sql": "ROLLBACK;", "ordinal": 10, "result": ""},
			{"kind": "autocommit", "ordinal": 5, "expected": 1},
			{"kind": "bound", "sql": "SELECT value FROM affinity_fixture WHERE id = ?;", "bindings": ["committed"], "ordinal": 3, "result": "committed_rows", "column": "value", "row_ordinal": 4},
			{"kind": "bound", "sql": "SELECT value FROM affinity_fixture WHERE id = ?;", "bindings": ["rolled_back"], "ordinal": 4, "result": "rolled_back_rows", "column": "value", "row_ordinal": 5},
		]
	else:
		actions = [
			{"kind": "query", "sql": "PRAGMA journal_mode;", "ordinal": 1, "result": "journal_mode_rows", "column": "journal_mode", "row_ordinal": 1},
			{"kind": "query", "sql": "PRAGMA foreign_keys;", "ordinal": 2, "result": "foreign_keys_rows", "column": "foreign_keys", "row_ordinal": 2},
			{"kind": "query", "sql": "PRAGMA user_version;", "ordinal": 3, "result": "user_version_rows", "column": "user_version", "row_ordinal": 3},
			{"kind": "autocommit", "ordinal": 1, "expected": 1},
			{"kind": "bound", "sql": "SELECT value FROM affinity_fixture WHERE id = ?;", "bindings": ["committed"], "ordinal": 1, "result": "committed_rows", "column": "value", "row_ordinal": 4},
			{"kind": "bound", "sql": "SELECT value FROM affinity_fixture WHERE id = ?;", "bindings": ["rolled_back"], "ordinal": 2, "result": "rolled_back_rows", "column": "value", "row_ordinal": 5},
		]
	return actions


func _query(database: SQLite, action: Dictionary, events: Array[Dictionary], owner: int, object_id: int, role: String, cycle: String) -> bool:
	var success: bool = false
	var span: Dictionary
	if action["kind"] == "bound":
		span = _begin("native.bound_query", "sqlite.query_with_bindings", "request", cycle, role, object_id, owner, action["ordinal"])
		# AFFINITY_SITE native.bound_query sqlite.query_with_bindings
		success = database.query_with_bindings(action["sql"], action["bindings"])
	else:
		span = _begin("native.query", "sqlite.query", "request", cycle, role, object_id, owner, action["ordinal"])
		# AFFINITY_SITE native.query sqlite.query
		success = database.query(action["sql"])
	_end(span, events, object_id, "ok" if success else "failed")
	return success


func _rows(database: SQLite, column: String, events: Array[Dictionary], owner: int, object_id: int, role: String, cycle: String, ordinal: int) -> Array:
	var span: Dictionary = _begin("native.rows", "sqlite.query_result.get", "request", cycle, role, object_id, owner, ordinal)
	# AFFINITY_SITE native.rows sqlite.query_result.get
	var raw: Array = database.query_result
	_end(span, events, object_id, "observed")
	var rows: Array = []
	if raw.size() > 1:
		return [["UNQUALIFIED"]]
	for row: Dictionary in raw:
		if not row.has(column) or (typeof(row[column]) != TYPE_INT and typeof(row[column]) != TYPE_STRING):
			return [["UNQUALIFIED"]]
		rows.append([row[column]])
	return rows


func _autocommit(database: SQLite, events: Array[Dictionary], owner: int, object_id: int, role: String, cycle: String, ordinal: int) -> int:
	var span: Dictionary = _begin("native.autocommit", "sqlite.get_autocommit", "request", cycle, role, object_id, owner, ordinal)
	# AFFINITY_SITE native.autocommit sqlite.get_autocommit
	var value: int = database.get_autocommit()
	_end(span, events, object_id, "observed")
	return value


func _run_main_wait() -> void:
	var attempt: Dictionary = _begin("sync.control.main_try", "mutex.try_lock", "request", "none", "main", _control_id, _main_owner, 1)
	# AFFINITY_SITE sync.control.main_try mutex.try_lock
	var acquired: bool = _control.try_lock()
	_end(attempt, _main_spans, _control_id, "acquired" if acquired else "busy")
	_main_wait = {"failed_try_lock": not acquired, "main_lock_begin_usec": 0, "main_lock_end_usec": 0}
	if acquired:
		var release: Dictionary = _begin("sync.control.main_try_unlock", "mutex.unlock", "request", "none", "main", _control_id, _main_owner, 1)
		# AFFINITY_SITE sync.control.main_try_unlock mutex.unlock
		_control.unlock()
		_end(release, _main_spans, _control_id, "ok")
		return
	# All dictionary/scalar/caller allocation occurs BEFORE the direct interval.
	var lock_span: Dictionary = _begin("sync.control.main_lock", "mutex.lock", "request", "none", "main", _control_id, _main_owner, 1)
	var lock_begin: int = 0
	var lock_end: int = 0
	lock_begin = Time.get_ticks_usec()
	# AFFINITY_SITE sync.control.main_lock mutex.lock
	_control.lock()
	lock_end = Time.get_ticks_usec()
	lock_span["begin_usec"] = lock_begin
	lock_span["end_usec"] = lock_end
	lock_span["caller_end"] = OS.get_thread_caller_id()
	lock_span["object_end"] = _control_id
	lock_span["outcome"] = "ok"
	_append(_main_spans, lock_span)
	_main_wait["main_lock_begin_usec"] = lock_begin
	_main_wait["main_lock_end_usec"] = lock_end
	var release: Dictionary = _begin("sync.control.main_unlock", "mutex.unlock", "request", "none", "main", _control_id, _main_owner, 1)
	# AFFINITY_SITE sync.control.main_unlock mutex.unlock
	_control.unlock()
	_end(release, _main_spans, _control_id, "ok")


func _observe_main_wait(events: Array[Dictionary], owner: int) -> Dictionary:
	var result: Dictionary = {"armed_attempt": 1, "observation_attempt": 0,
		"state_before_sleeping": false, "state_after_sleeping": false, "futex_class": NOT_OBSERVED,
		"observation_begin_usec": 0, "observation_end_usec": 0, "worker_unlock_begin_usec": 0,
		"source_attribution": "INFERENCE", "exact_target_identity": NOT_OBSERVED, "continuous_wait_duration": NOT_OBSERVED}
	var task: String = "/proc/self/task/" + str(OS.get_process_id())
	var deadline: int = Time.get_ticks_usec() + WAIT_HOLD_US
	while Time.get_ticks_usec() < deadline:
		var begin: int = Time.get_ticks_usec()
		var before: String = _read_state(task.path_join("stat"))
		var symbol: String = _read_prefix(task.path_join("wchan"), 128)
		var after: String = _read_state(task.path_join("stat"))
		var end: int = Time.get_ticks_usec()
		if before == "S" and after == "S" and symbol == "futex_wait_queue":
			result["observation_attempt"] = 1
			result["state_before_sleeping"] = true
			result["state_after_sleeping"] = true
			result["futex_class"] = "APPROVED_FUTEX_WAIT"
			result["observation_begin_usec"] = begin
			result["observation_end_usec"] = end
			break
		if before.is_empty() or after.is_empty() or symbol.is_empty():
			break
		_worker_delay(events, "request", owner)
	return result


func _main_mailbox_try(phase: String) -> bool:
	var span: Dictionary = _begin("sync.mailbox.main_try", "mutex.try_lock", phase, "none", "main", _mailbox_id, _main_owner, _main_spans.size() + 1)
	# AFFINITY_SITE sync.mailbox.main_try mutex.try_lock
	var acquired: bool = _mailbox.try_lock()
	_end(span, _main_spans, _mailbox_id, "acquired" if acquired else "busy")
	return acquired


func _main_mailbox_unlock(phase: String) -> void:
	var span: Dictionary = _begin("sync.mailbox.main_unlock", "mutex.unlock", phase, "none", "main", _mailbox_id, _main_owner, _main_spans.size() + 1)
	# AFFINITY_SITE sync.mailbox.main_unlock mutex.unlock
	_mailbox.unlock()
	_end(span, _main_spans, _mailbox_id, "ok")


func _worker_mailbox_lock(events: Array[Dictionary], phase: String, owner: int) -> void:
	var span: Dictionary = _begin("sync.mailbox.worker_lock", "mutex.lock", phase, "none", "worker", _mailbox_id, owner, events.size() + 1)
	# AFFINITY_SITE sync.mailbox.worker_lock mutex.lock
	_mailbox.lock()
	_end(span, events, _mailbox_id, "ok")


func _worker_mailbox_unlock(events: Array[Dictionary], phase: String, owner: int) -> void:
	var span: Dictionary = _begin("sync.mailbox.worker_unlock", "mutex.unlock", phase, "none", "worker", _mailbox_id, owner, events.size() + 1)
	# AFFINITY_SITE sync.mailbox.worker_unlock mutex.unlock
	_mailbox.unlock()
	_end(span, events, _mailbox_id, "ok")


func _worker_delay(events: Array[Dictionary], phase: String, owner: int) -> void:
	var span: Dictionary = _begin("sync.worker_delay", "os.delay_usec", phase, "none", "worker", 0, owner, events.size() + 1)
	# AFFINITY_SITE sync.worker_delay os.delay_usec
	OS.delay_usec(4000 if phase == "init" else 1000)
	_end(span, events, 0, "ok")


func _thread_alive(phase: String) -> bool:
	var span: Dictionary = _begin("sync.thread.alive", "thread.is_alive", phase, "none", "main", _thread_id, _main_owner, _main_spans.size() + 1)
	# AFFINITY_SITE sync.thread.alive thread.is_alive
	var alive: bool = _thread.is_alive()
	_end(span, _main_spans, _thread_id, "alive" if alive else "terminated")
	return alive


func _begin(site: String, operation: String, phase: String, cycle: String, role: String, object_id: int, owner: int, ordinal: int) -> Dictionary:
	var result: Dictionary = {"site": site, "operation": operation, "phase": phase, "cycle": cycle, "role": role, "ordinal": ordinal,
		"caller_begin": OS.get_thread_caller_id(), "caller_end": 0, "owner": owner, "object_begin": object_id, "object_end": object_id,
		"begin_usec": 0, "end_usec": 0, "outcome": "pending"}
	result["begin_usec"] = Time.get_ticks_usec()
	return result


func _end(span: Dictionary, events: Array[Dictionary], object_id: int, outcome: String) -> void:
	span["end_usec"] = Time.get_ticks_usec()
	span["caller_end"] = OS.get_thread_caller_id()
	span["object_end"] = object_id
	span["outcome"] = outcome
	_append(events, span)


func _append(events: Array[Dictionary], span: Dictionary) -> void:
	if events.size() < MAX_SPANS:
		events.append(span)
	elif events.size() == MAX_SPANS:
		events.append({"site": "trace_overflow"})


func _closed(value: Variant, depth: int = 0) -> bool:
	if depth > 10:
		return false
	match typeof(value):
		TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return typeof(value) != TYPE_STRING or value.length() <= 128
		TYPE_ARRAY:
			if value.size() > MAX_SPANS:
				return false
			for child: Variant in value:
				if not _closed(child, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			if value.size() > 64:
				return false
			for key: Variant in value:
				if typeof(key) != TYPE_STRING or key.length() > 128 or not _closed(value[key], depth + 1):
					return false
			return true
	return false


func _hash_file(path: String) -> String:
	var stream: FileAccess = FileAccess.open(path, FileAccess.READ)
	if stream == null:
		return NOT_OBSERVED
	var context: HashingContext = HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		stream.close()
		return NOT_OBSERVED
	var total: int = 0
	while not stream.eof_reached():
		var bytes: PackedByteArray = stream.get_buffer(65536)
		total += bytes.size()
		if total > 4194304 or (bytes.is_empty() and not stream.eof_reached()):
			stream.close()
			return NOT_OBSERVED
		if not bytes.is_empty() and context.update(bytes) != OK:
			stream.close()
			return NOT_OBSERVED
	stream.close()
	return context.finish().hex_encode()


func _mapped_addon() -> Dictionary:
	var result: Dictionary = {"selected_mode": NOT_OBSERVED, "mapped_member_sha256": NOT_OBSERVED}
	var debug: String = ProjectSettings.globalize_path("res://addons/godot-sqlite/bin/libgdsqlite.linux.template_debug.x86_64.so")
	var release: String = ProjectSettings.globalize_path("res://addons/godot-sqlite/bin/libgdsqlite.linux.template_release.x86_64.so")
	var stream: FileAccess = FileAccess.open("/proc/self/maps", FileAccess.READ)
	if stream == null:
		return result
	var line: String = ""
	var total: int = 0
	var debug_match: bool = false
	var release_match: bool = false
	var valid: bool = true
	while not stream.eof_reached() and valid:
		var byte: int = stream.get_8()
		if stream.eof_reached():
			break
		total += 1
		if total > PROC_TOTAL_BYTES or line.length() > PROC_LINE_BYTES:
			valid = false
		elif byte == 10:
			debug_match = debug_match or line.ends_with(" " + debug)
			release_match = release_match or line.ends_with(" " + release)
			line = ""
		elif byte >= 32 and byte <= 126:
			line += String.chr(byte)
		else:
			valid = false
	stream.close()
	if valid:
		debug_match = debug_match or line.ends_with(" " + debug)
		release_match = release_match or line.ends_with(" " + release)
	if valid and debug_match != release_match:
		result["selected_mode"] = "debug" if debug_match else "release"
		result["mapped_member_sha256"] = _hash_file(debug if debug_match else release)
	return result


func _read_prefix(path: String, maximum: int) -> String:
	var stream: FileAccess = FileAccess.open(path, FileAccess.READ)
	if stream == null:
		return ""
	var text: String = ""
	while not stream.eof_reached() and text.length() <= maximum:
		var byte: int = stream.get_8()
		if stream.eof_reached():
			break
		if byte == 10:
			break
		if byte < 32 or byte > 126:
			text = ""
			break
		text += String.chr(byte)
	stream.close()
	return text if text.length() <= maximum else ""


func _read_state(path: String) -> String:
	var prefix: String = _read_prefix(path, 4096)
	var boundary: int = prefix.rfind(") ")
	if boundary < 0 or prefix.length() < boundary + 4 or prefix.substr(boundary + 3, 1) != " " or not prefix.begins_with(str(OS.get_process_id()) + " ("):
		return ""
	return prefix.substr(boundary + 2, 1)


func _native_cleanup_known(lifecycle: Dictionary) -> bool:
	if lifecycle["cycles"].is_empty():
		return false
	for cycle: Dictionary in lifecycle["cycles"]:
		if not cycle["release"].get("weakref_null", false):
			return false
		var closed: bool = false
		for span: Dictionary in lifecycle["spans"]:
			if span.get("site", "") == "native.close" and span["cycle"] == cycle["cycle"]:
				closed = span["outcome"] == "ok" and span["object_end"] == cycle["release"]["object_id"]
		if not closed:
			return false
	return true


func _remove_owned_state() -> bool:
	var parent: DirAccess = DirAccess.open(_directory.get_base_dir())
	if parent == null or parent.is_link(_directory.get_file()):
		return false
	var directory: DirAccess = DirAccess.open(_directory)
	if directory == null:
		return false
	var allowed: Array[String] = ["affinity.db", "affinity.db-wal", "affinity.db-shm", "affinity.db-journal", "main-control.db", "main-control.db-wal", "main-control.db-shm", "main-control.db-journal"]
	for entry: String in directory.get_files():
		if not allowed.has(entry) or directory.is_link(entry):
			return false
	if not directory.get_directories().is_empty():
		return false
	for entry: String in directory.get_files():
		if directory.remove(entry) != OK:
			return false
	return DirAccess.remove_absolute(_directory) == OK
