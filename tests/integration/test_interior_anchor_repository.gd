extends GutTest
## #849 public repository seam, executed with real isolated Linux SQLite.

const StoreScript: Script = preload("res://server/sqlite_store.gd")
const CanonScript: Script = preload("res://server/canon_repository.gd")
const MutationsScript: Script = preload("res://server/canon_mutation_repository.gd")
const GuidScript: Script = preload("res://shared/canon_entity_guid.gd")
const FixturesScript: Script = preload("res://scripts/sector_blueprint_fixtures.gd")

var _store: SqliteStore
var _canon: CanonRepository
var _mutations: CanonMutationRepository
var _path: String
var _blueprint: Dictionary


func before_each() -> void:
	_path = "interior_anchor_%d_%d.db" % [Time.get_ticks_usec(), randi()]
	_store = StoreScript.new()
	assert_eq(_store.open(_path)["outcome"], "ok")
	_canon = CanonScript.new(_store)
	_mutations = MutationsScript.new(_store, _canon)
	assert_eq(_canon.ensure_schema()["outcome"], "ok")
	assert_eq(_mutations.ensure_schema()["outcome"], "ok")
	_blueprint = JSON.parse_string(FixturesScript.VALID_WITH_STRUCTURE)
	assert_eq(_canon.canonicalize_blueprint(_blueprint)["outcome"], "ok")


func after_each() -> void:
	if _store != null and _store.is_open():
		_store.close()
	for suffix: String in ["", "-wal", "-shm", "-journal"]:
		var absolute: String = ProjectSettings.globalize_path("user://%s%s" % [_path, suffix])
		if FileAccess.file_exists(absolute):
			assert_eq(DirAccess.remove_absolute(absolute), OK, "Owned fixture cleanup")


func test_server_anchor_resolves_and_recovers_after_reopen() -> void:
	var repository_script: Script = load("res://server/interior_anchor_repository.gd")
	assert_not_null(repository_script, "The server anchor repository public seam must exist")
	if repository_script == null:
		return
	var repository: RefCounted = repository_script.new(_store, _canon, _mutations)
	assert_eq(repository.ensure_schema()["outcome"], "ok")
	var descriptor: Dictionary = _descriptor()
	var registered: Dictionary = repository.register_anchor(descriptor)
	assert_eq(registered["outcome"], "ok")
	if registered["outcome"] != "ok":
		return
	var anchor: Dictionary = registered["anchor"].to_dict()
	assert_eq(anchor["plot_id"], "plot-village-hall")
	assert_eq(anchor["entry_position"], [0.0, 0.0, 0.0])
	assert_eq(anchor["cell_coordinate"], [0, 0, 0])
	assert_eq(anchor["bounds_min"], [-2.0, -1.0, -2.0])
	assert_eq(anchor["bounds_max"], [2.0, 3.0, 2.0])
	assert_eq(anchor["revision"], 1)
	assert_eq(anchor["exterior_revision"], 0)
	assert_eq(repository.resolve_entry(_intent())["anchor"].to_dict(), anchor)
	_store.close()
	_store = StoreScript.new()
	assert_eq(_store.open(_path)["outcome"], "ok")
	_canon = CanonScript.new(_store)
	_mutations = MutationsScript.new(_store, _canon)
	repository = repository_script.new(_store, _canon, _mutations)
	assert_eq(repository.get_anchor(anchor["interior_id"])["anchor"].to_dict(), anchor)
	assert_eq(repository.resolve_entry(_intent())["anchor"].to_dict(), anchor)
	assert_eq(_canon.get_canonical_sector("sector-0-0")["sector"]["blueprint"], _blueprint)


func _descriptor() -> Dictionary:
	return {
		"schema_version": 1,
		"exterior_sector_id": "sector-0-0",
		"exterior_entity_guid": GuidScript.derive("sector-0-0", "structure", "village_hall"),
		"plot_id": "plot-village-hall",
		"entry_position": [0.0, 0.0, 0.0],
		"cell_coordinate": [0, 0, 0],
		"bounds_min": [-2.0, -1.0, -2.0],
		"bounds_max": [2.0, 3.0, 2.0],
		"streaming_reference": "interior/village-hall/0-0-0",
	}


func _intent() -> Dictionary:
	return {
		"schema_version": 1,
		"exterior_sector_id": "sector-0-0",
		"exterior_entity_guid": GuidScript.derive("sector-0-0", "structure", "village_hall"),
	}


func test_registration_replay_and_conflict_preserve_retained_anchor() -> void:
	var repository_script: Script = load("res://server/interior_anchor_repository.gd")
	var repository: RefCounted = repository_script.new(_store, _canon, _mutations)
	assert_eq(repository.ensure_schema()["outcome"], "ok")
	var first: Dictionary = repository.register_anchor(_descriptor())
	assert_eq(first["outcome"], "ok")
	var original: Dictionary = first["anchor"].to_dict()
	var replay: Dictionary = repository.register_anchor(_descriptor())
	assert_eq(replay["outcome"], "idempotent")
	if replay.has("anchor"):
		assert_eq(replay["anchor"].to_dict(), original)
	var conflict: Dictionary = _descriptor()
	conflict["plot_id"] = "another-server-plot-reference"
	assert_eq(repository.register_anchor(conflict)["outcome"], "conflict")
	assert_eq(repository.get_anchor(original["interior_id"])["anchor"].to_dict(), original)
	assert_eq(repository.resolve_entry(_intent())["anchor"].to_dict(), original)


func test_real_second_insert_failure_leaves_no_anchor_after_reopen() -> void:
	# Owned fixture CHECK fails the real cell INSERT; no hidden trigger writes.
	assert_eq(_store.query("""
		CREATE TABLE interior_cells (
			interior_id TEXT NOT NULL REFERENCES interior_anchors(interior_id),
			cell_x INTEGER NOT NULL CHECK (cell_x <> 0), cell_y INTEGER NOT NULL, cell_z INTEGER NOT NULL,
			bounds_min_json TEXT NOT NULL, bounds_max_json TEXT NOT NULL,
			streaming_reference TEXT NOT NULL, revision INTEGER NOT NULL CHECK (revision = 1),
			PRIMARY KEY(interior_id, cell_x, cell_y, cell_z)
		);
	""")["outcome"], "ok")
	var repository_script: Script = load("res://server/interior_anchor_repository.gd")
	var contract_script: Script = load("res://shared/interior_anchor_contract.gd")
	var repository: RefCounted = repository_script.new(_store, _canon, _mutations)
	assert_eq(repository.ensure_schema()["outcome"], "ok")
	var interior_id: String = contract_script.parse_server_descriptor(_descriptor())["anchor"].interior_id
	assert_eq(repository.register_anchor(_descriptor())["outcome"], "transaction_failed")
	assert_eq(repository.get_anchor(interior_id)["outcome"], "not_found")
	assert_eq(repository.resolve_entry(_intent())["outcome"], "not_found")
	_store.close()
	_store = StoreScript.new()
	assert_eq(_store.open(_path)["outcome"], "ok")
	_canon = CanonScript.new(_store)
	_mutations = MutationsScript.new(_store, _canon)
	repository = repository_script.new(_store, _canon, _mutations)
	assert_eq(repository.get_anchor(interior_id)["outcome"], "not_found")
	assert_eq(repository.resolve_entry(_intent())["outcome"], "not_found")
	assert_eq(_canon.get_canonical_sector("sector-0-0")["sector"]["blueprint"], _blueprint)
