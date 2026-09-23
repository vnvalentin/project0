extends GutTest
## Slice 162 (telemetry map #282): public-seam tests for the telemetry ingest
## orchestration (server/telemetry_ingest_service.gd) over a real temporary
## user:// SQLite database via server/telemetry_sink.gd, mirroring
## tests/integration/test_telemetry_sink.gd. Covers the untrusted-input
## boundary this class enforces: the caller's peer_id/character_id/timing
## always win over anything the "client" batch tries to claim.

const SqliteStoreScript: Script = preload("res://server/sqlite_store.gd")
const TelemetrySinkScript: Script = preload("res://server/telemetry_sink.gd")
const TelemetryRateLimiterScript: Script = preload("res://server/telemetry_rate_limiter.gd")
const TelemetryIngestServiceScript: Script = preload("res://server/telemetry_ingest_service.gd")

var _relative_path: String = ""
var _store: SqliteStore = null
var _sink: TelemetrySink = null
var _limiter: TelemetryRateLimiter = null
var _ingest: TelemetryIngestService = null


func before_each() -> void:
	_relative_path = "test_telemetry_ingest_%d_%d.db" % [Time.get_ticks_usec(), randi()]
	_store = SqliteStoreScript.new()
	_store.open(_relative_path)
	_sink = TelemetrySinkScript.new(_store)
	_sink.ensure_schema()
	_limiter = TelemetryRateLimiterScript.new()
	_ingest = TelemetryIngestServiceScript.new(_sink, _limiter)


func after_each() -> void:
	if _store != null and _store.is_open():
		_store.close()
	for suffix: String in ["", "-wal", "-shm", "-journal"]:
		var path: String = ProjectSettings.globalize_path("user://%s%s" % [_relative_path, suffix])
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _rows() -> Array:
	return _store.query("SELECT * FROM events;")["rows"]


func test_a_well_formed_batch_is_written_with_caller_supplied_identity() -> void:
	var now: int = int(Time.get_unix_time_from_system())
	var accepted: Array[Dictionary] = _ingest.ingest_batch(
		7,
		[{"event_type": "connection.peer_connected", "schema_version": 1, "payload": {}}],
		"char-42",
		now,
		100,
	)

	var rows: Array = _rows()
	assert_eq(rows.size(), 1)
	assert_eq(accepted.size(), 1, "the accepted raw event is returned to server orchestration")
	assert_eq(int(rows[0]["peer_id"]), 7, "peer_id comes from the caller, not the raw event")
	assert_eq(rows[0]["character_id"], "char-42")
	assert_eq(int(rows[0]["emitted_at_unix"]), now)
	assert_eq(int(rows[0]["server_tick"]), 100)


func test_client_supplied_identity_fields_in_the_raw_event_are_ignored() -> void:
	# A malicious/buggy client cannot forge peer_id, character_id, or timing
	# by stuffing them into the raw event — only event_type/schema_version/
	# payload are ever read from client input.
	var now: int = int(Time.get_unix_time_from_system())
	_ingest.ingest_batch(
		7,
		[{
			"event_type": "connection.peer_connected",
			"schema_version": 1,
			"payload": {},
			"peer_id": 999,
			"character_id": "forged-character",
			"emitted_at_unix": 1,
			"server_tick": 999999,
		}],
		"char-42",
		now,
		100
	)

	var rows: Array = _rows()
	assert_eq(int(rows[0]["peer_id"]), 7, "the caller's peer_id wins, not the client's claim")
	assert_eq(rows[0]["character_id"], "char-42", "the caller's character_id wins, not the client's claim")
	assert_eq(int(rows[0]["emitted_at_unix"]), now, "the caller's timestamp wins, not the client's claim")
	assert_eq(int(rows[0]["server_tick"]), 100, "the caller's server_tick wins, not the client's claim")


func test_malformed_raw_events_are_skipped_without_aborting_the_batch() -> void:
	var now: int = int(Time.get_unix_time_from_system())
	_ingest.ingest_batch(
		7,
		[
			{"event_type": "connection.peer_connected", "schema_version": 1, "payload": {}},
			{"schema_version": 1, "payload": {}}, # missing event_type
			"not a dictionary at all",
			{"event_type": "connection.peer_connected", "schema_version": "not an int", "payload": {}},
		],
		"char-42",
		now,
		100
	)
	assert_eq(_rows().size(), 1, "only the one well-formed event was written")


func test_rate_limited_batch_writes_nothing() -> void:
	var now: int = int(Time.get_unix_time_from_system())
	var over_capacity: int = int(TelemetryRateLimiterScript.CAPACITY) + 1
	var events: Array = []
	for i: int in range(over_capacity):
		events.append({"event_type": "connection.peer_connected", "schema_version": 1, "payload": {}})
	var accepted: Array[Dictionary] = _ingest.ingest_batch(7, events, "char-42", now, 100)
	assert_eq(_rows().size(), 0, "an over-budget batch is rejected as a whole, nothing is written")
	assert_true(accepted.is_empty(), "rate-limited events are not reported as accepted")


func test_empty_batch_is_a_no_op() -> void:
	_ingest.ingest_batch(7, [], "char-42", int(Time.get_unix_time_from_system()), 100)
	assert_eq(_rows().size(), 0)


func test_no_sink_makes_ingest_a_silent_no_op() -> void:
	var ingest_without_sink: TelemetryIngestService = TelemetryIngestServiceScript.new(null, _limiter)
	var accepted: Array[Dictionary] = ingest_without_sink.ingest_batch(7, [{"event_type": "connection.peer_connected", "schema_version": 1, "payload": {}}], "char-42", int(Time.get_unix_time_from_system()), 100)
	assert_eq(_rows().size(), 0, "no sink means nothing is written, and nothing crashes")
	assert_true(accepted.is_empty(), "unavailable storage cannot report an accepted event")
