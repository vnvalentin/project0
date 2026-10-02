extends "res://scripts/exp1232_gate_fixture.gd"
## Experiment #1233 server fixture. Requests are resolved on receive. In the
## rollback cases the first request runs while a connection-scoped TEMP trigger
## adds a deferred foreign-key violation: the real unlock INSERT succeeds inside
## the transaction, the real COMMIT fails, and SqliteStore rolls back. The fault
## is removed before any later request, leaving no durable schema change.

const EXP1233_ROLLBACK_CASES: PackedStringArray = ["rollback_first", "rollback_then_same_actor_retry"]
const EXP1233_OUT_OF_REACH: Vector3 = Vector3(0.0, 1.0, -2.5)
const EXP1233_ARM: PackedStringArray = [
	"CREATE TEMP TABLE exp1233_parent (id INTEGER PRIMARY KEY);",
	"CREATE TEMP TABLE exp1233_guard (ref INTEGER REFERENCES exp1233_parent(id) DEFERRABLE INITIALLY DEFERRED);",
	"CREATE TEMP TRIGGER exp1233_fault AFTER INSERT ON main.canon_mutations BEGIN INSERT INTO exp1233_guard (ref) VALUES (-1); END;",
]
const EXP1233_DISARM: PackedStringArray = [
	"DROP TRIGGER temp.exp1233_fault;",
	"DROP TABLE temp.exp1233_guard;",
	"DROP TABLE temp.exp1233_parent;",
]


func _exp_actor_position() -> Vector3:
	return EXP1233_OUT_OF_REACH if _exp_case == "validation_failure_first" else super()


func _exp1232_process(item: Dictionary, pending_count: int) -> void:
	var inject: bool = EXP1233_ROLLBACK_CASES.has(_exp_case) and item["receive_seq"] == 1
	var fault: Dictionary = {}
	if inject:
		fault["armed"] = _exp1233_run(EXP1233_ARM)
	super(item, pending_count)
	if inject:
		fault["disarmed"] = _exp1233_run(EXP1233_DISARM)
		fault["temp_objects_after"] = _exp1233_temp_objects()
		_exp_observation["resolutions"].back()["fault"] = fault
		_exp_write()


func _exp1233_run(statements: PackedStringArray) -> bool:
	var store: SqliteStore = _canon_store if _canon_store != null else _accounts_store
	for statement: String in statements:
		if store.query(statement)["outcome"] != SqliteStore.OUTCOME_OK:
			return false
	return true


func _exp1233_temp_objects() -> int:
	var store: SqliteStore = _canon_store if _canon_store != null else _accounts_store
	var rows: Dictionary = store.query("SELECT COUNT(*) AS count FROM sqlite_temp_master WHERE name LIKE 'exp1233_%';")
	return int(rows["rows"][0]["count"]) if rows["outcome"] == SqliteStore.OUTCOME_OK else -1
