extends GutTest
## Public-seam tests for Slice 045's server-only Canon repository.

const SqliteStoreScript: Script = preload("res://server/sqlite_store.gd")
const CanonRepositoryScript: Script = preload("res://server/canon_repository.gd")
const FixturesScript: Script = preload("res://scripts/sector_blueprint_fixtures.gd")

var _relative_path: String = ""
var _store: SqliteStore = null
var _repository: CanonRepository = null
var _blueprint: Dictionary = {}


func before_each() -> void:
	_relative_path = "test_canon_repository_%d_%d.db" % [Time.get_ticks_usec(), randi()]
	_store = SqliteStoreScript.new()
	_store.open(_relative_path)
	_repository = CanonRepositoryScript.new(_store)
	_repository.ensure_schema()
	_blueprint = JSON.parse_string(FixturesScript.VALID)


func after_each() -> void:
	if _store != null and _store.is_open():
		_store.close()
	for suffix: String in ["", "-wal", "-shm", "-journal"]:
		var path: String = ProjectSettings.globalize_path("user://%s%s" % [_relative_path, suffix])
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func test_first_write_and_restart_recovery() -> void:
	var first: Dictionary = _repository.canonicalize_blueprint(_blueprint)
	assert_eq(first["outcome"], CanonRepositoryScript.OUTCOME_OK)
	var sector_id: String = _blueprint["sector_id"]
	var created_at: int = first["sector"]["created_at"]
	_store.close()

	_store = SqliteStoreScript.new()
	assert_eq(_store.open(_relative_path)["outcome"], SqliteStoreScript.OUTCOME_OK)
	_repository = CanonRepositoryScript.new(_store)
	assert_eq(_repository.ensure_schema()["outcome"], CanonRepositoryScript.OUTCOME_OK)
	var recovered: Dictionary = _repository.get_canonical_sector(sector_id)
	assert_eq(recovered["outcome"], CanonRepositoryScript.OUTCOME_OK)
	assert_eq(recovered["sector"]["created_at"], created_at)
	assert_eq(recovered["sector"]["blueprint"]["tiles"].size(), 3)


func test_same_blueprint_is_idempotent() -> void:
	assert_eq(_repository.canonicalize_blueprint(_blueprint)["outcome"], CanonRepositoryScript.OUTCOME_OK)
	var replay: Dictionary = _repository.canonicalize_blueprint(_blueprint.duplicate(true))
	assert_eq(replay["outcome"], CanonRepositoryScript.OUTCOME_IDEMPOTENT)


func test_conflicting_blueprint_cannot_replace_canon() -> void:
	assert_eq(_repository.canonicalize_blueprint(_blueprint)["outcome"], CanonRepositoryScript.OUTCOME_OK)
	var conflicting: Dictionary = _blueprint.duplicate(true)
	conflicting["tiles"] = [{"x": 7, "y": 7, "kind": "floor"}]
	var result: Dictionary = _repository.canonicalize_blueprint(conflicting)
	assert_eq(result["outcome"], CanonRepositoryScript.OUTCOME_CONFLICT)
	var loaded: Dictionary = _repository.get_canonical_sector("sector-0-0")
	assert_eq(loaded["sector"]["blueprint"]["tiles"][0]["x"], 0)


func test_invalid_blueprint_is_rejected_before_storage() -> void:
	var invalid: Variant = JSON.parse_string(FixturesScript.WRONG_SCHEMA_VERSION)
	var result: Dictionary = _repository.canonicalize_blueprint(invalid)
	assert_eq(result["outcome"], CanonRepositoryScript.OUTCOME_INVALID_BLUEPRINT)
	assert_eq(_repository.get_canonical_sector("sector-0-0")["outcome"], CanonRepositoryScript.OUTCOME_NOT_FOUND)


func test_hostile_sector_id_is_stored_as_data() -> void:
	var hostile: Dictionary = _blueprint.duplicate(true)
	hostile["sector_id"] = "Robert'); DROP TABLE canon_sectors; --"
	var result: Dictionary = _repository.canonicalize_blueprint(hostile)
	assert_eq(result["outcome"], CanonRepositoryScript.OUTCOME_OK)
	assert_eq(_repository.get_canonical_sector(hostile["sector_id"])["outcome"], CanonRepositoryScript.OUTCOME_OK)