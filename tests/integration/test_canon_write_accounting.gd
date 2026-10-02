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
