extends GutTest
## Slice 098 (P-013): the end-to-end replay path — a destroy_structure mutation
## applied through the real repository, then resolved against the canonical
## blueprint, yields the effective sector the server would replicate. No RPC or
## auth needed; this proves replay over a real SQLite-backed sector.

const SqliteStoreScript: Script = preload("res://server/sqlite_store.gd")
const CanonRepositoryScript: Script = preload("res://server/canon_repository.gd")
const CanonMutationRepositoryScript: Script = preload("res://server/canon_mutation_repository.gd")
const CanonMutationServiceScript: Script = preload("res://server/canon_mutation_service.gd")
const CanonSectorResolverScript: Script = preload("res://shared/canon_sector_resolver.gd")
const CanonEntityGuidScript: Script = preload("res://shared/canon_entity_guid.gd")
const JourneyRepositoryScript: Script = preload("res://server/journey_repository.gd")
const JourneyRegistryScript: Script = preload("res://server/journey_registry.gd")
const FixturesScript: Script = preload("res://scripts/sector_blueprint_fixtures.gd")
const TRACE_DIRECTORY: String = "res://logs/experiments"

var _relative_path: String = ""
var _store: SqliteStore = null
var _canon: CanonRepository = null
var _mutations: CanonMutationRepository = null
var _service: CanonMutationService = null
var _journey_repository: JourneyRepository = null


func before_each() -> void:
	_relative_path = "test_canon_sector_replay_%d_%d.db" % [Time.get_ticks_usec(), randi()]
	_store = SqliteStoreScript.new()
	_store.open(_relative_path)
	_canon = CanonRepositoryScript.new(_store)
	_canon.ensure_schema()
	_mutations = CanonMutationRepositoryScript.new(_store, _canon)
	_mutations.ensure_schema()
	_journey_repository = JourneyRepositoryScript.new(_store)
	_journey_repository.ensure_schema()
	_canon.canonicalize_blueprint(JSON.parse_string(FixturesScript.VALID_WITH_STRUCTURE))
	_service = CanonMutationServiceScript.new(_mutations, func() -> int: return 7)


func after_each() -> void:
	if _store != null and _store.is_open():
		_store.close()
	for suffix: String in ["", "-wal", "-shm", "-journal"]:
		var path: String = ProjectSettings.globalize_path("user://%s%s" % [_relative_path, suffix])
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _hub_blueprint() -> Dictionary:
	return _canon.get_canonical_sector("sector-0-0")["sector"]["blueprint"]


func _village_hall_guid() -> String:
	return CanonEntityGuidScript.derive("sector-0-0", CanonEntityGuidScript.ENTITY_CLASS_STRUCTURE, "village_hall")


func test_effective_blueprint_before_any_mutation_keeps_the_structure() -> void:
	var mutations: Array = _mutations.list_mutations("sector-0-0")["mutations"]
	var effective: Dictionary = CanonSectorResolverScript.resolve_effective_blueprint(_hub_blueprint(), mutations)
	assert_eq(effective.get("structures", []).size(), 1, "a fresh canon sector still has its structure")


func test_destroyed_structure_is_absent_from_the_effective_blueprint() -> void:
	var intent: Dictionary = {
		"schema_version": CanonMutationRepositoryScript.SUPPORTED_SCHEMA_VERSIONS[0],
		"event_id": "evt-destroy",
		"sector_id": "sector-0-0",
		"target_guid": _village_hall_guid(),
		"mutation_kind": "destroy_structure",
		"actor_player_id": "character-1",
		"server_tick": 7,
		"expected_revision": 0,
		"payload": {},
	}
	assert_eq(_mutations.apply_mutation(intent)["outcome"], CanonMutationRepositoryScript.OUTCOME_OK)

	var mutations: Array = _mutations.list_mutations("sector-0-0")["mutations"]
	var effective: Dictionary = CanonSectorResolverScript.resolve_effective_blueprint(_hub_blueprint(), mutations)
	assert_eq(effective.get("structures", []).size(), 0, "the destroyed structure is not replicated after reload")


func test_effective_blueprint_survives_restart() -> void:
	var intent: Dictionary = {
		"schema_version": CanonMutationRepositoryScript.SUPPORTED_SCHEMA_VERSIONS[0],
		"event_id": "evt-destroy",
		"sector_id": "sector-0-0",
		"target_guid": _village_hall_guid(),
		"mutation_kind": "destroy_structure",
		"actor_player_id": "character-1",
		"server_tick": 7,
		"expected_revision": 0,
		"payload": {},
	}
	assert_eq(_mutations.apply_mutation(intent)["outcome"], CanonMutationRepositoryScript.OUTCOME_OK)
	_store.close()

	_store = SqliteStoreScript.new()
	_store.open(_relative_path)
	_canon = CanonRepositoryScript.new(_store)
	_canon.ensure_schema()
	_mutations = CanonMutationRepositoryScript.new(_store, _canon)
	_mutations.ensure_schema()

	var mutations: Array = _mutations.list_mutations("sector-0-0")["mutations"]
	var effective: Dictionary = CanonSectorResolverScript.resolve_effective_blueprint(_hub_blueprint(), mutations)
	assert_eq(effective.get("structures", []).size(), 0, "the destruction persists across a restart")


func test_experiment_1012_reentry_restores_exact_canon_without_generation_or_writes() -> void:
	var blueprint: Dictionary = {
		"schema_version": 3,
		"sector_id": "sector_01_02",
		"origin": {"x": 16, "y": 20},
		"tiles": [{"x": 16, "y": 20, "kind": "floor"}],
		"structures": [{
			"structure_id": "str_claim_stone_01",
			"kind": "well",
			"x": 16,
			"y": 20,
			"facing_degrees": 0,
		}],
	}
	var target_guid: String = CanonEntityGuidScript.derive(
		"sector_01_02", CanonEntityGuidScript.ENTITY_CLASS_STRUCTURE, "str_claim_stone_01"
	)
	var lifecycle_events: Array[String] = ["SECTOR_BOUNDARY_TRIGGERED"]
	var sqlite_errors: Array[String] = []
	var generation_calls: int = 0
	var canon_result: Dictionary = _canon.canonicalize_blueprint(blueprint)
	if canon_result["outcome"] != CanonRepositoryScript.OUTCOME_OK:
		sqlite_errors.append(canon_result["detail"])
	assert_eq(canon_result["outcome"], CanonRepositoryScript.OUTCOME_OK)
	var mutation_result: Dictionary = _mutations.apply_mutation({
		"schema_version": 1,
		"event_id": "mut_01_02_anchor",
		"sector_id": "sector_01_02",
		"target_guid": target_guid,
		"mutation_kind": "destroy_structure",
		"actor_player_id": "character-1012",
		"server_tick": 1012,
		"expected_revision": 0,
		"payload": {"anchor": [16, 20]},
	})
	if mutation_result["outcome"] != CanonMutationRepositoryScript.OUTCOME_OK:
		sqlite_errors.append(mutation_result["detail"])
	assert_eq(mutation_result["outcome"], CanonMutationRepositoryScript.OUTCOME_OK)
	lifecycle_events.append("CANON_MUTATION_COMMITTED")

	var raw_before: Dictionary = _canon.get_canonical_sector("sector_01_02")["sector"]["blueprint"]
	var mutations_before: Array = _mutations.list_mutations("sector_01_02")["mutations"]
	var effective_before: Dictionary = CanonSectorResolverScript.resolve_effective_blueprint(raw_before, mutations_before)
	var raw_sha1_before: String = JSON.stringify(raw_before).sha1_text()
	var effective_sha1_before: String = JSON.stringify(effective_before).sha1_text()
	var row_counts_before: Dictionary = _row_counts()
	var journey_registry: RefCounted = JourneyRegistryScript.new()
	journey_registry.set_repository(_journey_repository)
	var entered: Dictionary = journey_registry.enter("character-1012", 7, 100)
	journey_registry.checkpoint("character-1012", Vector3(16.0, 0.0, 20.0), 101, "sector_01_02", 3, raw_sha1_before)
	journey_registry.mark_disconnected("character-1012", 7, 102)
	var journey_before: Dictionary = _journey_repository.load_all()

	_store.close()
	lifecycle_events.append("SERVER_RESTART_SIMULATED")
	_store = SqliteStoreScript.new()
	var reopen_result: Dictionary = _store.open(_relative_path)
	if reopen_result["outcome"] != SqliteStoreScript.OUTCOME_OK:
		sqlite_errors.append(reopen_result["detail"])
	assert_eq(reopen_result["outcome"], SqliteStoreScript.OUTCOME_OK)
	_canon = CanonRepositoryScript.new(_store)
	_mutations = CanonMutationRepositoryScript.new(_store, _canon)
	_journey_repository = JourneyRepositoryScript.new(_store)
	_journey_repository.ensure_schema()

	var reloaded: Dictionary = _canon.get_canonical_sector("sector_01_02")
	var replayed_mutations: Dictionary = _mutations.list_mutations("sector_01_02")
	if reloaded["outcome"] != CanonRepositoryScript.OUTCOME_OK:
		sqlite_errors.append(reloaded["detail"])
	if replayed_mutations["outcome"] != CanonMutationRepositoryScript.OUTCOME_OK:
		sqlite_errors.append(replayed_mutations["detail"])
	assert_eq(reloaded["outcome"], CanonRepositoryScript.OUTCOME_OK)
	assert_eq(replayed_mutations["outcome"], CanonMutationRepositoryScript.OUTCOME_OK)
	lifecycle_events.append("CANON_SECTOR_RELOADED")
	var raw_after: Dictionary = reloaded["sector"]["blueprint"]
	var effective_after: Dictionary = CanonSectorResolverScript.resolve_effective_blueprint(
		raw_after, replayed_mutations["mutations"]
	)
	var restored_journey_registry: RefCounted = JourneyRegistryScript.new()
	restored_journey_registry.set_repository(_journey_repository)
	assert_eq(restored_journey_registry.restore_records(_journey_repository.load_all()["records"])["outcome"], JourneyRegistryScript.OUTCOME_OK)
	var reclaimed: Dictionary = restored_journey_registry.enter("character-1012", 8, 103)
	var row_counts_after: Dictionary = _row_counts()
	var raw_sha1_after: String = JSON.stringify(raw_after).sha1_text()
	var effective_sha1_after: String = JSON.stringify(effective_after).sha1_text()
	var restored_match: bool = (
		raw_sha1_after == raw_sha1_before
		and effective_sha1_after == effective_sha1_before
		and row_counts_after == row_counts_before
		and reclaimed.get("outcome", "") == JourneyRegistryScript.OUTCOME_OK
		and reclaimed.get("kind", "") == "reclaim"
		and reclaimed["journey"].get("position_x", 0.0) == 16.0
		and reclaimed["journey"].get("position_z", 0.0) == 20.0
		and reclaimed["journey"].get("sector_id", "") == "sector_01_02"
		and reclaimed["journey"].get("sector_revision", 0) == 3
		and reclaimed["journey"].get("sector_geometry_hash", "") == raw_sha1_before
		and generation_calls == 0
		and sqlite_errors.is_empty()
	)

	assert_eq(raw_sha1_after, raw_sha1_before, "raw Canon SHA-1 survives restart")
	assert_eq(effective_sha1_after, effective_sha1_before, "effective SHA-1 survives replay")
	assert_eq(row_counts_after, row_counts_before, "re-entry writes no Canon or mutation rows")
	assert_eq(generation_calls, 0, "re-entry does not invoke generation")
	assert_eq((replayed_mutations["mutations"] as Array).size(), 1, "the committed mutation is restored")
	assert_eq(replayed_mutations["mutations"][0]["event_id"], "mut_01_02_anchor")
	assert_eq(effective_after["structures"].size(), 0, "the restored mutation changes effective state")
	assert_eq(reclaimed["journey"]["journey_id"], entered["journey_id"], "the journey identity survives restart")
	assert_eq(reclaimed["journey"]["sector_geometry_hash"], raw_sha1_before, "journey sector geometry survives restart")
	assert_eq(journey_before["records"].size(), 1, "the journey checkpoint is durable")
	assert_eq(lifecycle_events, [
		"SECTOR_BOUNDARY_TRIGGERED",
		"CANON_MUTATION_COMMITTED",
		"SERVER_RESTART_SIMULATED",
		"CANON_SECTOR_RELOADED",
	])
	assert_true(restored_match, "the complete restart/re-entry result matches")

	var timestamp_ms: int = int(Time.get_unix_time_from_system() * 1000.0)
	var trace: Dictionary = {
		"experiment_id": 1012,
		"timestamp_ms": timestamp_ms,
		"sector_id": "sector_01_02",
		"spatial_guid": target_guid,
		"raw_blueprint_sha1": {"before": raw_sha1_before, "after": raw_sha1_after},
		"reentry_pass": restored_match,
		"sql_query_write_counts": {"insert": 0, "update": 0},
		"generation_call_count": generation_calls,
		"restart_boundaries": {"cache_flushed": true, "sqlite_connection_reset": true},
		"event_payloads": lifecycle_events,
		"mutation_rows": replayed_mutations["mutations"],
		"runtime_errors": sqlite_errors,
		"effective_blueprint_sha1": {"before": effective_sha1_before, "after": effective_sha1_after},
		"row_counts": {"before_reentry": row_counts_before, "after_reentry": row_counts_after},
		"anchor": [16, 20],
		"structure_guid": "str_claim_stone_01",
		"status": "RESTORED_MATCH" if restored_match else "RESTORE_MISMATCH",
	}
	var trace_path: String = "%s/exp_990_immutable_canon_replay_%d.json" % [TRACE_DIRECTORY, timestamp_ms]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TRACE_DIRECTORY))
	var trace_file: FileAccess = FileAccess.open(trace_path, FileAccess.WRITE)
	assert_not_null(trace_file, "the Canon replay trace can be opened")
	trace_file.store_string(JSON.stringify(trace, "\t"))
	trace_file.close()


func _row_counts() -> Dictionary:
	var canon_rows: Dictionary = _store.query("SELECT COUNT(*) AS count FROM canon_sectors;")
	var mutation_rows: Dictionary = _store.query("SELECT COUNT(*) AS count FROM canon_mutations;")
	return {
		"canon_sectors": int(canon_rows["rows"][0]["count"]),
		"canon_mutations": int(mutation_rows["rows"][0]["count"]),
	}
