extends GutTest
## #1376 real isolated public-repository controls; no capacity claim.
const SourceEvidence: Script = preload("res://scripts/m4_canon_evidence.gd")
const Observer: Script = preload("res://scripts/m4_checkpoint_attribution.gd")
const Store: Script = preload("res://server/sqlite_store.gd")
const Canon: Script = preload("res://server/canon_repository.gd")
const Journey: Script = preload("res://server/journey_repository.gd")
const Registry: Script = preload("res://server/journey_registry.gd")
const Coordinator: Script = preload("res://server/canon_generation_coordinator.gd")
const Fixtures: Script = preload("res://scripts/sector_blueprint_fixtures.gd")

class BindingHost extends RefCounted:
	var _canon_repository: Object
	var _journey_repository: Object
	var _canon_generation_coordinator: Object
	var _journey_registry: Object

var _stores: Array[SqliteStore] = []
var _paths: Array[String] = []
var _host: BindingHost
var _observer: Object
var _case: String
var _failure_count: int
var _trace: Dictionary

func before_each() -> void:
	_stores = []
	_paths = []
	_case = ""
	_failure_count = get_fail_count()
	_trace = {"issue": 1376, "kind": "isolated_checkpoint_component", "source_revision": OS.get_environment("M4_SOURCE_REVISION"),
		"helper_sha256": FileAccess.get_sha256("res://scripts/m4_checkpoint_attribution.gd"),
		"test_sha256": FileAccess.get_sha256("res://tests/integration/test_m4_checkpoint_attribution.gd")}
	_trace["source_identity"] = SourceEvidence.source_identity(_trace["source_revision"])
	assert_eq(_trace["source_identity"]["status"], "OBSERVED", "standard runner derives HEAD or rejects malformed/conflicting supplied source")

func after_each() -> void:
	for store: SqliteStore in _stores:
		if store.is_open():
			store.close()
	var cleanup: Array = []
	for path: String in _paths:
		for suffix: String in ["", "-wal", "-shm", "-journal"]:
			var owned: String = path + suffix
			if FileAccess.file_exists(owned):
				DirAccess.remove_absolute(owned)
			cleanup.append({"path": owned, "absent": not FileAccess.file_exists(owned)})
			assert_false(FileAccess.file_exists(owned), "owned component fixture removed")
	_trace["cleanup"] = cleanup
	_trace["case_id"] = _case
	_trace["assertion_failures"] = get_fail_count() - _failure_count
	_trace["passed"] = _trace["assertion_failures"] == 0
	var directory: String = "res://logs/experiments"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var file: FileAccess = FileAccess.open("%s/exp_m4_checkpoint_%s_%d.json" % [directory, _case, Time.get_ticks_usec()], FileAccess.WRITE)
	assert_not_null(file)
	if file != null:
		var content: String = JSON.stringify(_trace, "\t")
		file.store_string(content)
		file.flush()
		assert_eq(file.get_error(), OK)
		var path: String = file.get_path_absolute()
		file.close()
		assert_eq(FileAccess.get_file_as_string(path), content, "complete evidence readback")
	_host = null
	_observer = null

func _open_store() -> SqliteStore:
	var relative: String = "m4_checkpoint_%d_%d.db" % [Time.get_ticks_usec(), randi()]
	var path: String = ProjectSettings.globalize_path("user://" + relative)
	for suffix: String in ["", "-wal", "-shm", "-journal"]:
		if FileAccess.file_exists(path + suffix):
			return null
	_paths.append(path)
	var store: SqliteStore = Store.new()
	_stores.append(store)
	assert_eq(store.open(relative)["outcome"], "ok")
	return store

func _fixture(dedicated: bool) -> Dictionary:
	var accounts: SqliteStore = _open_store()
	var canon_store: SqliteStore = _open_store() if dedicated else accounts
	_host = BindingHost.new()
	_host._canon_repository = Canon.new(canon_store)
	_host._journey_repository = Journey.new(accounts)
	_host._canon_generation_coordinator = Coordinator.new()
	_host._journey_registry = Registry.new()
	_host._canon_generation_coordinator.set_canonicalize_callback(Callable(_host._canon_repository, "canonicalize_blueprint"))
	_host._journey_registry.set_repository(_host._journey_repository)
	assert_eq(_host._canon_repository.ensure_schema()["outcome"], "ok")
	assert_eq(_host._journey_repository.ensure_schema()["outcome"], "ok")
	var blueprint: Dictionary = JSON.parse_string(Fixtures.VALID)
	assert_eq(_host._canon_repository.canonicalize_blueprint(blueprint)["outcome"], "ok")
	assert_eq(_host._journey_registry.enter("diagnostic-character", 7, 100)["outcome"], "ok")
	var originals: Dictionary = {"canon": _host._canon_repository, "journey": _host._journey_repository, "blueprint": blueprint}
	_observer = Observer.new()
	assert_true(_observer.install(_host))
	return originals

func _public_checkpoint_calls() -> Dictionary:
	var started: int = _observer.begin_checkpoint()
	var metadata: Dictionary = _host._canon_repository.get_checkpoint_metadata("sector-0-0")
	assert_eq(_host._journey_registry.checkpoint("diagnostic-character", Vector3(12, 1, 18), 101, "sector-0-0", 1, "checked-hash")["outcome"], "ok")
	_observer.end_checkpoint(started)
	return metadata

func _positive(dedicated: bool) -> void:
	var originals: Dictionary = _fixture(dedicated)
	var metadata: Dictionary = _public_checkpoint_calls()
	assert_eq(metadata["outcome"], "ok", "unchanged delegated Canon state")
	assert_eq(metadata["sector_revision"], int(originals["blueprint"]["schema_version"]))
	assert_eq(metadata["sector_geometry_hash"], JSON.stringify(originals["blueprint"]).md5_text())
	var rows: Dictionary = _host._journey_repository.load_all()
	assert_eq(rows["outcome"], "ok")
	assert_eq(rows["records"].size(), 1)
	var row: Dictionary = rows["records"][0]
	assert_eq(row["character_id"], "diagnostic-character")
	assert_eq(row["position_x"], 12.0)
	assert_eq(row["position_z"], 18.0)
	assert_eq(row["sector_geometry_hash"], "checked-hash")
	assert_eq(row["last_checkpoint_at"], 101)
	assert_true(_observer.bindings_qualified())
	var sample: Dictionary = _observer.take_iteration()
	assert_eq(sample["checkpoint_calls"], 1)
	assert_eq(sample["canon_read"]["calls"], 1)
	assert_eq(sample["journey_save"]["calls"], 1)
	assert_gte(sample["duration_usec"], sample["canon_read"]["duration_usec"] + sample["journey_save"]["duration_usec"])
	_trace["bindings"] = _observer.binding_evidence()
	_trace["sample"] = sample

func test_shared_store_delegation_preserves_state() -> void:
	_case = "shared_positive"
	_positive(false)

func test_dedicated_canon_delegation_preserves_state() -> void:
	_case = "dedicated_positive"
	_positive(true)

func test_stale_registry_binding_cannot_qualify() -> void:
	_case = "stale_registry_negative"
	var originals: Dictionary = _fixture(false)
	_host._journey_registry.set_repository(originals["journey"])
	_public_checkpoint_calls()
	assert_false(_observer.bindings_qualified())
	assert_false(_observer.binding_evidence()["registry"])
	assert_eq(_observer.take_iteration()["journey_save"]["calls"], 0, "missing observed save stays missing")

func test_missing_canon_observer_cannot_qualify() -> void:
	_case = "missing_canon_negative"
	var originals: Dictionary = _fixture(true)
	_host._canon_repository = originals["canon"]
	_public_checkpoint_calls()
	assert_false(_observer.bindings_qualified())
	assert_false(_observer.binding_evidence().get("server_canon", false))
	assert_eq(_observer.take_iteration()["canon_read"]["calls"], 0)

func test_different_store_handle_cannot_qualify() -> void:
	_case = "different_handle_negative"
	_fixture(true)
	_host._canon_repository.set("_store", _open_store())
	assert_false(_observer.bindings_qualified())
	assert_false(_observer.binding_evidence()["canon_store_original"])

func test_calls_outside_checkpoint_scope_are_not_attributed() -> void:
	_case = "outside_scope"
	_fixture(false)
	_host._canon_repository.get_checkpoint_metadata("sector-0-0")
	_host._journey_registry.checkpoint("diagnostic-character", Vector3.ZERO, 102)
	var sample: Dictionary = _observer.take_iteration()
	assert_eq(sample["checkpoint_calls"], 0)
	assert_eq(sample["canon_read"]["calls"], 0)
	assert_eq(sample["journey_save"]["calls"], 0)
