extends GutTest

const StoreScript: Script = preload("res://server/sqlite_store.gd")
const AUTHORITY_PATH: String = "res://server/claim_permit_authority.gd"
var _store: SqliteStore
var _database: String


func before_each() -> void:
	_database = "test_claim_permit_%d_%d.db" % [Time.get_ticks_usec(), randi()]
	_store = StoreScript.new()
	assert_eq(_store.open(_database).outcome, "ok")


func after_each() -> void:
	if _store.is_open():
		_store.close()
	for suffix: String in ["", "-wal", "-shm", "-journal"]:
		var path: String = ProjectSettings.globalize_path("user://" + _database + suffix)
		if FileAccess.file_exists(path):
			assert_eq(DirAccess.remove_absolute(path), OK)


func test_primary_owner_can_start_but_an_unpermitted_visitor_cannot() -> void:
	assert_true(ResourceLoader.exists(AUTHORITY_PATH), "the permission authority public seam exists")
	if not ResourceLoader.exists(AUTHORITY_PATH):
		return
	var authority_script: Script = load(AUTHORITY_PATH)
	var authority: RefCounted = authority_script.new(_store)
	assert_eq(authority.ensure_schema().outcome, "ok")
	assert_eq(authority.register_claim("plot-one", "owner-one", "provision-one").outcome, "ok")
	var allowed: Dictionary = authority.begin_interaction("owner-one", "plot-one", 1)
	assert_eq(allowed.outcome, "ok")
	assert_true(allowed.has("interaction_id"))
	assert_eq(authority.begin_interaction("visitor-one", "plot-one", 1).outcome, "permission_denied")
