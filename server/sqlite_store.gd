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

var _db: SQLite = null
var _db_path_user_uri: String = ""
var _is_open: bool = false


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
	return _result(OUTCOME_OK, "Opened '%s' at user_version=%d." % [db_uri, current_version], current_version)


## Public seam. Closes the database handle. Safe to call when not open.
func close() -> Dictionary:
	if not _is_open:
		return _result(OUTCOME_NOT_OPEN, "Store is not open.", -1)
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

	if body_ok and not had_error:
		if not _db.query("COMMIT;"):
			_db.query("ROLLBACK;")
			return _result(OUTCOME_TRANSACTION_FAILED, "COMMIT failed; rolled back.", -1)
		return _result(OUTCOME_OK, "Committed.", -1)

	_db.query("ROLLBACK;")
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
		return _result_rows(OUTCOME_QUERY_FAILED, _db.error_message, [])
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
		return _result_rows(OUTCOME_QUERY_FAILED, _db.error_message, [])
	return _result_rows(OUTCOME_OK, "", _db.query_result.duplicate(true))


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
