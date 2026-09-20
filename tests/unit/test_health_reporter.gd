extends GutTest
## Public-seam unit tests for Slice 067's runtime health-file writer
## (server/health_reporter.gd). Exercises the static path resolver and the
## snapshot writer against a temp user:// file, plus an end-to-end
## ServerHealth.build_snapshot -> HealthReporter.write_snapshot round-trip. See
## docs/slices/067-server-health-file-healthcheck.md.

const HealthReporterScript: Script = preload("res://server/health_reporter.gd")
const ServerHealthScript: Script = preload("res://server/server_health.gd")

const TEMP_HEALTH_PATH: String = "user://test_health_reporter.json"
const TEMP_OPS_PATH: String = "user://test_ops_snapshot.json"


func after_each() -> void:
	if FileAccess.file_exists(TEMP_HEALTH_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_HEALTH_PATH))
	if FileAccess.file_exists(TEMP_OPS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_OPS_PATH))


func _valid_snapshot(status: String) -> Dictionary:
	var built: Dictionary = ServerHealthScript.build_snapshot({
		"status": status,
		"tick_rate": 30,
		"uptime_seconds": 4.5,
		"server_tick": 270,
		"connected_peers": 1,
		"max_peers": 10,
		"app_schema_version": 1,
		"timestamp": 1_726_000_000,
	})
	assert_eq(built["outcome"], ServerHealthScript.OUTCOME_OK, "fixture snapshot is valid")
	return built["snapshot"]


func test_resolve_path_defaults_on_empty() -> void:
	assert_eq(HealthReporterScript.resolve_health_file_path(""), HealthReporterScript.DEFAULT_HEALTH_FILE_PATH, "empty config resolves to the default path")


func test_resolve_path_defaults_on_whitespace() -> void:
	assert_eq(HealthReporterScript.resolve_health_file_path("   "), HealthReporterScript.DEFAULT_HEALTH_FILE_PATH, "whitespace-only config resolves to the default path")


func test_resolve_path_uses_trimmed_override() -> void:
	assert_eq(HealthReporterScript.resolve_health_file_path("  /data/health.json  "), "/data/health.json", "a non-empty override is honored (trimmed)")


func test_write_snapshot_round_trips_to_disk() -> void:
	var snapshot: Dictionary = _valid_snapshot(ServerHealthScript.STATUS_HEALTHY)
	var result: Dictionary = HealthReporterScript.write_snapshot(TEMP_HEALTH_PATH, snapshot)
	assert_eq(result["outcome"], HealthReporterScript.OUTCOME_OK, "write reports ok")

	var file: FileAccess = FileAccess.open(TEMP_HEALTH_PATH, FileAccess.READ)
	assert_not_null(file, "health file exists after write")
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	assert_true(parsed is Dictionary, "written content parses as JSON")
	assert_eq((parsed as Dictionary)["status"], ServerHealthScript.STATUS_HEALTHY, "status round-trips")
	assert_eq((parsed as Dictionary)["tick_rate"], 30, "tick_rate round-trips")
	assert_eq((parsed as Dictionary)["snapshot_schema_version"], ServerHealthScript.SNAPSHOT_SCHEMA_VERSION, "schema version round-trips")


func test_write_snapshot_fails_closed_on_unwritable_path() -> void:
	# A path whose parent directory does not exist cannot be opened; the writer
	# returns an error outcome rather than raising.
	var result: Dictionary = HealthReporterScript.write_snapshot("user://no_such_dir/deep/health.json", _valid_snapshot(ServerHealthScript.STATUS_HEALTHY))
	assert_eq(result["outcome"], HealthReporterScript.OUTCOME_ERROR, "an unwritable path fails closed")
	assert_true(result.has("detail"), "the error carries a bounded detail")


func test_healthy_snapshot_lands_on_disk_end_to_end() -> void:
	var snapshot: Dictionary = _valid_snapshot(ServerHealthScript.STATUS_HEALTHY)
	HealthReporterScript.write_snapshot(TEMP_HEALTH_PATH, snapshot)
	var text: String = FileAccess.get_file_as_string(TEMP_HEALTH_PATH)
	assert_string_contains(text, "\"status\":\"healthy\"", "the on-disk file reports the healthy status the healthcheck greps for")


func test_ops_snapshot_writer_round_trips_atomically() -> void:
	var snapshot: Dictionary = {"snapshot_schema_version": 1, "server_id": "project0-game", "status": "healthy"}
	var result: Dictionary = HealthReporterScript.write_ops_snapshot(TEMP_OPS_PATH, snapshot)
	assert_eq(result["outcome"], HealthReporterScript.OUTCOME_OK, "ops snapshot write reports ok")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TEMP_OPS_PATH))
	assert_true(parsed is Dictionary, "ops snapshot parses as JSON")
	assert_eq((parsed as Dictionary)["server_id"], "project0-game", "ops snapshot round-trips")
	assert_false(FileAccess.file_exists(TEMP_OPS_PATH + ".tmp"), "temporary file is not left behind")


func test_ops_snapshot_writer_fails_closed_on_unwritable_path() -> void:
	var result: Dictionary = HealthReporterScript.write_ops_snapshot("user://no_such_dir/ops.json", {"status": "healthy"})
	assert_eq(result["outcome"], HealthReporterScript.OUTCOME_ERROR, "ops snapshot write fails closed")
