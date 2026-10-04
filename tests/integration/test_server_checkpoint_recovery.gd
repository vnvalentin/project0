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
var _store: SqliteStore
var _server: CheckpointServer
var _registry: JourneyRegistry
var _player_state: Node


func before_each() -> void:
	_relative_path = "test_server_checkpoint_recovery_%d_%d.db" % [Time.get_ticks_usec(), randi()]
	_store = SqliteStoreScript.new()
	assert_eq(_store.open(_relative_path)["outcome"], SqliteStoreScript.OUTCOME_OK)

	var canon: CanonRepository = CanonRepositoryScript.new(_store)
	assert_eq(canon.ensure_schema()["outcome"], CanonRepositoryScript.OUTCOME_OK)
	var blueprint: Dictionary = JSON.parse_string(FixturesScript.VALID)
	assert_eq(canon.canonicalize_blueprint(blueprint)["outcome"], CanonRepositoryScript.OUTCOME_OK)

	var journey_repository: JourneyRepository = JourneyRepositoryScript.new(_store)
	assert_eq(journey_repository.ensure_schema()["outcome"], JourneyRepositoryScript.OUTCOME_OK)
	_registry = JourneyRegistryScript.new()
	_registry.set_repository(journey_repository)
	assert_eq(_registry.enter("checkpoint-character", 7, 100)["outcome"], JourneyRegistryScript.OUTCOME_OK)

	_server = CheckpointServer.new()
	_server._canon_repository = canon
	_server._journey_repository = journey_repository
	_server._journey_registry = _registry
	_player_state = PlayerStateScript.new()
	_player_state.character_id = "checkpoint-character"
	_server._player_states[7] = _player_state


func after_each() -> void:
	if _server != null:
		_server.free()
	if _player_state != null:
		_player_state.free()
	if _store != null and _store.is_open():
		_store.close()
	for suffix: String in ["", "-wal", "-shm", "-journal"]:
		var path: String = ProjectSettings.globalize_path("user://%s%s" % [_relative_path, suffix])
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func test_checkpoint_metadata_flows_through_server_to_durable_recovery() -> void:
	var position := Vector3(12.0, 1.0, 20.0)
	var blueprint: Dictionary = JSON.parse_string(FixturesScript.VALID)
	var expected_revision: int = int(blueprint["schema_version"])
	_server._checkpoint_journey(7, position)

	var before_restart: Dictionary = _store.query_with_bindings(
		"SELECT position_x, position_y, position_z, sector_id, sector_revision, sector_geometry_hash FROM journeys WHERE character_id = ?;",
		["checkpoint-character"]
	)
	assert_eq(before_restart["outcome"], SqliteStoreScript.OUTCOME_OK)
	assert_eq(before_restart["rows"].size(), 1)
	var row: Dictionary = before_restart["rows"][0]
	assert_eq(float(row["position_x"]), position.x)
	assert_eq(float(row["position_y"]), position.y)
	assert_eq(float(row["position_z"]), position.z)
	assert_eq(row["sector_id"], "sector-0-0")
	assert_eq(int(row["sector_revision"]), expected_revision)
	assert_eq(row["sector_geometry_hash"], JSON.stringify(blueprint).md5_text())

	var journey_id: String = String(_registry.active_journey_id("checkpoint-character", 7))
	assert_ne(journey_id, "")
	assert_eq(_store.close()["outcome"], SqliteStoreScript.OUTCOME_OK)
	assert_eq(_store.open(_relative_path)["outcome"], SqliteStoreScript.OUTCOME_OK)
	var recovered_repository: JourneyRepository = JourneyRepositoryScript.new(_store)
	assert_eq(recovered_repository.ensure_schema()["outcome"], JourneyRepositoryScript.OUTCOME_OK)
	var records: Dictionary = recovered_repository.load_all()
	assert_eq(records["outcome"], JourneyRepositoryScript.OUTCOME_OK)
	var recovered_registry: JourneyRegistry = JourneyRegistryScript.new()
	recovered_registry.set_repository(recovered_repository)
	assert_eq(recovered_registry.restore_records(records["records"])["outcome"], JourneyRegistryScript.OUTCOME_OK)
	var reclaimed: Dictionary = recovered_registry.enter("checkpoint-character", 8, int(Time.get_unix_time_from_system()))
	assert_eq(reclaimed["outcome"], JourneyRegistryScript.OUTCOME_OK)
	assert_eq(reclaimed["kind"], "reclaim")
	assert_eq(reclaimed["journey_id"], journey_id)
	assert_eq(float(reclaimed["journey"]["position_x"]), position.x)
	assert_eq(float(reclaimed["journey"]["position_y"]), position.y)
	assert_eq(float(reclaimed["journey"]["position_z"]), position.z)
	assert_eq(reclaimed["journey"]["sector_id"], "sector-0-0")
	assert_eq(int(reclaimed["journey"]["sector_revision"]), expected_revision)
	assert_eq(reclaimed["journey"]["sector_geometry_hash"], JSON.stringify(blueprint).md5_text())