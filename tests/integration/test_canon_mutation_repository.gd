extends GutTest
## Public-seam tests for Slice 050's server-only Canon mutation repository
## (P-013 dynamic world mutation tracking). Mutations are an append-only log on
## top of the immutable Slice 045 Canon sectors: idempotent by event_id,
## optimistic on a per-sector revision, and fail-closed at the boundary.

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
	_relative_path = "test_canon_mutation_repository_%d_%d.db" % [Time.get_ticks_usec(), randi()]
	_store = SqliteStoreScript.new()
	_store.open(_relative_path)
	_canon = CanonRepositoryScript.new(_store)
	_canon.ensure_schema()
	_mutations = CanonMutationRepositoryScript.new(_store, _canon)
	_mutations.ensure_schema()
	# Every test operates on an already-canonical sector-0-0 that carries one
	# addressable structure (village_hall), so mutations target a real entity.
	_canon.canonicalize_blueprint(JSON.parse_string(FixturesScript.VALID_WITH_STRUCTURE))


func _target_guid() -> String:
	return CanonEntityGuidScript.derive("sector-0-0", CanonEntityGuidScript.ENTITY_CLASS_STRUCTURE, "village_hall")


func after_each() -> void:
	if _store != null and _store.is_open():
		_store.close()
	for suffix: String in ["", "-wal", "-shm", "-journal"]:
		var path: String = ProjectSettings.globalize_path("user://%s%s" % [_relative_path, suffix])
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _event(overrides: Dictionary = {}) -> Dictionary:
	var event: Dictionary = {
		"schema_version": 1,
		"event_id": "evt-1",
		"sector_id": "sector-0-0",
		"target_guid": _target_guid(),
		"mutation_kind": "defeat_leader",
		"actor_player_id": "player-1",
		"server_tick": 12345,
		"expected_revision": 0,
		"payload": {"leader": "baron"},
	}
	for key: String in overrides:
		event[key] = overrides[key]
	return event


func test_fresh_canon_sector_has_revision_zero() -> void:
	var revision: Dictionary = _mutations.get_sector_revision("sector-0-0")
	assert_eq(revision["outcome"], CanonMutationRepositoryScript.OUTCOME_OK)
	assert_eq(revision["revision"], 0, "a canon sector with no mutations is at revision 0")


func test_first_mutation_applies_and_bumps_revision() -> void:
	var result: Dictionary = _mutations.apply_mutation(_event())
	assert_eq(result["outcome"], CanonMutationRepositoryScript.OUTCOME_OK)
	assert_eq(result["applied_revision"], 1, "the first mutation moves the sector to revision 1")
	assert_eq(_mutations.get_sector_revision("sector-0-0")["revision"], 1)


func test_mutation_replay_is_idempotent() -> void:
	assert_eq(_mutations.apply_mutation(_event())["outcome"], CanonMutationRepositoryScript.OUTCOME_OK)
	var replay: Dictionary = _mutations.apply_mutation(_event())
	assert_eq(replay["outcome"], CanonMutationRepositoryScript.OUTCOME_IDEMPOTENT)
	assert_eq(replay["applied_revision"], 1, "an idempotent replay returns the original revision")
	assert_eq(_mutations.get_sector_revision("sector-0-0")["revision"], 1, "a replay does not advance the revision")


func test_stale_expected_revision_is_rejected() -> void:
	assert_eq(_mutations.apply_mutation(_event())["outcome"], CanonMutationRepositoryScript.OUTCOME_OK)
	var stale: Dictionary = _event({"event_id": "evt-2", "expected_revision": 0})
	var result: Dictionary = _mutations.apply_mutation(stale)
	assert_eq(result["outcome"], CanonMutationRepositoryScript.OUTCOME_REVISION_MISMATCH)
	assert_eq(_mutations.get_sector_revision("sector-0-0")["revision"], 1, "a stale mutation cannot advance the revision")


func test_second_mutation_at_current_revision_applies() -> void:
	assert_eq(_mutations.apply_mutation(_event())["outcome"], CanonMutationRepositoryScript.OUTCOME_OK)
	var second: Dictionary = _event({"event_id": "evt-2", "expected_revision": 1})
	var result: Dictionary = _mutations.apply_mutation(second)
	assert_eq(result["outcome"], CanonMutationRepositoryScript.OUTCOME_OK)
	assert_eq(result["applied_revision"], 2)


func test_mutation_on_non_canon_sector_is_rejected() -> void:
	var orphan: Dictionary = _event({"event_id": "evt-orphan", "sector_id": "sector-9-9"})
	var result: Dictionary = _mutations.apply_mutation(orphan)
	assert_eq(result["outcome"], CanonMutationRepositoryScript.OUTCOME_SECTOR_NOT_CANON)


func test_mutation_against_unknown_target_is_rejected() -> void:
	var unknown: Dictionary = _event({"event_id": "evt-unknown", "target_guid": "structure-does-not-exist"})
	var result: Dictionary = _mutations.apply_mutation(unknown)
	assert_eq(result["outcome"], CanonMutationRepositoryScript.OUTCOME_TARGET_NOT_FOUND, "a mutation must address a real canonical entity")
	assert_eq(_mutations.get_sector_revision("sector-0-0")["revision"], 0, "a target-not-found mutation is not stored")


func test_reused_event_id_with_different_content_conflicts() -> void:
	assert_eq(_mutations.apply_mutation(_event())["outcome"], CanonMutationRepositoryScript.OUTCOME_OK)
	var forged: Dictionary = _event({"payload": {"leader": "impostor"}})
	var result: Dictionary = _mutations.apply_mutation(forged)
	assert_eq(result["outcome"], CanonMutationRepositoryScript.OUTCOME_CONFLICT)
	assert_eq(_mutations.get_sector_revision("sector-0-0")["revision"], 1)


func test_malformed_event_is_rejected_before_storage() -> void:
	assert_eq(_mutations.apply_mutation(_event({"mutation_kind": "not_a_kind"}))["outcome"], CanonMutationRepositoryScript.OUTCOME_INVALID_EVENT)
	assert_eq(_mutations.apply_mutation(_event({"server_tick": -1}))["outcome"], CanonMutationRepositoryScript.OUTCOME_INVALID_EVENT)
	assert_eq(_mutations.apply_mutation(_event({"expected_revision": -1}))["outcome"], CanonMutationRepositoryScript.OUTCOME_INVALID_EVENT)
	assert_eq(_mutations.apply_mutation(_event({"event_id": ""}))["outcome"], CanonMutationRepositoryScript.OUTCOME_INVALID_EVENT)
	var missing: Dictionary = _event()
	missing.erase("target_guid")
	assert_eq(_mutations.apply_mutation(missing)["outcome"], CanonMutationRepositoryScript.OUTCOME_INVALID_EVENT)
	assert_eq(_mutations.get_sector_revision("sector-0-0")["revision"], 0, "no rejected event is stored")


func test_non_dictionary_event_is_rejected() -> void:
	assert_eq(_mutations.apply_mutation("not-a-dict")["outcome"], CanonMutationRepositoryScript.OUTCOME_INVALID_EVENT)
	assert_eq(_mutations.apply_mutation(null)["outcome"], CanonMutationRepositoryScript.OUTCOME_INVALID_EVENT)


func test_restart_recovery_replays_mutation_history() -> void:
	assert_eq(_mutations.apply_mutation(_event())["outcome"], CanonMutationRepositoryScript.OUTCOME_OK)
	assert_eq(_mutations.apply_mutation(_event({"event_id": "evt-2", "expected_revision": 1}))["outcome"], CanonMutationRepositoryScript.OUTCOME_OK)
	_store.close()

	_store = SqliteStoreScript.new()
	assert_eq(_store.open(_relative_path)["outcome"], SqliteStoreScript.OUTCOME_OK)
	_canon = CanonRepositoryScript.new(_store)
	_canon.ensure_schema()
	_mutations = CanonMutationRepositoryScript.new(_store, _canon)
	assert_eq(_mutations.ensure_schema()["outcome"], CanonMutationRepositoryScript.OUTCOME_OK)

	assert_eq(_mutations.get_sector_revision("sector-0-0")["revision"], 2, "mutation history survives a restart")
	var history: Dictionary = _mutations.list_mutations("sector-0-0")
	assert_eq(history["outcome"], CanonMutationRepositoryScript.OUTCOME_OK)
	var rows: Array = history["mutations"]
	assert_eq(rows.size(), 2)
	assert_eq(rows[0]["event_id"], "evt-1")
	assert_eq(rows[0]["applied_revision"], 1)
	assert_eq(rows[1]["event_id"], "evt-2")
	assert_eq(rows[1]["applied_revision"], 2)


func test_hostile_actor_id_is_stored_as_data() -> void:
	# target_guid stays valid so the mutation is admitted; the injection string
	# rides in actor_player_id, which reaches the INSERT, proving binding safety.
	var hostile: Dictionary = _event({"actor_player_id": "x'); DROP TABLE canon_mutations; --"})
	assert_eq(_mutations.apply_mutation(hostile)["outcome"], CanonMutationRepositoryScript.OUTCOME_OK)
	var history: Dictionary = _mutations.list_mutations("sector-0-0")
	assert_eq(history["mutations"].size(), 1, "parameter binding stored the injection string as inert data")
	assert_eq(history["mutations"][0]["actor_player_id"], "x'); DROP TABLE canon_mutations; --")
