extends "res://server/server_main.gd"
## #1376 isolated workload. Production admissions, movement, Canon and NPCs stay real.
## EngineProfiler supplies complete engine physics work, not tick wall periods.
const Issuer: Script = preload("res://server/assertion_issuer.gd")
const SECTORS: Array[String] = ["sector-0-0", "sector-1-0", "sector-0-1", "sector-1-1"]

class TickProfiler extends EngineProfiler:
	var receiver: Callable
	func _tick(frame_time: float, process_time: float, physics_time: float, physics_frame_time: float) -> void:
		receiver.call(frame_time, process_time, physics_time, physics_frame_time)

class WorkerProbe extends RefCounted:
	var iterations: int = 0
	var thread_id: int = 0
	func run() -> void:
		thread_id = OS.get_thread_caller_id()
		var deadline: int = Time.get_ticks_usec() + 50000
		while Time.get_ticks_usec() < deadline:
			iterations += 1

class MovingBody extends CharacterBody3D:
	var home: Vector3
	var steps: int = 0
	var travel: float = 0.0
	func _physics_process(delta: float) -> void:
		var before: Vector3 = position
		velocity = Vector3(1.0 if steps % 120 < 60 else -1.0, 0, 0)
		move_and_collide(velocity * delta)
		travel += before.distance_to(position)
		steps += 1

var _m4_profiler: TickProfiler
var _m4_report: Dictionary = {"samples": [], "crossings": [], "canon_reads": [], "errors": [], "isolation": {}}
var _m4_bodies: Array[MovingBody] = []
var _m4_triggers: Array[Area3D] = []
var _m4_seen: Dictionary = {}
var _m4_trigger_entries: int = 0
var _m4_start_usec: int = 0
var _m4_last_frame: int = 0
var _m4_started: bool = false
var _m4_finished: bool = false
var _m4_ready_ticks: int = 0
var _m4_healthy_before: Array = []
var _m4_listener: TCPServer
var _m4_connections: Array[StreamPeerTCP] = []
var _m4_background: Node
var _m4_background_results: Array[Dictionary] = []
var _m4_fault: Dictionary = {}
var _m4_worker_tasks: Array[int] = []
var _m4_worker_objects: Array[WorkerProbe] = []
var _m4_worker_peak_pending: int = 0
var _m4_worker_completed: int = 0
var _m4_blocking_wait_calls: int = 0
var _m4_blocking_wait_usec: int = 0
var _m4_required_ticks: int = int(OS.get_environment("M4_TICKS"))

func _initialize() -> void:
	if not EngineDebugger.is_active():
		push_error("M4 requires the local engine profiler")
		quit(1)
		return
	_m4_profiler = TickProfiler.new()
	_m4_profiler.receiver = _m4_tick
	EngineDebugger.register_profiler("m4", _m4_profiler)
	EngineDebugger.profiler_enable("m4", true)
	var issuer: Object = Issuer.new(OS.get_environment("PROJECT0_ASSERTION_SECRET"), "project0-login", "project0-game")
	for index: int in range(10):
		var identity: String = "m4-player-%d" % index
		var token: String = issuer.issue(identity, identity, identity, int(Time.get_unix_time_from_system()), 300, "M4 Player %d" % index, {})
		var file: FileAccess = FileAccess.open(OS.get_environment("M4_PRIVATE") + "/assertion-%d" % index, FileAccess.WRITE)
		if file == null:
			quit(1)
			return
		file.store_string(token)
		file.close()
	super()

func _start_server() -> void:
	await super()
	if _canon_repository == null:
		return
	for index: int in range(4):
		var blueprint: Dictionary = _m4_blueprint(index)
		var result: Dictionary = _canon_repository.canonicalize_blueprint(blueprint)
		if result.get("outcome") != "ok":
			_m4_report["errors"].append("canonical_setup_failed:" + SECTORS[index])
	_m4_healthy_before = _m4_healthy_rows()
	_m4_seed_sector_fault()
	for index: int in range(15):
		var body: MovingBody = MovingBody.new()
		body.name = "M4Body%d" % index
		body.position = Vector3(436.0 + (index % 5) * 2.0, 1.0, 436.0 + (index / 5) * 4.0)
		body.home = body.position
		body.collision_layer = 4
		body.collision_mask = 4
		var shape: CollisionShape3D = CollisionShape3D.new()
		var sphere: SphereShape3D = SphereShape3D.new()
		sphere.radius = 0.3
		shape.shape = sphere
		body.add_child(shape)
		root.add_child(body)
		_m4_bodies.append(body)
		var trigger: Area3D = Area3D.new()
		trigger.name = "M4Boundary%d" % index
		trigger.position = body.home + Vector3(0.6, 0, 0)
		trigger.collision_layer = 0
		trigger.collision_mask = 4
		var trigger_shape: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = Vector3(0.5, 1, 1)
		trigger_shape.shape = box
		trigger.add_child(trigger_shape)
		trigger.body_entered.connect(func(_body: Node3D) -> void: _m4_trigger_entries += 1)
		root.add_child(trigger)
		_m4_triggers.append(trigger)
	_m4_listener = TCPServer.new()
	if _m4_listener.listen(int(OS.get_environment("M4_HTTP_PORT")), "127.0.0.1") != OK:
		_m4_report["errors"].append("isolated_http_bind_failed")
	_m4_background = ProvisionalSectorGeneratorScript.new()
	_m4_background.ollama_host = "http://127.0.0.1:" + OS.get_environment("M4_HTTP_PORT")
	_m4_background.request_timeout_sec = 1.0
	_m4_background.provisional_sector_ready.connect(func(sector: String, result: Dictionary) -> void:
		_m4_background_results.append({"sector": sector, "outcome": result.get("request_outcome"), "timing": result.get("timing", {})}))
	root.add_child(_m4_background)
	_m4_report["configured_tick_rate"] = Engine.physics_ticks_per_second
	_m4_report["timing_seam"] = "EngineProfiler._tick physics_time; complete Main::iteration physics span; one physics tick per callback required"
	_m4_report["engine"] = Engine.get_version_info()
	_m4_report["status"] = "setup_ready"
	_m4_write()

func _m4_blueprint(index: int) -> Dictionary:
	var tiles: Array[Dictionary] = []
	for x: int in range(-8, 9):
		for y: int in range(-8, 9):
			tiles.append({"x": x, "y": y, "kind": "floor"})
	return {"schema_version": 5, "sector_id": SECTORS[index],
		"detail_origin": {"x": 437 if index % 2 == 0 else 2, "y": 437 if index < 2 else 2},
		"origin": {"x": 0, "y": 0}, "tiles": tiles, "structures": []}

func _default_town_anchor_defs() -> Array:
	var definitions: Array = []
	for index: int in range(10):
		definitions.append({"anchor_id": "m4-anchor-%d" % index, "role": "explorer", "desired_capacity": 1,
			"home_position": Vector3(437 + index % 5, 1, 438 if index < 5 else 442),
			"routine_steps": [{"activity_id": "patrol_a", "duration_ticks": 30}, {"activity_id": "patrol_b", "duration_ticks": 30}],
			"activity_locations": {"patrol_a": Vector3(438 + index % 5, 1, 438 if index < 5 else 442), "patrol_b": Vector3(439 + index % 5, 1, 438 if index < 5 else 442)}})
	return definitions

func _on_player_state_character_bound(peer_id: int, display_name: String, cosmetic: Dictionary) -> void:
	var state: Node = _player_states.get(peer_id)
	if state != null and String(state.character_id).begins_with("m4-player-"):
		var index: int = String(state.character_id).get_slice("-", 2).to_int()
		state.restore_authoritative_position(Vector3(439.5, 1, 438.5 if index < 5 else 441.5))
	super(peer_id, display_name, cosmetic)

func _inspect_canon_base(sector_id: String) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	var result: Dictionary = super(sector_id)
	if _m4_started and not _m4_finished:
		_m4_report["canon_reads"].append({"tick": Engine.get_physics_frames(), "sector_id": sector_id,
			"duration_usec": Time.get_ticks_usec() - started, "outcome": result.get("outcome")})
	return result

func _on_player_state_position_updated(peer_id: int, updated_position: Vector3) -> void:
	super(peer_id, updated_position)
	var sector: String = SectorBoundaryDetectorScript.sector_id_for_position(updated_position)
	if _m4_started and not _m4_finished and _m4_seen.has(peer_id) and _m4_seen[peer_id] != sector:
		_m4_report["crossings"].append({"tick": Engine.get_physics_frames(), "peer": peer_id, "from": _m4_seen[peer_id], "to": sector})
	_m4_seen[peer_id] = sector

func _m4_tick(frame_time: float, process_time: float, physics_time: float, physics_frame_time: float) -> void:
	if _m4_finished or _m4_bodies.is_empty():
		return
	while _m4_listener.is_connection_available():
		_m4_connections.append(_m4_listener.take_connection())
	var frame: int = Engine.get_physics_frames()
	var step_count: int = frame - _m4_last_frame
	_m4_last_frame = frame
	if step_count == 0:
		return
	var peers: int = 0
	var ready: int = 0
	var sectors: Dictionary = {}
	for peer_id: int in _player_states:
		var state: Node = _player_states[peer_id]
		if state._gameplay_authorized():
			peers += 1
			sectors[SectorBoundaryDetectorScript.sector_id_for_position(state.position)] = true
			if _frontier_position_ready(peer_id, state.position):
				ready += 1
	for body: MovingBody in _m4_bodies:
		sectors[SectorBoundaryDetectorScript.sector_id_for_position(body.position)] = true
	if not _m4_started:
		_m4_ready_ticks = _m4_ready_ticks + 1 if peers == 10 and ready == 10 else 0
		if _m4_ready_ticks < 60:
			return
		_m4_started = true
		_m4_start_usec = Time.get_ticks_usec()
		_m4_report["status"] = "measuring"
		_m4_report["start_tick"] = frame + 1
		return
	if step_count != 1:
		_m4_report["errors"].append("multiple_physics_ticks_in_profiler_iteration")
	var sample: Dictionary = {"tick": frame, "duration_ms": physics_time * 1000.0,
		"engine_frame_ms": frame_time * 1000.0, "engine_process_ms": process_time * 1000.0,
		"physics_step_seconds": physics_frame_time, "monotonic_usec": Time.get_ticks_usec(),
		"peers": peers, "ready": ready, "sectors": sectors.size(), "npcs": _town_npc_manager.npc_count(),
		"bodies": _m4_bodies.size(), "triggers": _m4_triggers.size(), "trigger_entries": _m4_trigger_entries}
	_m4_report["samples"].append(sample)
	var count: int = _m4_report["samples"].size()
	if count == 10:
		_m4_start_worker_probe()
		# Concurrent real asynchronous generation requests wait on a private loopback endpoint.
		for index: int in range(4):
			_m4_background.request_provisional_sector("sector-%d-10" % index, "Isolated M4 bounded fixture")
	_m4_poll_workers()
	if count == 20:
		_m4_inject_sector_fault()
	if count >= _m4_required_ticks:
		_m4_finish()

func _m4_start_worker_probe() -> void:
	for _index: int in range(32):
		var probe: WorkerProbe = WorkerProbe.new()
		_m4_worker_objects.append(probe)
		_m4_worker_tasks.append(WorkerThreadPool.add_task(probe.run))

func _m4_poll_workers() -> void:
	var completed: int = 0
	for task: int in _m4_worker_tasks:
		if WorkerThreadPool.is_task_completed(task):
			completed += 1
	_m4_worker_completed = completed
	_m4_worker_peak_pending = maxi(_m4_worker_peak_pending, _m4_worker_tasks.size() - completed)

func _m4_join_worker(task: int) -> void:
	var started: int = Time.get_ticks_usec()
	WorkerThreadPool.wait_for_task_completion(task)
	if _m4_started and not _m4_finished:
		_m4_blocking_wait_calls += 1
		_m4_blocking_wait_usec += Time.get_ticks_usec() - started

func _m4_seed_sector_fault() -> void:
	# Only a fifth, never-occupied fixture sector is corrupted. Other Canon is compared exactly.
	var blueprint: Dictionary = _m4_blueprint(0)
	blueprint["sector_id"] = "sector-5-5"
	var seeded: Dictionary = _canon_repository.canonicalize_blueprint(blueprint)
	var store: SqliteStore = _canon_store if _canon_store != null else _accounts_store
	var damaged: Dictionary = store.query("UPDATE canon_sectors SET blueprint_json = '{' WHERE sector_id = 'sector-5-5';")
	_m4_fault = {"seeded": seeded.get("outcome"), "damage_applied": damaged.get("outcome")}

func _m4_inject_sector_fault() -> void:
	var peer_id: int = int(_player_states.keys()[0])
	_reload_sector_from_boundary(peer_id, "sector-5-5", Vector3(2202, 1, 2202))
	_m4_fault["quarantine"] = sector_quarantine_evidence()
	_m4_fault["tick"] = Engine.get_physics_frames()
	_m4_fault["peer"] = peer_id

func _m4_healthy_rows() -> Array:
	var store: SqliteStore = _canon_store if _canon_store != null else _accounts_store
	var result: Dictionary = store.query("SELECT * FROM canon_sectors WHERE sector_id IN ('sector-0-0','sector-1-0','sector-0-1','sector-1-1') ORDER BY sector_id;")
	return result.get("rows", [])

func _m4_finish() -> void:
	_m4_finished = true
	_m4_report["elapsed_seconds"] = float(Time.get_ticks_usec() - _m4_start_usec) / 1000000.0
	for task: int in _m4_worker_tasks:
		_m4_join_worker(task)
	_m4_report["worker_probe"] = {"tasks": _m4_worker_tasks.size(), "peak_pending": _m4_worker_peak_pending,
		"completed_before_window_end": _m4_worker_completed,
		"results": _m4_worker_objects.map(func(probe: WorkerProbe) -> Dictionary: return {"iterations": probe.iterations, "thread_id": probe.thread_id}),
		"main_thread_id": OS.get_main_thread_id(), "blocking_wait_calls_in_window": _m4_blocking_wait_calls,
		"blocking_wait_usec_in_window": _m4_blocking_wait_usec,
		"scope": "Application-owned worker probe explicit waits only. Native engine synchronization is not observed. Joins occur after measured window."}
	_m4_report["body_activity"] = _m4_bodies.map(func(body: MovingBody) -> Dictionary: return {"steps": body.steps, "travel": body.travel})
	_m4_report["fault"] = _m4_fault
	_m4_report["background"] = {"accepted_connections": _m4_connections.size(), "results": _m4_background_results}
	_m4_report["isolation"] = {
		"healthy_canon_unchanged": _m4_healthy_before.size() == 4 and _m4_healthy_before == _m4_healthy_rows(),
		"sector_fault_contained": _m4_fault.get("quarantine", {}).get("quarantined", {}).has("sector-5-5"),
		"background_contention_observed": _m4_connections.size() == 4 and _m4_background_results.size() == 4 and _m4_worker_completed == 32 and _m4_worker_peak_pending > 0,
		"structural_nonblocking_verified": false,
		"lock_wait_observed": _m4_worker_completed == 32 and _m4_blocking_wait_calls == 0 and _m4_blocking_wait_usec == 0,
		"limitation": "Only bounded application-owned worker contention and explicit main-thread waits are measured; native engine synchronization and arbitrary worker failures are outside this probe."
	}
	_m4_report["status"] = "complete"
	_m4_write()
	quit(0)

func _m4_write() -> void:
	var path: String = OS.get_environment("M4_OBSERVATION")
	var file: FileAccess = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string(JSON.stringify(_m4_report))
	file.close()
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		quit(1)

func _finalize() -> void:
	if EngineDebugger.has_profiler("m4"):
		EngineDebugger.unregister_profiler("m4")
	super()
