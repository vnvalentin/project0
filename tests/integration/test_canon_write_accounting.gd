extends GutTest
## Slice 1325: SqliteStore counts INSERT/UPDATE statements against the Canon
## tables per window, split by transaction outcome, so experiments observe real
## Canon writes instead of inferring them from row counts.

const SqliteStoreScript: Script = preload("res://server/sqlite_store.gd")
const CanonRepositoryScript: Script = preload("res://server/canon_repository.gd")
const CanonMutationRepositoryScript: Script = preload("res://server/canon_mutation_repository.gd")
const CanonEntityGuidScript: Script = preload("res://shared/canon_entity_guid.gd")
const FixturesScript: Script = preload("res://scripts/sector_blueprint_fixtures.gd")

var _relative_path: String = ""
var _store: SqliteStore = null
var _canon: CanonRepository = null
var _mutations: CanonMutationRepository = null


func before_each() -> void:
	_relative_path = "test_canon_write_accounting_%d_%d.db" % [Time.get_ticks_usec(), randi()]
	_store = SqliteStoreScript.new()
	_store.open(_relative_path)
	_canon = CanonRepositoryScript.new(_store)
	_canon.ensure_schema()
	_mutations = CanonMutationRepositoryScript.new(_store, _canon)
	_mutations.ensure_schema()


func after_each() -> void:
	if _store != null and _store.is_open():
		_store.close()
	for suffix: String in ["", "-wal", "-shm", "-journal"]:
		var path: String = ProjectSettings.globalize_path("user://%s%s" % [_relative_path, suffix])
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _unlock_event(event_id: String, expected_revision: int) -> Dictionary:
	return {
		"schema_version": 1, "event_id": event_id, "sector_id": "sector-0-0",
		"target_guid": CanonEntityGuidScript.derive("sector-0-0", CanonEntityGuidScript.ENTITY_CLASS_STRUCTURE, "gate-1"),
		"mutation_kind": "unlock_gate", "actor_player_id": "character-1",
		"server_tick": 7, "expected_revision": expected_revision, "payload": {"unlocked": true},
	}


func test_schema_setup_counts_no_canon_writes() -> void:
	var counters: Dictionary = _store.canon_write_counters()
	for window: String in ["attempted", "committed", "rolled_back", "failed"]:
		assert_eq(counters[window], {"canon_sectors": 0, "canon_mutations": 0}, window)


func test_committed_canon_writes_are_counted_per_table() -> void:
	_canon.canonicalize_blueprint(JSON.parse_string(FixturesScript.VALID_WITH_LOCKED_GATE))
	assert_eq(_mutations.apply_mutation(_unlock_event("evt-1", 0))["outcome"], CanonMutationRepositoryScript.OUTCOME_OK)
	var counters: Dictionary = _store.canon_write_counters()
	assert_eq(counters["committed"], {"canon_sectors": 1, "canon_mutations": 1})
	assert_eq(counters["rolled_back"], {"canon_sectors": 0, "canon_mutations": 0})


func test_idempotent_replay_and_reads_add_no_canon_writes() -> void:
	_canon.canonicalize_blueprint(JSON.parse_string(FixturesScript.VALID_WITH_LOCKED_GATE))
	_mutations.apply_mutation(_unlock_event("evt-1", 0))
	var before: Dictionary = _store.canon_write_counters()
	assert_eq(_mutations.apply_mutation(_unlock_event("evt-1", 0))["outcome"], CanonMutationRepositoryScript.OUTCOME_IDEMPOTENT)
	_canon.canonicalize_blueprint(JSON.parse_string(FixturesScript.VALID_WITH_LOCKED_GATE))
	_mutations.list_mutations("sector-0-0")
	_canon.get_canonical_sector("sector-0-0")
	assert_eq(_store.canon_write_counters()["attempted"], before["attempted"], "no Canon INSERT/UPDATE was attempted")


func test_rolled_back_canon_write_is_attempted_but_not_committed() -> void:
	_canon.canonicalize_blueprint(JSON.parse_string(FixturesScript.VALID_WITH_LOCKED_GATE))
	var result: Dictionary = _store.transaction(func() -> bool:
		_store.query_with_bindings(
			"INSERT INTO canon_mutations (event_id, sector_id, target_guid, mutation_kind, payload_json, actor_player_id, server_tick, expected_revision, applied_revision, schema_version, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
			["evt-rollback", "sector-0-0", "structure-x", "unlock_gate", "{}", "character-1", 1, 0, 1, 1, 0]
		)
		return false
	)
	assert_eq(result["outcome"], SqliteStoreScript.OUTCOME_TRANSACTION_FAILED)
	var counters: Dictionary = _store.canon_write_counters()
	assert_eq(counters["attempted"]["canon_mutations"], 1)
	assert_eq(counters["rolled_back"]["canon_mutations"], 1)
	assert_eq(counters["committed"]["canon_mutations"], 0)
	assert_eq(_mutations.list_mutations("sector-0-0")["mutations"].size(), 0, "rollback leaves no committed row")


func test_non_canon_writes_are_not_counted() -> void:
	_store.query("CREATE TABLE other_table (id INTEGER PRIMARY KEY);")
	_store.query_with_bindings("INSERT INTO other_table (id) VALUES (?);", [1])
	assert_eq(_store.canon_write_counters()["attempted"], {"canon_sectors": 0, "canon_mutations": 0})


func test_direct_statement_window_observes_insert_by_table() -> void:
	_store.query("CREATE TABLE accounting_probe (id INTEGER PRIMARY KEY, value TEXT);")
	assert_true(_store.has_method("start_dml_observation"), "explicit observation window public seam")
	if not _store.has_method("start_dml_observation"):
		return
	var initial: Dictionary = _store.call("start_dml_observation")
	assert_eq(initial["observation_status"], "OBSERVED")
	_store.query_with_bindings("INSERT INTO accounting_probe (id, value) VALUES (?, ?);", [1, "a"])
	var report: Dictionary = _store.call("dml_statement_counters")
	assert_eq(report["observation_status"], "OBSERVED")
	assert_eq(report["totals"]["attempted"]["insert"], 1)
	assert_eq(report["by_table"]["accounting_probe"]["committed"]["insert"], 1)
	assert_eq(initial["totals"]["attempted"]["insert"], 0, "prior snapshot is immutable")


func test_closed_window_start_returns_complete_invalid_report() -> void:
	_store.close()
	var report: Dictionary = _store.start_dml_observation()
	assert_eq(report["observation_status"], "NOT_OBSERVED")
	assert_true(report.has("totals"), "failure has the same bounded report shape")
	if report.has("totals"):
		assert_eq(report["totals"], "NOT_OBSERVED")


func test_all_operations_dispositions_and_zero_row_statements() -> void:
	_store.query("CREATE TABLE accounting_probe (id INTEGER PRIMARY KEY, value TEXT);")
	_store.query("CREATE TABLE second_probe (id INTEGER PRIMARY KEY);")
	_store.start_dml_observation()
	_store.query_with_bindings("INSERT INTO accounting_probe VALUES (?, ?);", [1, "a"])
	_store.query_with_bindings("REPLACE INTO accounting_probe VALUES (?, ?);", [1, "b"])
	_store.query_with_bindings("UPDATE accounting_probe SET value = ? WHERE id = ?;", ["c", 99])
	_store.query_with_bindings("DELETE FROM accounting_probe WHERE id = ?;", [99])
	_store.transaction(func() -> bool:
		_store.query_with_bindings("INSERT INTO second_probe VALUES (?);", [1])
		return true
	)
	_store.transaction(func() -> bool:
		_store.query_with_bindings("DELETE FROM accounting_probe WHERE id = ?;", [1])
		_store.query_with_bindings("INSERT INTO second_probe VALUES (?);", [2])
		return false
	)
	assert_eq(_store.query_with_bindings("INSERT INTO accounting_probe VALUES (?, ?);", [1, "duplicate"])["outcome"], SqliteStoreScript.OUTCOME_QUERY_FAILED)
	var report: Dictionary = _store.dml_statement_counters()
	assert_eq(report["observation_status"], "OBSERVED")
	assert_eq(report["totals"]["attempted"], {"insert": 4, "replace": 1, "update": 1, "delete": 2})
	assert_eq(report["totals"]["committed"], {"insert": 2, "replace": 1, "update": 1, "delete": 1})
	assert_eq(report["totals"]["rolled_back"], {"insert": 1, "replace": 0, "update": 0, "delete": 1})
	assert_eq(report["by_table"]["accounting_probe"]["failed"]["insert"], 1)
	assert_eq(report["by_table"]["second_probe"]["committed"]["insert"], 1)
	assert_eq(report["native_row_effects"], "NOT_OBSERVED", "zero-row UPDATE/DELETE are statements, not affected rows")


func test_unknown_sql_keeps_known_counts_and_execution_and_window_history() -> void:
	_store.query("CREATE TABLE accounting_probe (id INTEGER PRIMARY KEY);")
	_store.start_dml_observation()
	_store.query_with_bindings("INSERT INTO accounting_probe VALUES (?);", [1])
	assert_eq(_store.query("WITH incoming AS (SELECT 2 AS id) INSERT INTO accounting_probe SELECT id FROM incoming;")["outcome"], SqliteStoreScript.OUTCOME_OK)
	var unknown: Dictionary = _store.dml_statement_counters()
	assert_eq(unknown["observation_status"], "NOT_OBSERVED")
	assert_eq(unknown["totals"], "NOT_OBSERVED")
	assert_eq(unknown["by_table"], "NOT_OBSERVED")
	assert_eq(unknown["partial_counts"]["totals"]["committed"]["insert"], 1)
	assert_eq(_store.query("SELECT COUNT(*) AS n FROM accounting_probe;")["rows"][0]["n"], 2, "unsupported observation preserved SQL execution")
	var next: Dictionary = _store.start_dml_observation()
	assert_eq(next["observation_status"], "OBSERVED")
	assert_eq(next["window_id"], unknown["window_id"] + 1)
	assert_eq(next["previous_windows"][0]["observation_status"], "NOT_OBSERVED")
	assert_eq(unknown["partial_counts"]["totals"]["committed"]["insert"], 1, "old snapshot remains immutable")


func test_multi_statement_and_trigger_schema_cannot_report_complete_counts() -> void:
	_store.query("CREATE TABLE accounting_probe (id INTEGER PRIMARY KEY);")
	_store.start_dml_observation()
	assert_eq(_store.query("INSERT INTO accounting_probe VALUES (1); INSERT INTO accounting_probe VALUES (2);")["outcome"], SqliteStoreScript.OUTCOME_OK)
	assert_eq(_store.dml_statement_counters()["observation_status"], "NOT_OBSERVED")
	_store.query("CREATE TABLE trigger_probe (id INTEGER PRIMARY KEY);")
	_store.query("CREATE TRIGGER accounting_trigger AFTER INSERT ON accounting_probe BEGIN INSERT INTO trigger_probe VALUES (new.id); END;")
	assert_eq(_store.start_dml_observation()["observation_status"], "NOT_OBSERVED")
	_store.query_with_bindings("INSERT INTO accounting_probe VALUES (?);", [3])
	var report: Dictionary = _store.dml_statement_counters()
	assert_eq(report["totals"], "NOT_OBSERVED")
	assert_true(report["reasons"].has("trigger_or_view_schema"))
	assert_eq(report["partial_counts"]["by_table"]["accounting_probe"]["committed"]["insert"], 1)
	assert_eq(_store.query("SELECT COUNT(*) AS n FROM trigger_probe;")["rows"][0]["n"], 1)


func test_quoted_values_and_connection_scope() -> void:
	_store.query("CREATE TABLE accounting_probe (id INTEGER PRIMARY KEY, value TEXT);")
	var initial: Dictionary = _store.start_dml_observation()
	assert_eq(_store.query("INSERT INTO accounting_probe VALUES (1, 'text; and ''quoted''');")["outcome"], SqliteStoreScript.OUTCOME_OK)
	assert_eq(_store.dml_statement_counters()["totals"]["committed"]["insert"], 1)
	_store.close()
	assert_eq(_store.dml_statement_counters()["observation_status"], "NOT_OBSERVED")
	assert_eq(_store.open(_relative_path)["outcome"], SqliteStoreScript.OUTCOME_OK)
	var reopened: Dictionary = _store.start_dml_observation()
	assert_ne(reopened["connection_id"], initial["connection_id"])
	assert_eq(reopened["previous_windows"][0]["observation_status"], "NOT_OBSERVED")


func test_temporary_schema_is_explicitly_outside_qualified_scope() -> void:
	_store.query("CREATE TEMP TABLE accounting_probe (id INTEGER PRIMARY KEY);")
	var report: Dictionary = _store.start_dml_observation()
	assert_eq(report["observation_status"], "NOT_OBSERVED", "table names cannot conflate main and temp schemas")


func test_unknown_rollback_and_mid_transaction_start_never_reset_counts() -> void:
	_store.query("CREATE TABLE accounting_probe (id INTEGER PRIMARY KEY);")
	var initial: Dictionary = _store.start_dml_observation()
	var transaction_result: Dictionary = _store.transaction(func() -> bool:
		_store.query_with_bindings("INSERT INTO accounting_probe VALUES (?);", [1])
		var rejected: Dictionary = _store.start_dml_observation()
		assert_eq(rejected["window_id"], initial["window_id"], "invalid start cannot erase active transaction evidence")
		assert_eq(rejected["observation_status"], "NOT_OBSERVED")
		_store.query_with_bindings("INSERT OR ROLLBACK INTO accounting_probe VALUES (?);", [1])
		return false
	)
	assert_eq(transaction_result["outcome"], SqliteStoreScript.OUTCOME_TRANSACTION_FAILED)
	var report: Dictionary = _store.dml_statement_counters()
	assert_eq(report["totals"], "NOT_OBSERVED")
	assert_true(report["reasons"].has("transaction_disposition_not_observed"))
	assert_eq(report["partial_counts"]["totals"]["attempted"]["insert"], 2)
	assert_eq(report["partial_counts"]["totals"]["failed"]["insert"], 1)
	assert_eq(report["partial_counts"]["totals"]["rolled_back"]["insert"], 0, "no inferred successful ROLLBACK")
	assert_eq(_store.query("SELECT id FROM accounting_probe;")["rows"], [], "native OR ROLLBACK acted even though explicit rollback returned failure")


func test_foreign_key_side_effects_and_raw_transaction_are_incomplete() -> void:
	_store.query("CREATE TABLE accounting_parent (id INTEGER PRIMARY KEY);")
	_store.query("CREATE TABLE accounting_child (id INTEGER PRIMARY KEY, parent_id INTEGER REFERENCES accounting_parent(id) ON DELETE CASCADE);")
	var report: Dictionary = _store.start_dml_observation()
	assert_eq(report["observation_status"], "NOT_OBSERVED")
	assert_true(report["reasons"].has("foreign_key_side_effects"))
	_store.query("DROP TABLE accounting_child;")
	_store.start_dml_observation()
	assert_eq(_store.query("BEGIN;")["outcome"], SqliteStoreScript.OUTCOME_OK)
	_store.query_with_bindings("INSERT INTO accounting_parent VALUES (?);", [1])
	assert_eq(_store.query("ROLLBACK;")["outcome"], SqliteStoreScript.OUTCOME_OK)
	report = _store.dml_statement_counters()
	assert_eq(report["totals"], "NOT_OBSERVED")
	assert_eq(report["partial_counts"]["totals"]["committed"]["insert"], 0, "native transaction is never mistaken for autocommit")


func test_read_whitespace_and_active_schema_change_are_observed_honestly() -> void:
	_store.query("CREATE TABLE accounting_probe (id INTEGER PRIMARY KEY);")
	_store.start_dml_observation()
	assert_eq(_store.query("SELECT\n COUNT(*) AS n FROM accounting_probe;")["outcome"], SqliteStoreScript.OUTCOME_OK)
	assert_eq(_store.dml_statement_counters()["observation_status"], "OBSERVED", "read-only SELECT whitespace is supported")
	_store.query("CREATE INDEX accounting_idx ON accounting_probe (id);")
	assert_eq(_store.dml_statement_counters()["observation_status"], "NOT_OBSERVED")


func test_read_only_windows_report_zero_without_resetting_legacy_canon_counters() -> void:
	_canon.canonicalize_blueprint(JSON.parse_string(FixturesScript.VALID_WITH_LOCKED_GATE))
	var legacy: Dictionary = _store.canon_write_counters()
	_store.start_dml_observation()
	_canon.get_canonical_sector("sector-0-0")
	_mutations.list_mutations("sector-0-0")
	var report: Dictionary = _store.dml_statement_counters()
	assert_eq(report["observation_status"], "OBSERVED")
	for window: String in ["attempted", "committed", "rolled_back", "failed"]:
		assert_eq(report["totals"][window], {"insert": 0, "replace": 0, "update": 0, "delete": 0})
	_store.start_dml_observation()
	assert_eq(_store.canon_write_counters(), legacy, "neither starting nor snapshotting observation resets lifetime Canon counters")


func test_query_failure_latch_rolls_back_observed_successful_attempts() -> void:
	_store.query("CREATE TABLE accounting_probe (id INTEGER PRIMARY KEY);")
	_store.start_dml_observation()
	var result: Dictionary = _store.transaction(func() -> bool:
		_store.query_with_bindings("INSERT INTO accounting_probe VALUES (?);", [1])
		_store.query_with_bindings("INSERT INTO accounting_probe VALUES (?);", [1])
		return true
	)
	assert_eq(result["outcome"], SqliteStoreScript.OUTCOME_TRANSACTION_FAILED, "accepted #1379 contract, regardless of callback bool")
	var report: Dictionary = _store.dml_statement_counters()
	assert_eq(report["observation_status"], "OBSERVED")
	assert_eq(report["by_table"]["accounting_probe"]["attempted"]["insert"], 2)
	assert_eq(report["by_table"]["accounting_probe"]["failed"]["insert"], 1)
	assert_eq(report["by_table"]["accounting_probe"]["rolled_back"]["insert"], 1)
	assert_eq(report["by_table"]["accounting_probe"]["committed"]["insert"], 0)
