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

## #1411 public derived metadata must preserve the accepted persisted-Canon hash.
func test_checkpoint_metadata_matches_existing_canon_read() -> void:
	assert_eq(_repository.canonicalize_blueprint(_blueprint)["outcome"], CanonRepositoryScript.OUTCOME_OK)
	var sector_id: String = String(_blueprint["sector_id"])
	var existing: Dictionary = _repository.get_canonical_sector(sector_id)
	assert_eq(existing["outcome"], CanonRepositoryScript.OUTCOME_OK)
	assert_true(_repository.has_method("get_checkpoint_metadata"), "Canon exposes authoritative derived checkpoint metadata")
	if not _repository.has_method("get_checkpoint_metadata"):
		return
	var expected_sector: Dictionary = existing["sector"]
	var metadata: Dictionary = _repository.call("get_checkpoint_metadata", sector_id)
	assert_eq(metadata["outcome"], CanonRepositoryScript.OUTCOME_OK)
	assert_eq(metadata["sector_revision"], int(expected_sector["schema_version"]))
	assert_eq(metadata["sector_geometry_hash"], JSON.stringify(expected_sector["blueprint"]).md5_text(), "existing public read is the compatibility oracle")
	var repeated: Dictionary = _repository.call("get_checkpoint_metadata", sector_id)
	assert_eq(repeated, metadata, "repeated unchanged authoritative read preserves the result")


func test_checkpoint_metadata_refreshes_schema_only_change_after_reopen() -> void:
	assert_eq(_repository.canonicalize_blueprint(_blueprint)["outcome"], CanonRepositoryScript.OUTCOME_OK)
	var sector_id: String = String(_blueprint["sector_id"])
	assert_true(_repository.has_method("get_checkpoint_metadata"), "Canon exposes authoritative derived checkpoint metadata")
	if not _repository.has_method("get_checkpoint_metadata"):
		return
	var original: Dictionary = _repository.call("get_checkpoint_metadata", sector_id)
	var next_revision: int = int(original["sector_revision"]) + 1
	_store.close()
	var writer: SqliteStore = SqliteStoreScript.new()
	assert_eq(writer.open(_relative_path)["outcome"], SqliteStoreScript.OUTCOME_OK)
	var update: Dictionary = writer.query_with_bindings(
		"UPDATE canon_sectors SET schema_version = ? WHERE sector_id = ?;",
		[next_revision, sector_id]
	)
	assert_eq(update["outcome"], SqliteStoreScript.OUTCOME_OK)
	writer.close()
	assert_eq(_store.open(_relative_path)["outcome"], SqliteStoreScript.OUTCOME_OK)
	var refreshed: Dictionary = _repository.call("get_checkpoint_metadata", sector_id)
	assert_eq(refreshed["outcome"], CanonRepositoryScript.OUTCOME_OK)
	assert_eq(refreshed["sector_revision"], next_revision)
	assert_eq(refreshed["sector_geometry_hash"], original["sector_geometry_hash"])


func test_checkpoint_metadata_refreshes_equivalent_reordered_json() -> void:
	assert_eq(_repository.canonicalize_blueprint(_blueprint)["outcome"], CanonRepositoryScript.OUTCOME_OK)
	var sector_id: String = String(_blueprint["sector_id"])
	assert_true(_repository.has_method("get_checkpoint_metadata"), "Canon exposes authoritative derived checkpoint metadata")
	if not _repository.has_method("get_checkpoint_metadata"):
		return
	var original: Dictionary = _repository.call("get_checkpoint_metadata", sector_id)
	var reversed_keys: Array = _blueprint.keys()
	reversed_keys.reverse()
	var reordered_blueprint: Dictionary = {}
	for key: Variant in reversed_keys:
		reordered_blueprint[key] = _blueprint[key]
	var reordered_json: String = JSON.stringify(reordered_blueprint, "\t", false)
	_store.close()
	var writer: SqliteStore = SqliteStoreScript.new()
	assert_eq(writer.open(_relative_path)["outcome"], SqliteStoreScript.OUTCOME_OK)
	var update: Dictionary = writer.query_with_bindings(
		"UPDATE canon_sectors SET blueprint_json = ? WHERE sector_id = ?;",
		[reordered_json, sector_id]
	)
	assert_eq(update["outcome"], SqliteStoreScript.OUTCOME_OK)
	writer.close()
	assert_eq(_store.open(_relative_path)["outcome"], SqliteStoreScript.OUTCOME_OK)
	var refreshed: Dictionary = _repository.call("get_checkpoint_metadata", sector_id)
	var legacy_read: Dictionary = _repository.get_canonical_sector(sector_id)
	assert_eq(refreshed["outcome"], CanonRepositoryScript.OUTCOME_OK)
	assert_eq(refreshed["sector_revision"], original["sector_revision"])
	assert_eq(refreshed["sector_geometry_hash"], JSON.stringify(legacy_read["sector"]["blueprint"]).md5_text())
	assert_eq(refreshed["sector_geometry_hash"], original["sector_geometry_hash"])


func test_checkpoint_metadata_does_not_outlive_missing_canon() -> void:
	assert_eq(_repository.canonicalize_blueprint(_blueprint)["outcome"], CanonRepositoryScript.OUTCOME_OK)
	var sector_id: String = String(_blueprint["sector_id"])
	assert_true(_repository.has_method("get_checkpoint_metadata"), "Canon exposes authoritative derived checkpoint metadata")
	if not _repository.has_method("get_checkpoint_metadata"):
		return
	assert_eq(_repository.call("get_checkpoint_metadata", sector_id)["outcome"], CanonRepositoryScript.OUTCOME_OK)
	var delete: Dictionary = _store.query_with_bindings("DELETE FROM canon_sectors WHERE sector_id = ?;", [sector_id])
	assert_eq(delete["outcome"], SqliteStoreScript.OUTCOME_OK)
	assert_eq(_repository.call("get_checkpoint_metadata", sector_id)["outcome"], CanonRepositoryScript.OUTCOME_NOT_FOUND)


func test_checkpoint_metadata_uses_canon_created_after_initial_miss() -> void:
	var sector_id: String = String(_blueprint["sector_id"])
	assert_true(_repository.has_method("get_checkpoint_metadata"), "Canon exposes authoritative derived checkpoint metadata")
	if not _repository.has_method("get_checkpoint_metadata"):
		return
	assert_eq(_repository.call("get_checkpoint_metadata", sector_id)["outcome"], CanonRepositoryScript.OUTCOME_NOT_FOUND)
	assert_eq(_repository.canonicalize_blueprint(_blueprint)["outcome"], CanonRepositoryScript.OUTCOME_OK)
	var metadata: Dictionary = _repository.call("get_checkpoint_metadata", sector_id)
	assert_eq(metadata["outcome"], CanonRepositoryScript.OUTCOME_OK)
	assert_eq(metadata["sector_revision"], int(_blueprint["schema_version"]))
	assert_eq(metadata["sector_geometry_hash"], JSON.stringify(_blueprint).md5_text())


func test_checkpoint_metadata_preserves_empty_not_open_and_query_failed_results() -> void:
	assert_true(_repository.has_method("get_checkpoint_metadata"), "Canon exposes authoritative derived checkpoint metadata")
	if not _repository.has_method("get_checkpoint_metadata"):
		return
	assert_eq(_repository.call("get_checkpoint_metadata", "")["outcome"], CanonRepositoryScript.OUTCOME_NOT_FOUND)
	assert_eq(_repository.canonicalize_blueprint(_blueprint)["outcome"], CanonRepositoryScript.OUTCOME_OK)
	var sector_id: String = String(_blueprint["sector_id"])
	assert_eq(_repository.call("get_checkpoint_metadata", sector_id)["outcome"], CanonRepositoryScript.OUTCOME_OK)
	assert_eq(_store.close()["outcome"], SqliteStoreScript.OUTCOME_OK)
	assert_eq(_repository.call("get_checkpoint_metadata", sector_id)["outcome"], SqliteStoreScript.OUTCOME_NOT_OPEN)
	assert_eq(_store.open(_relative_path)["outcome"], SqliteStoreScript.OUTCOME_OK)
	assert_eq(_store.query("DROP TABLE canon_sectors;")["outcome"], SqliteStoreScript.OUTCOME_OK)
	assert_eq(_repository.call("get_checkpoint_metadata", sector_id)["outcome"], SqliteStoreScript.OUTCOME_QUERY_FAILED)
	assert_eq(_repository.get_canonical_sector(sector_id)["outcome"], SqliteStoreScript.OUTCOME_QUERY_FAILED)


func test_checkpoint_metadata_handles_valid_oversized_blueprint() -> void:
	var oversized: Dictionary = JSON.parse_string(FixturesScript.VALID_WITH_STRUCTURE)
	var long_structure_id: String = "x".repeat(4 * 1024 * 1024 + 1)
	oversized["structures"][0]["structure_id"] = long_structure_id
	assert_eq(_repository.canonicalize_blueprint(oversized)["outcome"], CanonRepositoryScript.OUTCOME_OK)
	var sector_id: String = String(oversized["sector_id"])
	var legacy_read: Dictionary = _repository.get_canonical_sector(sector_id)
	assert_eq(legacy_read["outcome"], CanonRepositoryScript.OUTCOME_OK)
	assert_true(_repository.has_method("get_checkpoint_metadata"), "Canon exposes authoritative derived checkpoint metadata")
	if not _repository.has_method("get_checkpoint_metadata"):
		return
	var expected_hash: String = JSON.stringify(legacy_read["sector"]["blueprint"]).md5_text()
	var first: Dictionary = _repository.call("get_checkpoint_metadata", sector_id)
	var repeated: Dictionary = _repository.call("get_checkpoint_metadata", sector_id)
	assert_eq(first["outcome"], CanonRepositoryScript.OUTCOME_OK)
	assert_eq(first["sector_geometry_hash"], expected_hash)
	assert_eq(repeated, first)
