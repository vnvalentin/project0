extends GutTest

const ReadyCodec = preload("res://tests/fixtures/prediction_listener_ready.gd")
const CONSUMER: String = "res://tests/fixtures/prediction_listener_startup.py"
const READY_LABEL: String = "1450 owned listener readiness precedes client startup"
const SOURCE_FILES: Array[String] = [
	"server/server_main.gd", "tests/fixtures/prediction_listener_ready.gd",
	"tests/fixtures/prediction_listener_server.gd", "tests/fixtures/prediction_listener_startup.py",
]
const NULLABLE_BOOLEAN_FIELDS: Array[String] = [
	"held_port_owned", "child_started", "pidfd_qualified", "ready_observed", "ready_qualified",
	"listener_live", "listener_owned", "capture_qualified", "released_listener_rebound",
	"child_reaped", "resources_released", "temp_removed",
]
const BOOLEAN_FIELDS: Array[String] = [
	"source_qualified", "run_qualified", "intended_bind_failure", "unexpected_error_observed",
	"qualified_red", "qualified_green",
]


func test_owned_listener_readiness_overrides_occupied_default() -> void:
	var revision: String = OS.get_environment("M4_SOURCE_REVISION")
	var source_hashes: Dictionary = {}
	for relative: String in SOURCE_FILES:
		source_hashes[relative] = FileAccess.get_sha256("res://" + relative)
	var output: Array = []
	var project: String = ProjectSettings.globalize_path("res://").trim_suffix("/")
	var user_directory: String = ProjectSettings.globalize_path("user://").trim_suffix("/")
	var executable: String = OS.get_executable_path()
	var safe_arguments: bool = _safe_argument(project) and _safe_argument(user_directory) and _safe_argument(executable) \
		and ReadyCodec.valid_revision(revision)
	assert_true(safe_arguments, "1450 execution paths have known harmless syntax")
	if not safe_arguments:
		return
	var exit_code: int = OS.execute("/usr/bin/python3", PackedStringArray([
		"-I", "-B",
		ProjectSettings.globalize_path(CONSUMER),
		"--godot", executable,
		"--project-root", project,
		"--runtime-parent", user_directory,
		"--source-revision", revision,
		"--run-id", "1450_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()],
		"--source-hashes-base64", Marshalls.utf8_to_base64(JSON.stringify(source_hashes, "", true)),
		"--userdir-leaf", user_directory.get_file(),
	]), output, false)
	assert_true(exit_code == 0, "1450 known consumer emits a reduced result")
	if exit_code != 0:
		return
	var bytes: String = "".join(output).trim_suffix("\n")
	assert_true(bytes.to_utf8_buffer().size() <= 2048, "1450 reduced result is bounded")
	if bytes.to_utf8_buffer().size() > 2048:
		return
	var parser: JSON = JSON.new()
	var parsed: Error = parser.parse(bytes)
	assert_true(parsed == OK and typeof(parser.data) == TYPE_DICTIONARY, "1450 reduced result parses as a closed object")
	if parsed != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return
	var result: Dictionary = parser.data
	var valid: bool = _closed_report(result, bytes)
	assert_true(valid, "1450 reduced result has exact typed schema")
	if not valid:
		return
	# Only booleans/fixed enums. Source/run/port/PID/path and child text stay private.
	print("1450_LISTENER_REPORT:" + JSON.stringify(result, "", true))
	assert_true(result["ready_qualified"] == true, READY_LABEL)
	if result["ready_qualified"] != true:
		return
	assert_true(result["qualified_green"] == true, "1450 owned startup and release controls qualify")
	assert_true(result["source_qualified"] == true, "1450 actual fixture source is qualified")
	assert_true(result["listener_live"] == true and result["listener_owned"] == true, "1450 actual listener remains owned")
	assert_true(result["released_listener_rebound"] == true, "1450 listener releases before positive rebind")
	assert_true(result["child_reaped"] == true and result["temp_removed"] == true, "1450 owned process and temporary cleanup qualify")


func _safe_argument(value: String) -> bool:
	if value.is_empty() or value.length() > 4096:
		return false
	for character: String in value:
		if not "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./- ".contains(character):
			return false
	return true


func _closed_report(result: Dictionary, bytes: String) -> bool:
	if result.size() != NULLABLE_BOOLEAN_FIELDS.size() + BOOLEAN_FIELDS.size() + 4:
		return false
	if not result.has("schema_version") or result["schema_version"] != 1 \
		or (typeof(result["schema_version"]) != TYPE_INT and typeof(result["schema_version"]) != TYPE_FLOAT):
		return false
	for field: String in BOOLEAN_FIELDS:
		if not result.has(field) or typeof(result[field]) != TYPE_BOOL:
			return false
	for field: String in NULLABLE_BOOLEAN_FIELDS:
		if not result.has(field) or (typeof(result[field]) != TYPE_BOOL and typeof(result[field]) != TYPE_NIL):
			return false
	if not result.has("outcome") or typeof(result["outcome"]) != TYPE_STRING \
		or not ["precondition_failed", "startup_unqualified", "custody_failed", "red_observed", "listener_ready"].has(result["outcome"]):
		return false
	if not result.has("child_exit") or typeof(result["child_exit"]) != TYPE_STRING \
		or not ["NOT_OBSERVED", "EXITED_ONE", "EXITED_ZERO", "SIGNALLED", "OTHER"].has(result["child_exit"]):
		return false
	if not result.has("historical_cause") or result["historical_cause"] != "UNKNOWN":
		return false
	var normalized: Dictionary = result.duplicate()
	normalized["schema_version"] = 1
	return bytes == JSON.stringify(normalized, "", true)


func test_default_logging_custody_controls_pass() -> void:
	var python: String = OS.get_environment("PROJECT0_PYTHON")
	if python.is_empty():
		python = "/usr/bin/python3"
	var controls: String = ProjectSettings.globalize_path("res://tests/fixtures/prediction_listener_logging_custody.py")
	var executable_qualified: bool = python.is_absolute_path() and _safe_argument(python) \
		and _safe_argument(controls) and FileAccess.file_exists(python)
	assert_true(executable_qualified, "1450 logging custody uses the owning Python runtime")
	if not executable_qualified:
		return
	var output: Array = []
	var exit_code: int = OS.execute(python, PackedStringArray(["-I", "-B", controls]), output, false)
	assert_true(exit_code == 0, "1450 logging custody controls emit a qualified reduced result")
	if exit_code != 0:
		return
	var bytes: String = "".join(output).trim_suffix("\n")
	assert_true(bytes.to_utf8_buffer().size() <= 512, "1450 logging custody result is bounded")
	if bytes.to_utf8_buffer().size() > 512:
		return
	var parser: JSON = JSON.new()
	var parsed: Error = parser.parse(bytes)
	assert_true(parsed == OK and typeof(parser.data) == TYPE_DICTIONARY, "1450 logging custody result is a closed object")
	if parsed != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return
	var report: Dictionary = parser.data
	var counts: Array[String] = ["schema_version", "tests", "failures", "errors", "skips"]
	var flags: Array[String] = ["passed", "cleanup_verified", "source_qualified"]
	var valid: bool = report.size() == counts.size() + flags.size()
	var normalized: Dictionary = report.duplicate()
	for field: String in counts:
		if not report.has(field) or (typeof(report[field]) != TYPE_INT and typeof(report[field]) != TYPE_FLOAT):
			valid = false
			continue
		if report[field] < 0 or report[field] > 10:
			valid = false
			continue
		if report[field] != int(report[field]):
			valid = false
		normalized[field] = int(report[field])
	for field: String in flags:
		if not report.has(field) or typeof(report[field]) != TYPE_BOOL:
			valid = false
	valid = valid and bytes == JSON.stringify(normalized, "", true)
	assert_true(valid, "1450 logging custody result has exact types and spelling")
	if not valid:
		return
	var passed: bool = report["schema_version"] == 1 and report["tests"] == 10 \
		and report["failures"] == 0 and report["errors"] == 0 and report["skips"] == 0 \
		and report["passed"] == true and report["cleanup_verified"] == true and report["source_qualified"] == true
	assert_true(passed, "1450 exact logging custody preserves unknown state and removes only owned state")
