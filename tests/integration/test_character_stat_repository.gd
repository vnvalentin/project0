extends GutTest
## Experiment 1 for Epic #1292: public-seam persistence tests for the
## server-only CharacterStatRepository over real temporary SQLite databases.

const SqliteStoreScript: Script = preload("res://server/sqlite_store.gd")
const RepositoryScript: Script = preload("res://server/character_stat_repository.gd")
const GameStateScript: Script = preload("res://shared/game_state.gd")
const EmbodimentTuningScript: Script = preload("res://server/embodiment_tuning.gd")

var _relative_path: String = ""
var _store: SqliteStore = null
var _repository: Object = null
var _tuning: Object = null


func before_each() -> void:
	_relative_path = "test_character_stats_%d_%d.db" % [Time.get_ticks_usec(), randi()]
	_store = SqliteStoreScript.new()
	_store.open(_relative_path)
	_repository = RepositoryScript.new(_store)
	_repository.ensure_schema()
	_tuning = EmbodimentTuningScript.resolve(EmbodimentTuningScript.DEFAULT_TUNING_VERSION)["tuning"]


func after_each() -> void:
	if _store != null and _store.is_open():
		_store.close()
	for suffix: String in ["", "-wal", "-shm", "-journal"]:
		var path: String = ProjectSettings.globalize_path("user://%s%s" % [_relative_path, suffix])
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _state(strength: float, dexterity: float, constitution: float) -> Object:
	var result: Dictionary = GameStateScript.create_stat_aggregate(
		{"STR": strength, "DEX": dexterity, "CON": constitution, "INT": 10.0, "WIS": 10.0, "CHA": 10.0},
		_tuning
	)
	return result["state"]


func test_missing_character_returns_not_found() -> void:
	var result: Dictionary = _repository.load_stats("nobody", _tuning)
	assert_eq(result["outcome"], RepositoryScript.OUTCOME_NOT_FOUND)
	assert_null(result["state"])


func test_save_close_reopen_recovers_all_eleven_fields() -> void:
	var state: Object = _state(10.0, 10.0, 10.0)
	assert_eq(_repository.save_stats("hero", state, _tuning)["outcome"], RepositoryScript.OUTCOME_OK)
	var before: Dictionary = state.to_snapshot()
	_store.close()
	_store = SqliteStoreScript.new()
	assert_eq(_store.open(_relative_path)["outcome"], SqliteStoreScript.OUTCOME_OK)
	_repository = RepositoryScript.new(_store)
	assert_eq(_repository.ensure_schema()["outcome"], RepositoryScript.OUTCOME_OK)
	var recovered: Dictionary = _repository.load_stats("hero", _tuning)
	assert_eq(recovered["outcome"], RepositoryScript.OUTCOME_OK)
	assert_eq((recovered["state"] as Object).to_snapshot(), before)


func test_resaving_upserts_latest_complete_snapshot() -> void:
	assert_eq(_repository.save_stats("hero", _state(10.0, 10.0, 10.0), _tuning)["outcome"], RepositoryScript.OUTCOME_OK)
	var updated: Object = _state(10.0, 5.0, 30.0)
	assert_eq(_repository.save_stats("hero", updated, _tuning)["outcome"], RepositoryScript.OUTCOME_OK)
	var recovered: Dictionary = _repository.load_stats("hero", _tuning)
	assert_eq(recovered["outcome"], RepositoryScript.OUTCOME_OK)
	assert_eq((recovered["state"] as Object).to_snapshot(), updated.to_snapshot())
	var count: Dictionary = _store.query_with_bindings("SELECT COUNT(*) AS count FROM character_stats WHERE character_id = ?;", ["hero"])
	assert_eq(int(count["rows"][0]["count"]), 1)


func test_malformed_snapshot_is_rejected() -> void:
	assert_eq(_repository.save_stats("hero", _state(10.0, 10.0, 10.0), _tuning)["outcome"], RepositoryScript.OUTCOME_OK)
	_store.query_with_bindings("UPDATE character_stats SET stats_json = ? WHERE character_id = ?;", ["not-json", "hero"])
	var result: Dictionary = _repository.load_stats("hero", _tuning)
	assert_eq(result["outcome"], RepositoryScript.OUTCOME_INVALID_SNAPSHOT)
	assert_null(result["state"])


func test_incomplete_snapshot_is_rejected() -> void:
	assert_eq(_repository.save_stats("hero", _state(10.0, 10.0, 10.0), _tuning)["outcome"], RepositoryScript.OUTCOME_OK)
	_store.query_with_bindings("UPDATE character_stats SET stats_json = ? WHERE character_id = ?;", ['{"STR":10.0}', "hero"])
	var result: Dictionary = _repository.load_stats("hero", _tuning)
	assert_eq(result["outcome"], RepositoryScript.OUTCOME_INVALID_SNAPSHOT)
	assert_null(result["state"])


func test_unknown_version_is_rejected() -> void:
	assert_eq(_repository.save_stats("hero", _state(10.0, 10.0, 10.0), _tuning)["outcome"], RepositoryScript.OUTCOME_OK)
	_store.query_with_bindings("UPDATE character_stats SET schema_version = ? WHERE character_id = ?;", [99, "hero"])
	var result: Dictionary = _repository.load_stats("hero", _tuning)
	assert_eq(result["outcome"], RepositoryScript.OUTCOME_INVALID_SNAPSHOT)
	assert_null(result["state"])