extends GutTest

const SqliteStoreScript: Script = preload("res://server/sqlite_store.gd")
const JourneyRepositoryScript: Script = preload("res://server/journey_repository.gd")
const JourneyRegistryScript: Script = preload("res://server/journey_registry.gd")

var _path: String
var _store: SqliteStore
var _repository: JourneyRepository


func before_each() -> void:
	_path = "test_journey_repository_%d_%d.db" % [Time.get_ticks_usec(), randi()]
	_store = SqliteStoreScript.new()
	assert_eq(_store.open(_path)["outcome"], SqliteStoreScript.OUTCOME_OK)
	_repository = JourneyRepositoryScript.new(_store)
	assert_eq(_repository.ensure_schema()["outcome"], JourneyRepositoryScript.OUTCOME_OK)


func after_each() -> void:
	if _store != null and _store.is_open():
		_store.close()
	for suffix: String in ["", "-wal", "-shm", "-journal"]:
		var path: String = ProjectSettings.globalize_path("user://%s%s" % [_path, suffix])
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func test_journey_position_and_disconnect_survive_restart() -> void:
	var registry: RefCounted = JourneyRegistryScript.new()
	registry.set_repository(_repository)
	var entered: Dictionary = registry.enter("character-1", 7, 100)
	assert_eq(entered["outcome"], JourneyRegistryScript.OUTCOME_OK)
	assert_eq(registry.checkpoint("character-1", Vector3(32.5, 0.0, -4.25), 110, "sector-1-0", 3, "geometry-hash")["outcome"], JourneyRegistryScript.OUTCOME_OK)
	assert_eq(registry.mark_disconnected("character-1", 7, 120)["outcome"], JourneyRegistryScript.OUTCOME_OK)
	_store.close()

	_store = SqliteStoreScript.new()
	assert_eq(_store.open(_path)["outcome"], SqliteStoreScript.OUTCOME_OK)
	_repository = JourneyRepositoryScript.new(_store)
	assert_eq(_repository.ensure_schema()["outcome"], JourneyRepositoryScript.OUTCOME_OK)
	var records: Dictionary = _repository.load_all()
	assert_eq(records["outcome"], JourneyRepositoryScript.OUTCOME_OK)
	var restored: RefCounted = JourneyRegistryScript.new()
	assert_eq(restored.restore_records(records["records"])["outcome"], JourneyRegistryScript.OUTCOME_OK)
	var reclaimed: Dictionary = restored.enter("character-1", 8, 121)
	assert_eq(reclaimed["outcome"], JourneyRegistryScript.OUTCOME_OK)
	assert_eq(reclaimed["kind"], "reclaim")
	assert_eq(reclaimed["journey_id"], entered["journey_id"])
	assert_eq(float(reclaimed["journey"]["position_x"]), 32.5)
	assert_eq(float(reclaimed["journey"]["position_z"]), -4.25)
	assert_eq(reclaimed["journey"]["sector_id"], "sector-1-0")
	assert_eq(int(reclaimed["journey"]["sector_revision"]), 3)
	assert_eq(reclaimed["journey"]["sector_geometry_hash"], "geometry-hash")


func test_expired_persisted_journey_is_deleted_after_reclaim_window() -> void:
	var registry: RefCounted = JourneyRegistryScript.new()
	registry.set_repository(_repository)
	var entered: Dictionary = registry.enter("character-2", 7, 100)
	registry.mark_disconnected("character-2", 7, 100)
	var cleaned: Array[Dictionary] = registry.cleanup(100 + JourneyRegistryScript.RECLAIM_WINDOW_SECONDS + 1)
	assert_eq(cleaned.size(), 1)
	assert_eq(cleaned[0]["journey_id"], entered["journey_id"])
	assert_eq(_repository.load_all()["records"].size(), 0)