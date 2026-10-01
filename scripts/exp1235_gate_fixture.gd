extends "res://scripts/exp1234_gate_fixture.gd"
## Experiment #1235 server fixture. Armed only in the first server process.
## pre_commit: a connection-scoped TEMP trigger calls a registered SQL function
## right after the real unlock INSERT, inside the open transaction; it publishes a
## barrier and blocks, so COMMIT never runs. post_commit: after the real COMMIT
## returns, the fixture publishes a barrier and blocks before the confirmation is
## sent. In both windows the controller kills this process; the barrier only
## records release if it was never killed.

const EXP1235_BARRIER_HOLD_MSEC: int = 120000
const EXP1235_TRIGGER: String = "CREATE TEMP TRIGGER exp1235_pre_commit AFTER INSERT ON main.canon_mutations BEGIN SELECT exp1235_barrier(NEW.event_id); END;"

var _exp1235_armed: bool = OS.get_environment("EXP1235_ARM") == "1"
var _exp1235_baseline_taken: bool = false


func _resolve_environmental_interaction(sender_peer_id: int, intent: Dictionary) -> Dictionary:
	if _exp1235_armed and _exp_case == "pre_commit" and not _exp1235_baseline_taken:
		_exp1235_baseline_taken = true
		_exp_observation["expected_snapshot"] = _exp1234_snapshot()
		var store: SqliteStore = _canon_store if _canon_store != null else _accounts_store
		var registered: bool = store._db.create_function("exp1235_barrier", Callable(self, "_exp1235_sql_barrier"), 1)
		_exp_observation["fault"] = {"function_registered": registered, "trigger": store.query(EXP1235_TRIGGER)["outcome"] == "ok"}
		_exp_write()
	var resolution: Dictionary = super(sender_peer_id, intent)
	if _exp1235_armed and _exp_case == "post_commit" and resolution.get("reason") == "ok":
		_exp1235_barrier("post_commit", {"applied_revision": resolution.get("applied_revision"), "event_id": resolution.get("event_id")})
	return resolution


func _exp1235_sql_barrier(event_id: Variant) -> int:
	return _exp1235_barrier("pre_commit", {"event_id": event_id})


func _exp1235_barrier(window: String, detail: Dictionary) -> int:
	_exp_observation["barrier"] = {"window": window, "pid": OS.get_process_id(), "detail": detail}
	_exp_write()
	var flag: FileAccess = FileAccess.open(OS.get_environment("EXP1235_BARRIER_FILE"), FileAccess.WRITE)
	if flag != null:
		flag.store_string(JSON.stringify({"window": window, "pid": OS.get_process_id()}))
		flag.close()
	var deadline: int = Time.get_ticks_msec() + EXP1235_BARRIER_HOLD_MSEC
	while Time.get_ticks_msec() < deadline:
		OS.delay_msec(50)
	_exp_observation["barrier"]["released_without_kill"] = true
	_exp_write()
	return 1
