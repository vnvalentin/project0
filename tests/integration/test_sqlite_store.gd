extends GutTest
## Headless public-seam test for Slice 038's shared server-owned SQLite
## engine foundation (server/sqlite_store.gd). Covers the BDD scenarios from
## docs/slices/038-shared-sqlite-persistence-foundation.md: fresh-open
## WAL/user_version init, durability across restart, atomic rollback on
## error, fail-closed on an unsupported user_version, and parameter-bound
## injection safety. No domain tables — this slice is the engine seam only.

const SqliteStoreScript: Script = preload("res://server/sqlite_store.gd")

var _relative_path: String = ""


func before_each() -> void:
	_relative_path = "test_sqlite_store_%d_%d.db" % [Time.get_ticks_usec(), randi()]


func after_each() -> void:
	_delete_user_file(_relative_path)
	_delete_user_file(_relative_path + "-wal")
	_delete_user_file(_relative_path + "-shm")
	_delete_user_file(_relative_path + "-journal")


func _delete_user_file(relative_path: String) -> void:
	var abs_path: String = ProjectSettings.globalize_path("user://%s" % relative_path)
	if FileAccess.file_exists(abs_path):
		DirAccess.remove_absolute(abs_path)


func test_fresh_open_creates_db_enables_wal_and_sets_user_version_one() -> void:
	var store: SqliteStore = SqliteStoreScript.new()
	var result: Dictionary = store.open(_relative_path)

	assert_eq(result["outcome"], SqliteStoreScript.OUTCOME_OK, "fresh open succeeds: %s" % result["detail"])
	assert_true(store.is_open(), "store reports open after a successful open()")
	assert_eq(store.get_user_version(), 1, "fresh database is initialized at user_version 1")

	var journal_mode: Dictionary = store.query("PRAGMA journal_mode;")
	assert_eq(journal_mode["outcome"], SqliteStoreScript.OUTCOME_OK, "journal_mode PRAGMA succeeds")
	assert_eq(String(journal_mode["rows"][0]["journal_mode"]).to_lower(), "wal", "WAL journal mode is enabled")

	var abs_path: String = ProjectSettings.globalize_path("user://%s" % _relative_path)
	assert_true(FileAccess.file_exists(abs_path), "the database file is created on disk under user://")

	store.close()


func test_committed_transaction_is_durable_across_restart() -> void:
	var store: SqliteStore = SqliteStoreScript.new()
	store.open(_relative_path)
	store.query("CREATE TABLE IF NOT EXISTS durability_probe (id INTEGER PRIMARY KEY, name TEXT NOT NULL);")

	var txn_result: Dictionary = store.transaction(func() -> bool:
		var insert: Dictionary = store.query_with_bindings(
			"INSERT INTO durability_probe (name) VALUES (?);", ["alice"]
		)
		return insert["outcome"] == SqliteStoreScript.OUTCOME_OK
	)
	assert_eq(txn_result["outcome"], SqliteStoreScript.OUTCOME_OK, "commit succeeds: %s" % txn_result["detail"])

	store.close()

	var reopened: SqliteStore = SqliteStoreScript.new()
	var reopen_result: Dictionary = reopened.open(_relative_path)
	assert_eq(reopen_result["outcome"], SqliteStoreScript.OUTCOME_OK, "reopen after restart succeeds")

	var select_result: Dictionary = reopened.query("SELECT name FROM durability_probe;")
	assert_eq(select_result["rows"].size(), 1, "the committed row survives close+reopen")
	assert_eq(select_result["rows"][0]["name"], "alice", "the durable row has the committed value")

	reopened.close()


func test_transaction_error_before_commit_leaves_no_partial_row() -> void:
	var store: SqliteStore = SqliteStoreScript.new()
	store.open(_relative_path)
	store.query("CREATE TABLE IF NOT EXISTS rollback_probe (id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE);")

	var txn_result: Dictionary = store.transaction(func() -> bool:
		var insert: Dictionary = store.query_with_bindings(
			"INSERT INTO rollback_probe (name) VALUES (?);", ["bob"]
		)
		if insert["outcome"] != SqliteStoreScript.OUTCOME_OK:
			return false
		# Force an error before COMMIT: violates the UNIQUE constraint just added.
		var conflicting_insert: Dictionary = store.query_with_bindings(
			"INSERT INTO rollback_probe (name) VALUES (?);", ["bob"]
		)
		return conflicting_insert["outcome"] == SqliteStoreScript.OUTCOME_OK
	)
	assert_eq(txn_result["outcome"], SqliteStoreScript.OUTCOME_TRANSACTION_FAILED, "the failing transaction reports rollback")

	store.close()

	var reopened: SqliteStore = SqliteStoreScript.new()
	reopened.open(_relative_path)
	var select_result: Dictionary = reopened.query("SELECT name FROM rollback_probe;")
	assert_eq(select_result["rows"].size(), 0, "no partial row exists after the rolled-back transaction")
	reopened.close()


func test_unsupported_user_version_fails_closed_without_mutating_db() -> void:
	var store: SqliteStore = SqliteStoreScript.new()
	store.open(_relative_path)
	store.query("CREATE TABLE IF NOT EXISTS version_probe (id INTEGER PRIMARY KEY);")
	store.query("PRAGMA user_version = 999;")
	store.close()

	var reopened: SqliteStore = SqliteStoreScript.new()
	var reopen_result: Dictionary = reopened.open(_relative_path)

	assert_eq(reopen_result["outcome"], SqliteStoreScript.OUTCOME_UNSUPPORTED_VERSION, "an unsupported user_version fails closed")
	assert_eq(reopen_result["user_version"], 999, "the rejection reports the actual on-disk version")
	assert_false(reopened.is_open(), "the store does not consider itself open after a fail-closed rejection")

	# Verify the DB was not mutated: version_probe table still exists and the
	# rejected version is unchanged (no silent migrate-forward to 1).
	var raw_check := SQLite.new()
	raw_check.path = "user://%s" % _relative_path
	raw_check.open_db()
	raw_check.query("PRAGMA user_version;")
	var on_disk_version: int = int(raw_check.query_result[0]["user_version"])
	raw_check.query("SELECT name FROM sqlite_master WHERE type='table' AND name='version_probe';")
	var table_still_present: bool = raw_check.query_result.size() == 1
	raw_check.close_db()

	assert_eq(on_disk_version, 999, "the on-disk user_version is untouched by the fail-closed open attempt")
	assert_true(table_still_present, "no destructive rewrite occurred; prior schema objects remain")


func test_parameter_bound_query_stores_and_retrieves_hostile_string_literally() -> void:
	var store: SqliteStore = SqliteStoreScript.new()
	store.open(_relative_path)
	store.query("CREATE TABLE IF NOT EXISTS injection_probe (id INTEGER PRIMARY KEY, name TEXT NOT NULL);")

	var hostile_value: String = "Robert'); DROP TABLE injection_probe; --"
	var insert_result: Dictionary = store.query_with_bindings(
		"INSERT INTO injection_probe (name) VALUES (?);", [hostile_value]
	)
	assert_eq(insert_result["outcome"], SqliteStoreScript.OUTCOME_OK, "parameter-bound insert of a hostile string succeeds: %s" % insert_result["detail"])

	var select_result: Dictionary = store.query("SELECT name FROM injection_probe;")
	assert_eq(select_result["rows"].size(), 1, "the table survives; no injected statement executed")
	assert_eq(select_result["rows"][0]["name"], hostile_value, "the hostile string is stored and retrieved literally, unmodified")

	store.close()


func test_open_rejects_res_path() -> void:
	var store: SqliteStore = SqliteStoreScript.new()
	var result: Dictionary = store.open("res://should_not_be_allowed.db")
	assert_eq(result["outcome"], SqliteStoreScript.OUTCOME_OPEN_FAILED, "a res:// path is rejected outright")
	assert_false(store.is_open(), "store is not open after a rejected res:// path")
