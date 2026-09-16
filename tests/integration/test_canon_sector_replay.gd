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
const FixturesScript: Script = preload("res://scripts/sector_blueprint_fixtures.gd")

var _relative_path: String = ""
var _store: SqliteStore = null
var _canon: CanonRepository = null
var _mutations: CanonMutationRepository = null
var _service: CanonMutationService = null


func before_each() -> void:
	_relative_path = "test_canon_sector_replay_%d_%d.db" % [Time.get_ticks_usec(), randi()]
	_store = SqliteStoreScript.new()
	_store.open(_relative_path)
	_canon = CanonRepositoryScript.new(_store)
	_canon.ensure_schema()
	_mutations = CanonMutationRepositoryScript.new(_store, _canon)
	_mutations.ensure_schema()
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
