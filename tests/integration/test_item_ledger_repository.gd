extends GutTest

const StoreScript = preload("res://server/sqlite_store.gd")

var _relative_path: String = ""
var _store: SqliteStore = null


func before_each() -> void:
	_relative_path = "test_item_ledger_%d_%d.db" % [Time.get_ticks_usec(), randi()]
	_store = StoreScript.new()
	assert_eq(_store.open(_relative_path).outcome, StoreScript.OUTCOME_OK)


func after_each() -> void:
	if _store != null and _store.is_open():
		_store.close()
	for suffix: String in ["", "-wal", "-shm", "-journal"]:
		var path: String = ProjectSettings.globalize_path("user://%s%s" % [_relative_path, suffix])
		if FileAccess.file_exists(path):
			assert_eq(DirAccess.remove_absolute(path), OK)


func test_sqlite_preserves_integer_types_above_json_precision_across_reopen() -> void:
	assert_eq(_store.query("CREATE TABLE integer_probe (id INTEGER PRIMARY KEY, value INTEGER NOT NULL);").outcome, StoreScript.OUTCOME_OK)
	var values: Array[int] = [0, 9007199254740993, 9223372036854775807]
	for index: int in values.size():
		assert_eq(_store.query_with_bindings("INSERT INTO integer_probe (id, value) VALUES (?, ?);", [index, values[index]]).outcome, StoreScript.OUTCOME_OK)
	_store.close()
	_store = StoreScript.new()
	assert_eq(_store.open(_relative_path).outcome, StoreScript.OUTCOME_OK)
	var result: Dictionary = _store.query("SELECT value FROM integer_probe ORDER BY id;")
	assert_eq(result.outcome, StoreScript.OUTCOME_OK)
	assert_eq(result.rows.size(), values.size())
	for index: int in values.size():
		assert_true(result.rows[index].value is int, "INTEGER row preserves its type")
		assert_eq(result.rows[index].value, values[index], "no float rounding or int64 truncation")
