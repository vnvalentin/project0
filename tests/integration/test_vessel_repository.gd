extends GutTest
## Slice 143 (Phase 15 follow-on, P-016): public-seam tests for the server-only
## durable vessel repository (server/vessel_repository.gd) over a real temporary
## user:// SQLite database opened through the SqliteStore engine seam (consumed
## unmodified), mirroring tests/integration/test_canon_repository.gd. Proves the
## round-trip survives a store restart, upserts on re-train, and fails closed on a
## corrupt/mistuned row and a missing character. See
## docs/slices/143-vessel-persistence.md.

const SqliteStoreScript: Script = preload("res://server/sqlite_store.gd")
const VesselRepositoryScript: Script = preload("res://server/vessel_repository.gd")
const VesselScript: Script = preload("res://shared/vessel_progression_state.gd")
const EmbodimentTuningScript: Script = preload("res://server/embodiment_tuning.gd")

var _relative_path: String = ""
var _store: SqliteStore = null
var _repository: VesselRepository = null
var _tuning: Object = null


func before_each() -> void:
	_relative_path = "test_vessel_repository_%d_%d.db" % [Time.get_ticks_usec(), randi()]
	_store = SqliteStoreScript.new()
	_store.open(_relative_path)
	_repository = VesselRepositoryScript.new(_store)
	_repository.ensure_schema()
	_tuning = EmbodimentTuningScript.resolve(EmbodimentTuningScript.DEFAULT_TUNING_VERSION)["tuning"]


func after_each() -> void:
	if _store != null and _store.is_open():
		_store.close()
	for suffix: String in ["", "-wal", "-shm", "-journal"]:
		var path: String = ProjectSettings.globalize_path("user://%s%s" % [_relative_path, suffix])
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func test_missing_character_returns_not_found() -> void:
	var result: Dictionary = _repository.load_vessel("nobody", _tuning)
	assert_eq(result["outcome"], VesselRepositoryScript.OUTCOME_NOT_FOUND, "no row yet")
	assert_null(result["vessel"], "no vessel is returned")


func test_save_then_restart_recovers_the_same_vessel() -> void:
	var vessel: Object = VesselScript.create_baseline(_tuning)
	assert_eq(_repository.save_vessel("hero", vessel)["outcome"], VesselRepositoryScript.OUTCOME_OK)
	_store.close()

	_store = SqliteStoreScript.new()
	assert_eq(_store.open(_relative_path)["outcome"], SqliteStoreScript.OUTCOME_OK)
	_repository = VesselRepositoryScript.new(_store)
	assert_eq(_repository.ensure_schema()["outcome"], VesselRepositoryScript.OUTCOME_OK)
	var recovered: Dictionary = _repository.load_vessel("hero", _tuning)
	assert_eq(recovered["outcome"], VesselRepositoryScript.OUTCOME_OK, "the vessel survives a restart")
	var loaded: Object = recovered["vessel"]
	assert_eq(loaded.tuning_version, vessel.tuning_version, "the pinned tuning round-trips")
	assert_eq(loaded.base_nodes, vessel.base_nodes, "the earned base nodes round-trip exactly")


func test_saved_earned_progression_round_trips() -> void:
	var vessel: Object = VesselScript.create_baseline(_tuning)
	# A real training gain so the persisted nodes are no longer the balanced baseline.
	assert_eq(vessel.train("STR", 3.0, _tuning)["outcome"], VesselScript.OUTCOME_OK)
	assert_eq(_repository.save_vessel("hero", vessel)["outcome"], VesselRepositoryScript.OUTCOME_OK)
	var recovered: Dictionary = _repository.load_vessel("hero", _tuning)
	assert_eq(recovered["outcome"], VesselRepositoryScript.OUTCOME_OK)
	assert_eq((recovered["vessel"] as Object).base_nodes, vessel.base_nodes, "the earned gain persists, not the baseline")


func test_resaving_upserts_the_same_character() -> void:
	var vessel: Object = VesselScript.create_baseline(_tuning)
	assert_eq(_repository.save_vessel("hero", vessel)["outcome"], VesselRepositoryScript.OUTCOME_OK)
	assert_eq(vessel.train("DEX", 2.0, _tuning)["outcome"], VesselScript.OUTCOME_OK)
	assert_eq(_repository.save_vessel("hero", vessel)["outcome"], VesselRepositoryScript.OUTCOME_OK, "a second save upserts")
	var recovered: Dictionary = _repository.load_vessel("hero", _tuning)
	assert_eq((recovered["vessel"] as Object).base_nodes, vessel.base_nodes, "the latest trained state is stored")


func test_corrupt_stored_row_fails_closed() -> void:
	var vessel: Object = VesselScript.create_baseline(_tuning)
	assert_eq(_repository.save_vessel("hero", vessel)["outcome"], VesselRepositoryScript.OUTCOME_OK)
	# Corrupt the persisted blob out-of-band so the loaded budget no longer holds.
	_store.query_with_bindings(
		"UPDATE character_vessels SET vessel_json = ? WHERE character_id = ?;",
		['{"schema_version":1,"tuning_version":"vessel-2026q4-baseline","base_nodes":{"STR":999.0,"DEX":0.0,"CON":0.0,"INT":0.0,"WIS":0.0,"CHA":0.0}}', "hero"]
	)
	var result: Dictionary = _repository.load_vessel("hero", _tuning)
	assert_eq(result["outcome"], VesselRepositoryScript.OUTCOME_INVALID_VESSEL, "a budget-violating row is refused")
	assert_null(result["vessel"], "no invalid vessel is resurrected")


func test_empty_character_id_is_refused() -> void:
	var vessel: Object = VesselScript.create_baseline(_tuning)
	assert_eq(_repository.save_vessel("", vessel)["outcome"], VesselRepositoryScript.OUTCOME_INVALID_VESSEL, "empty id refused")
	assert_eq(_repository.save_vessel("hero", null)["outcome"], VesselRepositoryScript.OUTCOME_INVALID_VESSEL, "null vessel refused")
