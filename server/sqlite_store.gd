extends RefCounted
class_name SqliteStore
## Slice 038: the shared server-owned SQLite engine foundation. Server-only
## per CLAUDE.md ("Shared Contracts") and AGENTS.md; shared/ and client/ MUST
## NEVER reference this class or the godot-sqlite GDExtension it wraps.
##
## Scope: this is the ENGINE SEAM ONLY. It owns the DB handle lifecycle
## (user://, WAL, PRAGMA user_version fail-closed), an atomic transaction
## helper, and a parameter-bound query API. It defines no domain tables
## (accounts/characters/canon are later slices per docs/slices/038-*.md).
##
## Every public method returns a bounded, structured result Dictionary and
## never raises: callers get an explicit outcome rather than an exception or a
## silently-guessed fallback, matching CLAUDE.md's fail-closed persistence
## rule.

const SUPPORTED_USER_VERSION: int = 1

const OUTCOME_OK: String = "ok"
const OUTCOME_ALREADY_OPEN: String = "already_open"
const OUTCOME_NOT_OPEN: String = "not_open"
const OUTCOME_OPEN_FAILED: String = "open_failed"
const OUTCOME_UNSUPPORTED_VERSION: String = "unsupported_version"
const OUTCOME_QUERY_FAILED: String = "query_failed"
const OUTCOME_TRANSACTION_FAILED: String = "transaction_failed"

## Slice 1325: physical Canon tables whose INSERT/UPDATE statements are counted.
const CANON_WRITE_TABLES: PackedStringArray = ["canon_sectors", "canon_mutations"]
const CANON_WRITE_WINDOWS: PackedStringArray = ["attempted", "committed", "rolled_back", "failed"]

const StatementObserverScript: Script = preload("res://server/sqlite_statement_observer.gd")

var _statement_observer: RefCounted = StatementObserverScript.new()
var _connection_id: int = 0
var _db: SQLite = null
var _db_path_user_uri: String = ""
var _is_open: bool = false
var _canon_writes: Dictionary = {}
var _pending_canon_writes: Array[String] = []
var _in_transaction: bool = false
var _transaction_query_failed: bool = false
var _write_target: RegEx = RegEx.create_from_string("(?i)^\\s*(?:INSERT|REPLACE|UPDATE)(?:\\s+OR\\s+\\w+)?(?:\\s+INTO)?\\s+[\"`\\[]?(\\w+)")


func _init() -> void:
	for window: String in CANON_WRITE_WINDOWS:
		_canon_writes[window] = {}
		for table: String in CANON_WRITE_TABLES:
			_canon_writes[window][table] = 0


## Public seam. Per-table Canon INSERT/UPDATE statement counts for this store
## instance: attempted = every statement issued, failed = statement errors,
## committed/rolled_back = outcome of the enclosing transaction (autocommit
## statements count as committed).
func canon_write_counters() -> Dictionary:
	return _canon_writes.duplicate(true)


## #1347 public seam. Explicitly start after schema setup. Qualification observes
## schema metadata only. Unsupported coverage is evidence failure, never a ban
## on production SQL. Native row effects/other connections are not observed.
func start_dml_observation() -> Dictionary:
	if not _is_open or _in_transaction:
		_statement_observer.invalidate("window_start_requires_open_idle_connection")
		var report: Dictionary = _statement_observer.report()
		report["reasons"].append("window_start_requires_open_idle_connection")
		return report
	var tables: Array[String] = []
	var reasons: Array[String] = []
	if not _db.has_method("get_autocommit") or not bool(_db.call("get_autocommit")):
		reasons.append("autocommit_scope_not_observed")
	if not _db.query("PRAGMA database_list;"):
		reasons.append("schema_qualification_failed")
	else:
		for database: Dictionary in _db.query_result:
			if str(database["name"]) not in ["main", "temp"]:
				reasons.append("attached_database")
	if not _db.query("SELECT 'main' AS schema_name, name, type, sql FROM sqlite_master UNION ALL SELECT 'temp' AS schema_name, name, type, sql FROM sqlite_temp_master;"):
		reasons.append("schema_qualification_failed")
	else:
		var schema: Array = _db.query_result.duplicate(true)
		for entry: Dictionary in schema:
			if entry["schema_name"] != "main":
				reasons.append("temporary_schema")
				continue
			var table: String = str(entry["name"])
			if entry["type"] in ["trigger", "view"]:
				reasons.append("trigger_or_view_schema")
			elif entry["type"] == "table":
				if RegEx.create_from_string("(?i)^CREATE\\s+VIRTUAL\\s+TABLE").search(str(entry["sql"])) != null:
					reasons.append("virtual_table_schema")
				if RegEx.create_from_string("^[A-Za-z_][A-Za-z0-9_]*$").search(table) == null:
					reasons.append("unsupported_schema_identifier")
					continue
				tables.append(table.to_lower())
				if not _db.query('PRAGMA foreign_key_list("%s");' % table):
					reasons.append("schema_qualification_failed")
				else:
					for foreign_key: Dictionary in _db.query_result:
						if foreign_key["on_update"] not in ["NO ACTION", "RESTRICT"] or foreign_key["on_delete"] not in ["NO ACTION", "RESTRICT"]:
							reasons.append("foreign_key_side_effects")
	return _statement_observer.start(_connection_id, tables, reasons)


## Snapshot only: neither this window nor existing Canon counters are reset.
## Prior windows remain visible, including any incomplete coverage verdict.
func dml_statement_counters() -> Dictionary:
	return _statement_observer.report()


## Public seam. Opens (creating on first use) the SQLite database at
## `user://<relative_path>`. NEVER accepts a res:// path: the DB is a runtime
## server artifact, not a shipped asset.
##
## On a fresh DB, initializes PRAGMA journal_mode=WAL and sets
## PRAGMA user_version to SUPPORTED_USER_VERSION. On an existing DB, reads
## user_version and FAILS CLOSED (does not open, does not mutate) if it is
## unsupported; it never guesses a migration forward.
##
## Returns { "outcome": OUTCOME_*, "detail": String, "user_version": int }.
func open(relative_path: String) -> Dictionary:
	if _is_open:
		return _result(OUTCOME_ALREADY_OPEN, "Store is already open at %s." % _db_path_user_uri, -1)
	if relative_path.begins_with("res://"):
		return _result(OUTCOME_OPEN_FAILED, "SqliteStore MUST NOT open a res:// path; use a user:// relative path.", -1)

	var db_uri: String = "user://%s" % relative_path.trim_prefix("user://")
	var db := SQLite.new()
	db.path = db_uri
	db.foreign_keys = true

	if not db.open_db():
		return _result(OUTCOME_OPEN_FAILED, "godot-sqlite failed to open '%s'." % db_uri, -1)

	if not db.query("PRAGMA journal_mode=WAL;"):
		db.close_db()
		return _result(OUTCOME_OPEN_FAILED, "Failed to enable WAL journal mode on '%s'." % db_uri, -1)

	var current_version: int = _read_user_version(db)

	if current_version == 0:
		# Fresh database (SQLite defaults user_version to 0): claim it at the
		# schema-engine version this build supports.
		if not db.query("PRAGMA user_version = %d;" % SUPPORTED_USER_VERSION):
			db.close_db()
			return _result(OUTCOME_OPEN_FAILED, "Failed to initialize user_version on '%s'." % db_uri, -1)
		current_version = SUPPORTED_USER_VERSION
	elif current_version != SUPPORTED_USER_VERSION:
		# Fail closed: an unsupported version (older or newer than what this
		# build understands) must not be opened, migrated forward, or mutated.
		db.close_db()
		return _result(
			OUTCOME_UNSUPPORTED_VERSION,
			"Database '%s' has user_version=%d; this build supports only %d." % [db_uri, current_version, SUPPORTED_USER_VERSION],
			current_version
		)

	_db = db
	_db_path_user_uri = db_uri
	_is_open = true
	_connection_id += 1
	return _result(OUTCOME_OK, "Opened '%s' at user_version=%d." % [db_uri, current_version], current_version)


## Public seam. Closes the database handle. Safe to call when not open.
func close() -> Dictionary:
	if not _is_open:
		return _result(OUTCOME_NOT_OPEN, "Store is not open.", -1)
	_statement_observer.invalidate("connection_closed")
	_db.close_db()
	_db = null
	_db_path_user_uri = ""
	_is_open = false
	return _result(OUTCOME_OK, "Closed.", -1)


## Public seam. True while a database handle is open.
func is_open() -> bool:
	return _is_open


## Public seam. Returns the PRAGMA user_version currently recorded in the
## open database, or -1 if the store is not open.
func get_user_version() -> int:
	if not _is_open:
		return -1
	return _read_user_version(_db)


## Public seam. Runs `body` (a Callable taking no arguments and returning
## true on success, false to trigger rollback) inside a BEGIN/COMMIT
## transaction. Any false return, or any query failure inside `body`, rolls
## the transaction back so NO PARTIAL DURABLE RECORD is left — CLAUDE.md's
## atomic-commit rule. `body` should perform its work via this store's own
## query_with_bindings()/query() so failures are detected consistently.
##
## Returns { "outcome": OUTCOME_*, "detail": String }.
func transaction(body: Callable) -> Dictionary:
	if not _is_open:
		return _result(OUTCOME_NOT_OPEN, "Store is not open.", -1)

	if not _db.query("BEGIN;"):
		return _result(OUTCOME_TRANSACTION_FAILED, "Failed to BEGIN transaction.", -1)
	_in_transaction = true
	_transaction_query_failed = false
	_pending_canon_writes.clear()

	var body_ok: bool = false
	var body_detail: String = ""
	var had_error: bool = false
	if body.is_valid():
		var outcome: Variant = body.call()
		if outcome is bool:
			body_ok = outcome
			if not body_ok:
				body_detail = "Transaction body returned false."
		else:
			had_error = true
			body_detail = "Transaction body did not return a bool."
	else:
		had_error = true
		body_detail = "Transaction body Callable is not valid."

	if _transaction_query_failed:
		had_error = true
		body_detail = "A query failed inside the transaction."

	if body_ok and not had_error:
		if not _db.query("COMMIT;"):
			var rolled_back: bool = _db.query("ROLLBACK;")
			_statement_observer.finish_transaction("rolled_back" if rolled_back else "unknown")
			_finish_canon_transaction("rolled_back")
			return _result(OUTCOME_TRANSACTION_FAILED, "COMMIT failed; rolled back.", -1)
		_statement_observer.finish_transaction("committed")
		_finish_canon_transaction("committed")
		return _result(OUTCOME_OK, "Committed.", -1)

	var rolled_back: bool = _db.query("ROLLBACK;")
	_statement_observer.finish_transaction("rolled_back" if rolled_back else "unknown")
	_finish_canon_transaction("rolled_back")
	return _result(OUTCOME_TRANSACTION_FAILED, body_detail if body_detail != "" else "Transaction rolled back.", -1)


## Public seam. Parameter-bound query. `sql` MUST use `?` placeholders;
## `bindings` supplies the values positionally. This is the ONLY query entry
## point that should ever carry variable/player-supplied data — never build
## SQL by string concatenation/interpolation of untrusted values.
##
## Returns { "outcome": OUTCOME_*, "detail": String, "rows": Array }.
func query_with_bindings(sql: String, bindings: Array = []) -> Dictionary:
	if not _is_open:
		return _result_rows(OUTCOME_NOT_OPEN, "Store is not open.", [])
	if not _db.query_with_bindings(sql, bindings):
		if _in_transaction:
			_transaction_query_failed = true
		_note_statement(sql, false)
		_note_canon_write(sql, false)
		return _result_rows(OUTCOME_QUERY_FAILED, _db.error_message, [])
	_note_statement(sql, true)
	_note_canon_write(sql, true)
	return _result_rows(OUTCOME_OK, "", _db.query_result.duplicate(true))


## Public seam. Executes `sql` with no bindings — for DDL/PRAGMA statements
## that carry no variable data (e.g. CREATE TABLE). MUST NOT be used to
## interpolate variable/player-supplied values; use query_with_bindings for
## any statement that carries data.
##
## Returns { "outcome": OUTCOME_*, "detail": String, "rows": Array }.
func query(sql: String) -> Dictionary:
	if not _is_open:
		return _result_rows(OUTCOME_NOT_OPEN, "Store is not open.", [])
	if not _db.query(sql):
		if _in_transaction:
			_transaction_query_failed = true
		_note_statement(sql, false)
		_note_canon_write(sql, false)
		return _result_rows(OUTCOME_QUERY_FAILED, _db.error_message, [])
	_note_statement(sql, true)
	_note_canon_write(sql, true)
	return _result_rows(OUTCOME_OK, "", _db.query_result.duplicate(true))


func _note_statement(sql: String, succeeded: bool) -> void:
	var native_transaction: bool = _in_transaction
	if _db.has_method("get_autocommit"):
		native_transaction = not bool(_db.call("get_autocommit"))
	_statement_observer.observe(sql, succeeded, native_transaction)


func _note_canon_write(sql: String, succeeded: bool) -> void:
	var found: RegExMatch = _write_target.search(sql)
	if found == null:
		return
	var table: String = found.get_string(1).to_lower()
	if not CANON_WRITE_TABLES.has(table):
		return
	_canon_writes["attempted"][table] += 1
	if not succeeded:
		_canon_writes["failed"][table] += 1
	elif _in_transaction:
		_pending_canon_writes.append(table)
	else:
		_canon_writes["committed"][table] += 1


func _finish_canon_transaction(window: String) -> void:
	for table: String in _pending_canon_writes:
		_canon_writes[window][table] += 1
	_pending_canon_writes.clear()
	_in_transaction = false
	_transaction_query_failed = false


func _read_user_version(db: SQLite) -> int:
	if not db.query("PRAGMA user_version;"):
		return -1
	var rows: Array = db.query_result
	if rows.is_empty():
		return -1
	return int(rows[0]["user_version"])


func _result(outcome: String, detail: String, user_version: int) -> Dictionary:
	return {
		"outcome": outcome,
		"detail": detail,
		"user_version": user_version,
	}


func _result_rows(outcome: String, detail: String, rows: Array) -> Dictionary:
	return {
		"outcome": outcome,
		"detail": detail,
		"rows": rows,
	}
