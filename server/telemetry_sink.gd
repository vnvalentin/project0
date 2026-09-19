extends RefCounted
class_name TelemetrySink
## Slice 160 (telemetry map #282, decisions #287/#288): the dedicated
## telemetry database writer. Server-only per CLAUDE.md ("Shared Contracts")
## and AGENTS.md; shared/ and client/ MUST NEVER reference this class or the
## SqliteStore/godot-sqlite engine it uses.
##
## Owns the `events` table (one wide table, JSON `payload` column, versioned
## per `event_type` per the envelope contract in `shared/telemetry_event.gd`)
## and its retention/volume bounds: a 30-day raw-event window enforced by an
## opportunistic write-time DELETE on every `emit()` call (no scheduled job),
## plus a hard row-count ceiling backstop independent of time, for the exact
## kind of runaway-emission bug the transport-layer rate cap is meant to
## prevent but might not fully catch.
##
## This slice owns storage only. Wiring a live instance into the server boot
## sequence, the client-to-server transport RPC, and connection/combat
## emission call sites are separate slices (see issue #328).

const TelemetryEventScript: Script = preload("res://shared/telemetry_event.gd")

## Overridable at runtime, matching PROJECT0_CANON_DB_PATH/
## PROJECT0_ACCOUNTS_DB_PATH's convention.
const DB_PATH_ENV_VAR: String = "PROJECT0_TELEMETRY_DB_PATH"
const DEFAULT_DB_PATH: String = "telemetry.db"

## 30 days of raw retention, per decision #288.
const RETENTION_SECONDS: int = 30 * 86400
## Hard backstop independent of the time window, per decision #288.
const MAX_ROW_CEILING: int = 2000000

const OUTCOME_OK: String = "ok"
const OUTCOME_NOT_OPEN: String = "not_open"
## The event failed shared/telemetry_event.gd's validate(); nothing was written.
const OUTCOME_REJECTED: String = "rejected"
const OUTCOME_QUERY_FAILED: String = "query_failed"

var _store: SqliteStore = null
var _row_ceiling: int = MAX_ROW_CEILING


## `row_ceiling` defaults to MAX_ROW_CEILING; overridable only so tests can
## exercise the trim path without inserting millions of rows.
func _init(store: SqliteStore, row_ceiling: int = MAX_ROW_CEILING) -> void:
	_store = store
	_row_ceiling = row_ceiling


## Server-owned telemetry database path, honoring DB_PATH_ENV_VAR when set.
static func resolve_db_path() -> String:
	var override: String = OS.get_environment(DB_PATH_ENV_VAR).strip_edges()
	if override.is_empty():
		return DEFAULT_DB_PATH
	return override


## Idempotent `CREATE TABLE IF NOT EXISTS` for the events table and its
## query-pattern indexes (engineering diagnosis by event_type+time; player-
## behavior analysis by account/peer+time).
func ensure_schema() -> Dictionary:
	if _store == null or not _store.is_open():
		return _result(OUTCOME_NOT_OPEN, "Store is not open.")

	var create_table: Dictionary = _store.query("""
		CREATE TABLE IF NOT EXISTS events (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			event_type TEXT NOT NULL,
			schema_version INTEGER NOT NULL,
			emitted_at_unix INTEGER NOT NULL,
			server_tick INTEGER NOT NULL,
			peer_id INTEGER NOT NULL,
			account_id TEXT,
			character_id TEXT,
			session_id TEXT,
			payload TEXT NOT NULL
		);
	""")
	if create_table["outcome"] != SqliteStore.OUTCOME_OK:
		return _result(OUTCOME_QUERY_FAILED, "events table failed: %s" % create_table["detail"])

	var create_type_index: Dictionary = _store.query(
		"CREATE INDEX IF NOT EXISTS idx_events_type_time ON events (event_type, emitted_at_unix);"
	)
	if create_type_index["outcome"] != SqliteStore.OUTCOME_OK:
		return _result(OUTCOME_QUERY_FAILED, "type/time index failed: %s" % create_type_index["detail"])

	var create_account_index: Dictionary = _store.query(
		"CREATE INDEX IF NOT EXISTS idx_events_account_time ON events (account_id, emitted_at_unix);"
	)
	if create_account_index["outcome"] != SqliteStore.OUTCOME_OK:
		return _result(OUTCOME_QUERY_FAILED, "account/time index failed: %s" % create_account_index["detail"])

	var create_peer_index: Dictionary = _store.query(
		"CREATE INDEX IF NOT EXISTS idx_events_peer_time ON events (peer_id, emitted_at_unix);"
	)
	if create_peer_index["outcome"] != SqliteStore.OUTCOME_OK:
		return _result(OUTCOME_QUERY_FAILED, "peer/time index failed: %s" % create_peer_index["detail"])

	return _result(OUTCOME_OK, "Telemetry schema ready.")


## Validates then writes one event, and opportunistically enforces retention.
## A rejected/malformed event is never written; a write failure never blocks
## retention enforcement from at least being attempted on the next call.
func emit(event: Dictionary) -> Dictionary:
	if _store == null or not _store.is_open():
		return _result(OUTCOME_NOT_OPEN, "Store is not open.")

	var validation: Dictionary = TelemetryEventScript.validate(event)
	if validation["outcome"] != TelemetryEventScript.OUTCOME_ACCEPTED:
		return _result(OUTCOME_REJECTED, validation["detail"])

	var insert: Dictionary = _store.query_with_bindings(
		"""
		INSERT INTO events (
			event_type, schema_version, emitted_at_unix, server_tick, peer_id,
			account_id, character_id, session_id, payload
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
		""",
		[
			event["event_type"],
			event["schema_version"],
			event["emitted_at_unix"],
			event["server_tick"],
			event["peer_id"],
			event.get("account_id", ""),
			event.get("character_id", ""),
			event.get("session_id", ""),
			JSON.stringify(event["payload"]),
		]
	)
	if insert["outcome"] != SqliteStore.OUTCOME_OK:
		return _result(OUTCOME_QUERY_FAILED, "Insert failed: %s" % insert["detail"])

	_enforce_retention()
	return _result(OUTCOME_OK, "")


## Deletes rows older than RETENTION_SECONDS, then trims down to
## MAX_ROW_CEILING (oldest first) if the table is still over the hard cap.
## Best-effort: a failure here never blocks the caller's emit() result.
func _enforce_retention() -> void:
	var cutoff: int = int(Time.get_unix_time_from_system()) - RETENTION_SECONDS
	_store.query_with_bindings("DELETE FROM events WHERE emitted_at_unix < ?;", [cutoff])

	var count_result: Dictionary = _store.query("SELECT COUNT(*) AS row_count FROM events;")
	if count_result["outcome"] != SqliteStore.OUTCOME_OK or count_result["rows"].is_empty():
		return
	var row_count: int = int(count_result["rows"][0]["row_count"])
	if row_count <= _row_ceiling:
		return
	var excess: int = row_count - _row_ceiling
	_store.query_with_bindings(
		"DELETE FROM events WHERE id IN (SELECT id FROM events ORDER BY emitted_at_unix ASC LIMIT ?);", [excess]
	)


func _result(outcome: String, detail: String) -> Dictionary:
	return {"outcome": outcome, "detail": detail}
