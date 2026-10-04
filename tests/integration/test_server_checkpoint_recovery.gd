extends GutTest

const ServerMainScript: Script = preload("res://server/server_main.gd")
const PlayerStateScript: Script = preload("res://server/server_player_state.gd")
const SqliteStoreScript: Script = preload("res://server/sqlite_store.gd")
const CanonRepositoryScript: Script = preload("res://server/canon_repository.gd")
const JourneyRepositoryScript: Script = preload("res://server/journey_repository.gd")
const JourneyRegistryScript: Script = preload("res://server/journey_registry.gd")
const FixturesScript: Script = preload("res://scripts/sector_blueprint_fixtures.gd")

class CheckpointServer extends "res://server/server_main.gd":
	pass

var _relative_path: String
var _canon_path: String
var _store: SqliteStore
var _canon_store: SqliteStore
var _journey_repository: JourneyRepository
var _server: CheckpointServer
var _registry: JourneyRegistry
var _player_state: Node


func before_each() -> void:
	var stamp: String = "%d_%d" % [Time.get_ticks_usec(), randi()]
	_relative_path = "test_server_checkpoint_recovery_%s.db" % stamp
	_canon_path = "test_server_checkpoint_recovery_canon_%s.db" % stamp
	_store = SqliteStoreScript.new()
	assert_eq(_store.open(_relative_path)["outcome"], SqliteStoreScript.OUTCOME_OK)

	var canon: CanonRepository = CanonRepositoryScript.new(_store)
	assert_eq(canon.ensure_schema()["outcome"], CanonRepositoryScript.OUTCOME_OK)
	var blueprint: Dictionary = JSON.parse_string(FixturesScript.VALID)
	assert_eq(canon.canonicalize_blueprint(blueprint)["outcome"], CanonRepositoryScript.OUTCOME_OK)

	_journey_repository = JourneyRepositoryScript.new(_store)
	assert_eq(_journey_repository.ensure_schema()["outcome"], JourneyRepositoryScript.OUTCOME_OK)
	_registry = JourneyRegistryScript.new()
	_registry.set_repository(_journey_repository)
	assert_eq(_registry.enter("checkpoint-character", 7, int(Time.get_unix_time_from_system()))["outcome"], JourneyRegistryScript.OUTCOME_OK)

	_server = CheckpointServer.new()
	_server._canon_repository = canon
	_server._journey_repository = _journey_repository
	_server._journey_registry = _registry
	_player_state = PlayerStateScript.new()
	_player_state.character_id = "checkpoint-character"
	_server._player_states[7] = _player_state


func after_each() -> void:
	if _server != null:
		_server.free()
	if _player_state != null:
		_player_state.free()
	for store: SqliteStore in [_store, _canon_store]:
		if store != null and store.is_open():
			store.close()
	for relative_path: String in [_relative_path, _canon_path]:
		for suffix: String in ["", "-wal", "-shm", "-journal"]:
			var path: String = ProjectSettings.globalize_path("user://%s%s" % [relative_path, suffix])
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)


func _load_journey(repository: JourneyRepository, journey_id: String) -> Dictionary:
	var loaded: Dictionary = repository.load_all()
	assert_eq(loaded["outcome"], JourneyRepositoryScript.OUTCOME_OK)
	assert_eq((loaded["records"] as Array).size(), 1)
	if (loaded["records"] as Array).is_empty():
		return {}
	var record: Dictionary = loaded["records"][0]
	assert_eq(record["journey_id"], journey_id)
	return record


func _assert_checkpoint_record(record: Dictionary, position: Vector3, expected_revision: int, expected_hash: String, earliest_checkpoint: int, latest_checkpoint: int) -> void:
	assert_eq(record["character_id"], "checkpoint-character")
	assert_eq(record["lifecycle_status"], "active")
	assert_eq(int(record["peer_id"]), 7)
	assert_eq(float(record["position_x"]), position.x)
	assert_eq(float(record["position_y"]), position.y)
	assert_eq(float(record["position_z"]), position.z)
	assert_eq(record["sector_id"], "sector-0-0")
	assert_eq(int(record["sector_revision"]), expected_revision)
	assert_eq(record["sector_geometry_hash"], expected_hash)
	assert_gte(int(record["last_checkpoint_at"]), earliest_checkpoint)
	assert_lte(int(record["last_checkpoint_at"]), latest_checkpoint)
	assert_eq(int(record["last_disconnected_at"]), 0)


func test_checkpoint_metadata_flows_through_shared_and_dedicated_canon_to_recovery() -> void:
	var blueprint: Dictionary = JSON.parse_string(FixturesScript.VALID)
	var expected_revision: int = int(blueprint["schema_version"])
	var expected_hash: String = JSON.stringify(blueprint).md5_text()
	var journey_id: String = String(_registry.active_journey_id("checkpoint-character", 7))
	assert_ne(journey_id, "")

	var first_position := Vector3(12.0, 1.0, 20.0)
	var first_started: int = int(Time.get_unix_time_from_system())
	_server._checkpoint_journey(7, first_position)
	var first_saved_at: int = int(Time.get_unix_time_from_system())
	_assert_checkpoint_record(_load_journey(_journey_repository, journey_id), first_position, expected_revision, expected_hash, first_started, first_saved_at)

	_canon_store = SqliteStoreScript.new()
	assert_eq(_canon_store.open(_canon_path)["outcome"], SqliteStoreScript.OUTCOME_OK)
	var dedicated_canon: CanonRepository = CanonRepositoryScript.new(_canon_store)
	assert_eq(dedicated_canon.ensure_schema()["outcome"], CanonRepositoryScript.OUTCOME_OK)
	assert_eq(dedicated_canon.canonicalize_blueprint(blueprint)["outcome"], CanonRepositoryScript.OUTCOME_OK)
	_server._canon_repository = dedicated_canon

	var final_position := Vector3(13.0, 2.0, 21.0)
	var final_started: int = int(Time.get_unix_time_from_system())
	_server._checkpoint_journey(7, final_position)
	var final_saved_at: int = int(Time.get_unix_time_from_system())
	_assert_checkpoint_record(_load_journey(_journey_repository, journey_id), final_position, expected_revision, expected_hash, final_started, final_saved_at)

	assert_eq(_store.close()["outcome"], SqliteStoreScript.OUTCOME_OK)
	assert_eq(_store.open(_relative_path)["outcome"], SqliteStoreScript.OUTCOME_OK)
	var recovered_repository: JourneyRepository = JourneyRepositoryScript.new(_store)
	assert_eq(recovered_repository.ensure_schema()["outcome"], JourneyRepositoryScript.OUTCOME_OK)
	var persisted: Dictionary = _load_journey(recovered_repository, journey_id)
	_assert_checkpoint_record(persisted, final_position, expected_revision, expected_hash, final_started, final_saved_at)
	var recovered_registry: JourneyRegistry = JourneyRegistryScript.new()
	recovered_registry.set_repository(recovered_repository)
	assert_eq(recovered_registry.restore_records([persisted])["outcome"], JourneyRegistryScript.OUTCOME_OK)
	var reclaimed: Dictionary = recovered_registry.enter("checkpoint-character", 8, int(Time.get_unix_time_from_system()))
	assert_eq(reclaimed["outcome"], JourneyRegistryScript.OUTCOME_OK)
	assert_eq(reclaimed["kind"], "reclaim")
	assert_eq(reclaimed["journey_id"], journey_id)
	assert_eq(reclaimed["journey"]["character_id"], "checkpoint-character")
	assert_eq(reclaimed["journey"]["lifecycle_status"], "active")
	assert_eq(int(reclaimed["journey"]["peer_id"]), 8)
	assert_eq(float(reclaimed["journey"]["position_x"]), final_position.x)
	assert_eq(float(reclaimed["journey"]["position_y"]), final_position.y)
	assert_eq(float(reclaimed["journey"]["position_z"]), final_position.z)
	assert_eq(reclaimed["journey"]["sector_id"], "sector-0-0")
	assert_eq(int(reclaimed["journey"]["sector_revision"]), expected_revision)
	assert_eq(reclaimed["journey"]["sector_geometry_hash"], expected_hash)
	assert_eq(int(reclaimed["journey"]["last_checkpoint_at"]), int(persisted["last_checkpoint_at"]))
	assert_eq(int(reclaimed["journey"]["last_disconnected_at"]), 0)


func test_checkpoint_persists_empty_metadata_fallback_when_canon_is_closed() -> void:
	var blueprint: Dictionary = JSON.parse_string(FixturesScript.VALID)
	_canon_store = SqliteStoreScript.new()
	assert_eq(_canon_store.open(_canon_path)["outcome"], SqliteStoreScript.OUTCOME_OK)
	var dedicated_canon: CanonRepository = CanonRepositoryScript.new(_canon_store)
	assert_eq(dedicated_canon.ensure_schema()["outcome"], CanonRepositoryScript.OUTCOME_OK)
	assert_eq(dedicated_canon.canonicalize_blueprint(blueprint)["outcome"], CanonRepositoryScript.OUTCOME_OK)
	assert_eq(dedicated_canon.get_checkpoint_metadata("sector-0-0")["outcome"], CanonRepositoryScript.OUTCOME_OK)
	_server._canon_repository = dedicated_canon
	assert_eq(_canon_store.close()["outcome"], SqliteStoreScript.OUTCOME_OK)

	var journey_id: String = String(_registry.active_journey_id("checkpoint-character", 7))
	var position := Vector3(13.0, 2.0, 21.0)
	var started: int = int(Time.get_unix_time_from_system())
	_server._checkpoint_journey(7, position)
	var saved_at: int = int(Time.get_unix_time_from_system())
	var record: Dictionary = _load_journey(_journey_repository, journey_id)
	_assert_checkpoint_record(record, position, 0, "", started, saved_at)