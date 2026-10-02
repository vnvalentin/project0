extends SceneTree

const GuidScript: Script = preload("res://shared/canon_entity_guid.gd")
const RepositoryScript: Script = preload("res://server/canon_repository.gd")
const CoordinatorScript: Script = preload("res://server/canon_generation_coordinator.gd")
const AdmissionScript: Script = preload("res://server/sector_archetype_admission.gd")

class TimedStore extends SqliteStore:
	var measured_calls: Array[Dictionary] = []

	func query(sql: String) -> Dictionary:
		var started: int = Time.get_ticks_usec()
		var result: Dictionary = super.query(sql)
		measured_calls.append({"operation": sql.strip_edges().get_slice(" ", 0).to_upper(), "method": "query", "elapsed_ms": float(Time.get_ticks_usec() - started) / 1000.0, "outcome": result.outcome})
		return result

	func query_with_bindings(sql: String, bindings: Array = []) -> Dictionary:
		var started: int = Time.get_ticks_usec()
		var result: Dictionary = super.query_with_bindings(sql, bindings)
		measured_calls.append({"operation": sql.strip_edges().get_slice(" ", 0).to_upper(), "method": "query_with_bindings", "elapsed_ms": float(Time.get_ticks_usec() - started) / 1000.0, "outcome": result.outcome})
		return result

	func transaction(body: Callable) -> Dictionary:
		var wall_started: float = Time.get_unix_time_from_system()
		var started: int = Time.get_ticks_usec()
		var result: Dictionary = super.transaction(body)
		var elapsed_ms: float = float(Time.get_ticks_usec() - started) / 1000.0
		var wall_ended: float = Time.get_unix_time_from_system()
		measured_calls.append({"operation": "TRANSACTION", "method": "transaction", "elapsed_ms": elapsed_ms, "wall_start_s": wall_started, "wall_end_s": wall_ended, "outcome": result.outcome})
		return result


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.size() not in [1, 2] or (arguments.size() == 2 and arguments[1] not in ["1", "3"]):
		quit(2)
		return
	var sample_count: int = int(arguments[1]) if arguments.size() == 2 else 3
	var samples: Array[Dictionary] = []
	var passed: bool = true
	for iteration: int in range(sample_count):
		var filename: String = "test_canon_timing_%d_%d.db" % [OS.get_process_id(), Time.get_ticks_usec()]
		var store: TimedStore = TimedStore.new()
		var repository: CanonRepository = RepositoryScript.new(store)
		var setup_ok: bool = store.open(filename).outcome == "ok" and repository.ensure_schema().outcome == "ok"
		var settings: Dictionary = {}
		if setup_ok:
			var journal: Dictionary = store.query("PRAGMA journal_mode;")
			var synchronous: Dictionary = store.query("PRAGMA synchronous;")
			setup_ok = journal.outcome == "ok" and synchronous.outcome == "ok" and journal.rows.size() == 1 and synchronous.rows.size() == 1
			if setup_ok:
				settings = {"journal_mode": journal.rows[0].journal_mode, "synchronous": synchronous.rows[0].synchronous}
				setup_ok = settings.journal_mode == "wal" and settings.synchronous is int and settings.synchronous in [0, 1, 2, 3]
		var callback_time: Array[float] = [0.0]
		var coordinator: CanonGenerationCoordinator = CoordinatorScript.new()
		coordinator.set_canonicalize_callback(func(blueprint: Dictionary) -> Dictionary:
			var started: int = Time.get_ticks_usec()
			var result: Dictionary = repository.canonicalize_blueprint(blueprint)
			callback_time[0] = float(Time.get_ticks_usec() - started) / 1000.0
			return result
		)
		store.measured_calls.clear()
		var generation: Dictionary = {"request_outcome": "validated", "validation_outcome": "valid", "blueprint": _blueprint()}
		var started: int = Time.get_ticks_usec()
		var result: Dictionary = coordinator.accept_generation_result("sector_01_02", AdmissionScript.PROFILE_POI_ANCHOR, generation) if setup_ok else {"outcome": "setup_failed"}
		var elapsed: float = float(Time.get_ticks_usec() - started) / 1000.0
		samples.append({"iteration": iteration, "sqlite_settings": settings, "outcome": result.outcome, "total_ms": elapsed, "canonicalize_ms": callback_time[0], "admission_and_dispatch_ms": elapsed - callback_time[0], "store_calls": store.measured_calls.duplicate(true)})
		passed = passed and result.outcome == "canonicalized"
		if store.is_open():
			store.close()
		for suffix: String in ["", "-wal", "-shm", "-journal"]:
			var path: String = ProjectSettings.globalize_path("user://" + filename + suffix)
			if FileAccess.file_exists(path):
				passed = DirAccess.remove_absolute(path) == OK and passed
	var output: FileAccess = FileAccess.open(arguments[0], FileAccess.WRITE)
	if output == null:
		quit(1)
		return
	output.store_string(JSON.stringify({"status": "passed" if passed else "failed", "samples": samples, "budget_ms": 15.0, "acceptance": "diagnostic only; no timing threshold assertion or policy change", "limitations": "public transaction includes nested INSERT; native BEGIN/COMMIT/fsync not individually observed"}, "\t") + "\n")
	output.close()
	quit(0 if passed else 1)


func _blueprint() -> Dictionary:
	return {
		"schema_version": 3, "sector_id": "sector_01_02", "origin": {"x": 16, "y": 20},
		"tiles": [{"x": 16, "y": 20, "kind": "floor"}, {"x": 17, "y": 20, "kind": "floor"}],
		"structures": [{"structure_id": "str_claim_stone_01", "kind": "well", "x": 16, "y": 20, "facing_degrees": 0, "entity_guid": GuidScript.derive_rfc4122_v5("sector_01_02", GuidScript.ENTITY_CLASS_STRUCTURE, "str_claim_stone_01")}],
	}
