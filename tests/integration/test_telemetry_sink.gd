extends GutTest
## Slice 160 (telemetry map #282, decisions #287/#288): public-seam tests for
## the telemetry sink (server/telemetry_sink.gd) over a real temporary
## user:// SQLite database opened through the SqliteStore engine seam
## (consumed unmodified), mirroring tests/integration/test_vessel_repository.gd.
## Covers schema creation, validated writes, rejection of invalid events, and
## the retention/row-ceiling enforcement. See
## docs/slices/160-telemetry-sink-database.md.

const SqliteStoreScript: Script = preload("res://server/sqlite_store.gd")
const TelemetrySinkScript: Script = preload("res://server/telemetry_sink.gd")
const TelemetryEventScript: Script = preload("res://shared/telemetry_event.gd")

var _relative_path: String = ""
var _store: SqliteStore = null
var _sink: TelemetrySink = null


func before_each() -> void:
	_relative_path = "test_telemetry_sink_%d_%d.db" % [Time.get_ticks_usec(), randi()]
	_store = SqliteStoreScript.new()
	_store.open(_relative_path)
	_sink = TelemetrySinkScript.new(_store)
	_sink.ensure_schema()


func after_each() -> void:
	if _store != null and _store.is_open():
		_store.close()
	for suffix: String in ["", "-wal", "-shm", "-journal"]:
		var path: String = ProjectSettings.globalize_path("user://%s%s" % [_relative_path, suffix])
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _event(payload: Dictionary = {}, emitted_at_unix: int = -1) -> Dictionary:
	var timestamp: int = emitted_at_unix if emitted_at_unix >= 0 else int(Time.get_unix_time_from_system())
	return TelemetryEventScript.build(
		"connection.peer_connected", 1, timestamp, 42, 7, payload, "acct-1", "char-1", "sess-1"
	)


func test_ensure_schema_is_idempotent() -> void:
	var second: Dictionary = _sink.ensure_schema()
	assert_eq(second["outcome"], TelemetrySinkScript.OUTCOME_OK, "re-running ensure_schema is safe")


func test_valid_event_is_written_and_readable() -> void:
	var result: Dictionary = _sink.emit(_event({"houses_free_after": 2}))
	assert_eq(result["outcome"], TelemetrySinkScript.OUTCOME_OK, result["detail"])

	var rows: Dictionary = _store.query("SELECT * FROM events;")
	assert_eq(rows["rows"].size(), 1, "exactly one row was written")
	var row: Dictionary = rows["rows"][0]
	assert_eq(row["event_type"], "connection.peer_connected")
	assert_eq(int(row["peer_id"]), 7)
	assert_eq(row["account_id"], "acct-1")
	var parsed_payload: Dictionary = JSON.parse_string(row["payload"])
	assert_eq(int(parsed_payload["houses_free_after"]), 2, "payload round-trips as JSON (JSON numbers parse as float)")


func test_invalid_event_is_rejected_and_not_written() -> void:
	var malformed: Dictionary = _event()
	malformed.erase("event_type")
	var result: Dictionary = _sink.emit(malformed)
	assert_eq(result["outcome"], TelemetrySinkScript.OUTCOME_REJECTED)

	var rows: Dictionary = _store.query("SELECT COUNT(*) AS row_count FROM events;")
	assert_eq(int(rows["rows"][0]["row_count"]), 0, "a rejected event writes nothing")


func test_emit_on_closed_store_fails_closed() -> void:
	_store.close()
	var result: Dictionary = _sink.emit(_event())
	assert_eq(result["outcome"], TelemetrySinkScript.OUTCOME_NOT_OPEN)


func test_events_older_than_retention_window_are_deleted_on_next_emit() -> void:
	var stale_cutoff: int = int(Time.get_unix_time_from_system()) - TelemetrySinkScript.RETENTION_SECONDS - 10
	_sink.emit(_event({}, stale_cutoff))
	var recent: int = int(Time.get_unix_time_from_system())
	_sink.emit(_event({}, recent))

	var rows: Dictionary = _store.query("SELECT emitted_at_unix FROM events;")
	assert_eq(rows["rows"].size(), 1, "only the recent event survives the retention sweep")
	assert_eq(int(rows["rows"][0]["emitted_at_unix"]), recent)


func test_row_ceiling_trims_oldest_rows_first() -> void:
	# A small injected ceiling exercises the trim path without inserting
	# millions of rows in a unit-scoped integration test. Timestamps stay
	# well within the retention window so only the ceiling trim (not the
	# retention sweep) removes rows.
	var now: int = int(Time.get_unix_time_from_system())
	var tight_sink: TelemetrySink = TelemetrySinkScript.new(_store, 2)
	tight_sink.emit(_event({}, now - 2))
	tight_sink.emit(_event({}, now - 1))
	tight_sink.emit(_event({}, now))

	var rows: Dictionary = _store.query("SELECT emitted_at_unix FROM events ORDER BY emitted_at_unix ASC;")
	assert_eq(rows["rows"].size(), 2, "trimmed down to the injected ceiling")
	assert_eq(int(rows["rows"][0]["emitted_at_unix"]), now - 1, "the oldest row was trimmed first")
	assert_eq(int(rows["rows"][1]["emitted_at_unix"]), now)
