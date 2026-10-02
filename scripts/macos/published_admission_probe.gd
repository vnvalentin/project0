extends SceneTree
## External probe for the exact audited published PCK; its actual autoloads run.
## Real pre-auth ENet/version/admission path only. No credentials or assertions.
## The coordinator disables all native logs and discards stdout/stderr before boot.
## Only literal enums, bounded counts, booleans and a validated version reach JSON.

const TARGET_HOST: String = "192.69.180.236"
const TARGET_PORT: int = 9999
const CLIENT_VERSION: String = "0.14.20"
const RUNTIME_BUDGET_MS: int = 45000
const MAX_EVENTS: int = 64
const KNOWN_REJECTIONS: Array[String] = ["CLIENT_OUTDATED", "MALFORMED", "SERVER_MISCONFIGURED", "UNSUPPORTED"]

class AdmissionChecksumLogger:
	extends Logger

	const PREFIX: String = "The rpc node checksum failed."
	const ENGINE_FILES: Array[String] = [
		"modules/multiplayer/scene_cache_interface.cpp",
		"modules/multiplayer/scene_rpc_interface.cpp",
	]
	var _mutex: Mutex = Mutex.new()
	var _count: int = 0

	func is_checksum_failure(file: String, code: String, rationale: String) -> bool:
		var normalized: String = file.replace("\\", "/").trim_prefix("./")
		var engine_source: bool = false
		for expected: String in ENGINE_FILES:
			if normalized == expected or normalized.ends_with("/" + expected):
				engine_source = true
		return engine_source and (code.begins_with(PREFIX) or rationale.begins_with(PREFIX))

	func _log_error(_function: String, file: String, _line: int, code: String, rationale: String, _editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if not is_checksum_failure(file, code, rationale):
			return
		_mutex.lock()
		_count = mini(_count + 1, 64)
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func failure_count() -> int:
		_mutex.lock()
		var count: int = _count
		_mutex.unlock()
		return count

	func reset() -> void:
		_mutex.lock()
		_count = 0
		_mutex.unlock()

var _evidence_path: String = ""
var _expected_user_data: String = ""
var _expected_inert_scene: String = ""
var _started_ms: int = 0
var _finished: bool = false
var _network: Node
var _checksum_logger: AdmissionChecksumLogger
var _logger_registered: bool = false
var _result: Dictionary = {
	"schema_version": 1,
	"probe": "macos-server-admission",
	"passed": false,
	"target": {"host": TARGET_HOST, "port": TARGET_PORT},
	"client_version": CLIENT_VERSION,
	"user_data_isolated": false,
	"startup_scene_inert": false,
	"connected": false,
	"admitted": false,
	"terminal_stage": "setup",
	"timeout_ms": 20000,
	"elapsed_msec": 0,
	"phase_durations_ms": {"connect": 0, "admission": 0},
	"connection_events": [],
	"events_truncated": false,
	"version_rejection": {"received": false, "outcome": "", "required_version": ""},
	"assertion_sent": false,
	"authentication_attempted": false,
	"session_attempted": false,
	"world_entry_attempted": false,
	"cleanup_disconnect": false,
	"rpc_checksum_failed": false,
	"rpc_checksum_failure_count": 0,
	"checksum_classifier_selfcheck_passed": false,
	"failures": [],
}


func _initialize() -> void:
	_started_ms = Time.get_ticks_msec()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--evidence="):
			_evidence_path = argument.trim_prefix("--evidence=")
		elif argument.begins_with("--expected-user-data="):
			_expected_user_data = argument.trim_prefix("--expected-user-data=")
		elif argument.begins_with("--expected-inert-scene="):
			_expected_inert_scene = argument.trim_prefix("--expected-inert-scene=")
	if not _evidence_path.is_absolute_path() or FileAccess.file_exists(_evidence_path):
		quit(1)
		return
	_result["user_data_isolated"] = _expected_user_data.is_absolute_path() and OS.get_user_data_dir().simplify_path() == _expected_user_data.simplify_path()
	if not _result["user_data_isolated"]:
		_fail("isolation_mismatch")
		_finish("setup_failed")
		return
	call_deferred("_run")


func _process(_delta: float) -> bool:
	if not _finished and Time.get_ticks_msec() - _started_ms > RUNTIME_BUDGET_MS:
		_fail("runtime_deadline")
		_finish("runtime_deadline")
	return false


func _run() -> void:
	if _finished:
		return
	var engine: Dictionary = Engine.get_version_info()
	if OS.get_name() != "macOS" or engine["major"] != 4 or engine["minor"] != 7 or engine["patch"] != 2 or engine["status"] != "stable":
		_fail("engine_mismatch")
	var version_script: Script = load("res://shared/client_build_version.gd") as Script
	if version_script == null or version_script.get_script_constant_map().get("CLIENT_BUILD_VERSION") != CLIENT_VERSION:
		_fail("client_version_mismatch")
	_result["startup_scene_inert"] = _expected_inert_scene.is_absolute_path() and FileAccess.file_exists(_expected_inert_scene) and ProjectSettings.get_setting("application/run/main_scene", "") == _expected_inert_scene
	if not _result["startup_scene_inert"]:
		_fail("inert_scene_missing")
	for setting: String in ["debug/file_logging/enable_file_logging", "debug/settings/stdout/print_to_stdout", "debug/settings/stdout/print_to_stderr"]:
		if ProjectSettings.get_setting(setting, true) != false:
			_fail("logging_not_disabled")
	_network = root.get_node_or_null("NetworkClient")
	if _network == null:
		_fail("network_client_missing")
	else:
		var network_script: Script = _network.get_script() as Script
		if network_script == null or not _network.has_method("_handoff_await_connected") or not _network.has_method("_handoff_await_server_admission") or network_script.get_script_constant_map().get("HANDOFF_STEP_TIMEOUT_MS") != 20000:
			_fail("waiter_contract_mismatch")
	if not (_result["failures"] as Array).is_empty():
		_finish("setup_failed")
		return
	_checksum_logger = AdmissionChecksumLogger.new()
	_result["checksum_classifier_selfcheck_passed"] = _check_classifier()
	if not _result["checksum_classifier_selfcheck_passed"]:
		_fail("checksum_classifier_selfcheck_failed")
		_finish("setup_failed")
		return
	OS.add_logger(_checksum_logger)
	_logger_registered = true
	_network.connect("connection_status_changed", _on_connection_status)
	_network.connect("version_handshake_rejected", _on_version_rejection)
	_network.call("connect_to_server", TARGET_HOST, TARGET_PORT)
	var phase_started: int = Time.get_ticks_msec()
	_result["connected"] = await _network.call("_handoff_await_connected", true)
	_result["phase_durations_ms"]["connect"] = Time.get_ticks_msec() - phase_started
	if not _result["connected"]:
		if _result["version_rejection"]["received"]:
			_fail("version_rejected")
			_finish("version_rejected")
		else:
			_fail("game_connect_timeout")
			_finish("game_connect_timeout")
		return
	phase_started = Time.get_ticks_msec()
	_result["admitted"] = await _network.call("_handoff_await_server_admission")
	_result["phase_durations_ms"]["admission"] = Time.get_ticks_msec() - phase_started
	if not _result["admitted"]:
		if _result["version_rejection"]["received"]:
			_fail("version_rejected")
			_finish("version_rejected")
		else:
			_fail("server_admission_timeout")
			_finish("server_admission_timeout")
		return
	_finish("admitted")


func _check_classifier() -> bool:
	var backtraces: Array[ScriptBacktrace] = []
	var source: String = "modules/multiplayer/scene_cache_interface.cpp"
	var prefix: String = "The rpc node checksum failed."
	var positive_rationale: bool = _checksum_logger.is_checksum_failure(source, "", prefix + " Owned synthetic control.")
	_checksum_logger._log_error("owned_control", source, 0, "", prefix + " Owned synthetic control.", false, 0, backtraces)
	var one: bool = _checksum_logger.failure_count() == 1
	var positive_code: bool = _checksum_logger.is_checksum_failure("modules/multiplayer/scene_rpc_interface.cpp", prefix, "")
	var unrelated_rpc: bool = not _checksum_logger.is_checksum_failure(source, "", "Unrelated RPC failure.")
	_checksum_logger._log_error("owned_control", source, 0, "", "Unrelated RPC failure.", false, 0, backtraces)
	var marker_rejected: bool = not _checksum_logger.is_checksum_failure("res://owned-marker.gd", "", prefix)
	_checksum_logger._log_error("owned_control", "res://owned-marker.gd", 0, "", prefix, false, 0, backtraces)
	var negatives_unchanged: bool = _checksum_logger.failure_count() == 1
	for control: int in range(70):
		_checksum_logger._log_error("owned_control", source, 0, "", prefix, false, 0, backtraces)
	var capped: bool = _checksum_logger.failure_count() == 64
	_checksum_logger.reset()
	return positive_rationale and one and positive_code and unrelated_rpc and marker_rejected and negatives_unchanged and capped and _checksum_logger.failure_count() == 0


func _on_connection_status(status: String) -> void:
	if _finished:
		return
	var state: String = "unknown"
	if status == "connecting":
		state = "connecting"
	elif status.begins_with("connected"):
		state = "connected"
	elif status == "disconnected":
		state = "disconnected"
	elif status.begins_with("failed:"):
		state = "failed"
	elif status.begins_with("refused:"):
		state = "refused"
	if (_result["connection_events"] as Array).size() >= MAX_EVENTS:
		_result["events_truncated"] = true
		return
	(_result["connection_events"] as Array).append({"state": state, "elapsed_msec": Time.get_ticks_msec() - _started_ms})


func _on_version_rejection(rejection: Dictionary) -> void:
	var outcome: Variant = rejection.get("outcome")
	var bounded_outcome: String = "unknown_rejection"
	if outcome is String and outcome in KNOWN_REJECTIONS:
		bounded_outcome = outcome
	var version: Variant = rejection.get("required_version")
	var bounded_version: String = ""
	if version is String and version.length() <= 32:
		var pattern: RegEx = RegEx.new()
		pattern.compile("^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$")
		if pattern.search(version) != null:
			bounded_version = version
	_result["version_rejection"] = {"received": true, "outcome": bounded_outcome, "required_version": bounded_version}


func _fail(reason: String) -> void:
	if reason not in (_result["failures"] as Array):
		(_result["failures"] as Array).append(reason)


func _finish(stage: String) -> void:
	if _finished:
		return
	_finished = true
	if is_instance_valid(_network):
		_network.call("disconnect_from_server")
	if _logger_registered:
		OS.remove_logger(_checksum_logger)
		_logger_registered = false
	if _checksum_logger != null:
		_result["rpc_checksum_failure_count"] = _checksum_logger.failure_count()
		_result["rpc_checksum_failed"] = _result["rpc_checksum_failure_count"] > 0
		if _result["rpc_checksum_failed"]:
			_fail("rpc_checksum_failed")
	var peer: MultiplayerPeer = root.multiplayer.multiplayer_peer
	_result["cleanup_disconnect"] = peer == null or peer is OfflineMultiplayerPeer
	if current_scene != null:
		var inert_scene: Node = current_scene
		current_scene = null
		inert_scene.free()
	_result["terminal_stage"] = stage
	_result["elapsed_msec"] = Time.get_ticks_msec() - _started_ms
	_result["passed"] = stage == "admitted" and _result["admitted"] and _result["connected"] and _result["user_data_isolated"] and _result["startup_scene_inert"] and _result["cleanup_disconnect"] and _result["checksum_classifier_selfcheck_passed"] and not _result["rpc_checksum_failed"] and not _result["version_rejection"]["received"] and (_result["failures"] as Array).is_empty()
	var output: FileAccess = FileAccess.open(_evidence_path, FileAccess.WRITE)
	if output == null:
		quit(1)
		return
	output.store_string(JSON.stringify(_result, "\t"))
	output.close()
	quit(0 if _result["passed"] else 1)
