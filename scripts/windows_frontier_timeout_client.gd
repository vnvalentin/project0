extends SceneTree

const SCENARIO: String = "frontier-timeout-v1"
const FRONTIER_SECTOR: String = "sector-0--1"
const FRONTIER_EDGE_Z: float = -440.0
const INSIDE_Z: float = -444.0
const OUTSIDE_Z: float = -436.0
const FRAME_BUDGET_MS: float = 16.6
var _network: Node
var _gameplay: Node3D
var _output: String
var _stop: String
var _deadline: int
var _authenticated := false
var _world_entered := false
var _position: Vector3 = Vector3.ZERO
var _frontier_started_at_msec: int = -1
var _frontier_geometry_ready_at_msec: int = -1
var _frontier_crossed_at_msec: int = -1
var _frontier_geometry_ready := false
var _frontier_crossed := false
var _x_at_start: float = NAN
var _x_at_ready: float = NAN
var _window_frame_ms: Array[float] = []
var _all_frames: int = 0
var _reentry: Dictionary = {"left": false, "reentered": false, "left_at_msec": -1, "reentered_at_msec": -1}
var _report: Dictionary = {"status": "failed", "scenario_id": SCENARIO, "authenticated": false, "world_entered": false}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 7:
		quit(1)
		return
	_output = arguments[2]
	_stop = arguments[3]
	_deadline = Time.get_ticks_msec() + 120000
	var ready: Variant = JSON.parse_string(FileAccess.get_file_as_string(arguments[4]))
	if not ready is Dictionary or ready.get("scenario_id") != SCENARIO:
		await _finish("readiness identity missing")
		return
	for key: String in ["schema_version", "run_id", "scenario_id", "correlation_id", "client_build", "server_build"]:
		_report[key] = ready[key]
	_report["client_id"] = arguments[0]
	_report["character_id"] = arguments[1]
	if FileAccess.get_sha256(arguments[5]) != ready["client_build"]["sha256"] or ClassDB.class_exists("SQLite"):
		await _finish("client package or dependency mismatch")
		return
	_network = root.get_node_or_null("NetworkClient")
	if _network == null:
		await _finish("packed NetworkClient missing")
		return
	_network.session_established_received.connect(func(outcome: String) -> void: _authenticated = outcome == "ok")
	_network.world_entry_received.connect(func(outcome: String, _character: Dictionary) -> void: _world_entered = outcome == "ok")
	_network.authoritative_position_received.connect(_on_authoritative_position)
	_network.geometry_assembly_completed.connect(_on_geometry_assembly_completed)
	_gameplay = load("res://client/gameplay.tscn").instantiate() as Node3D
	root.add_child(_gameplay)
	current_scene = _gameplay
	_network.connect_to_server(String(ready["host"]), int(ready["port"]))
	if not await _wait_for(func() -> bool: return _network.status == "connected: player spawned"):
		await _finish("connection")
		return
	_network.submit_present_assertion(FileAccess.get_file_as_string(arguments[6]).strip_edges())
	if not await _wait_for(func() -> bool: return _authenticated):
		await _finish("session")
		return
	_report["authenticated"] = true
	_network.submit_enter_world()
	if not await _wait_for(func() -> bool: return _world_entered):
		await _finish("world entry")
		return
	_report["world_entered"] = true
	# Strafing inside loaded terrain while the frontier holds shows adjacent responsiveness.
	Input.action_press("move_forward")
	Input.action_press("move_right")
	if not await _sample_until(func() -> bool: return _frontier_crossed and _position.z <= INSIDE_Z):
		await _finish("frontier crossing")
		return
	Input.action_release("move_right")
	Input.action_release("move_forward")
	Input.action_press("move_back")
	if not await _sample_until(func() -> bool: return _position.z >= OUTSIDE_Z):
		await _finish("leave sector")
		return
	_reentry["left"] = true
	_reentry["left_at_msec"] = Time.get_ticks_msec()
	Input.action_release("move_back")
	Input.action_press("move_forward")
	if not await _sample_until(func() -> bool: return _position.z <= INSIDE_Z):
		await _finish("re-enter sector")
		return
	_reentry["reentered"] = true
	_reentry["reentered_at_msec"] = Time.get_ticks_msec()
	Input.action_release("move_forward")
	_report["status"] = "passed"
	await _sample_until(func() -> bool: return FileAccess.file_exists(_stop))
	await _finish("coordinator stop" if FileAccess.file_exists(_stop) else "deadline")


func _sample_until(condition: Callable) -> bool:
	var previous_usec: int = Time.get_ticks_usec()
	while not bool(condition.call()) and Time.get_ticks_msec() < _deadline:
		await process_frame
		var now_usec: int = Time.get_ticks_usec()
		_all_frames += 1
		if _frontier_started_at_msec >= 0 and not _frontier_geometry_ready:
			_window_frame_ms.append(float(now_usec - previous_usec) / 1000.0)
		previous_usec = now_usec
		_write_report()
	return bool(condition.call())


func _wait_for(condition: Callable) -> bool:
	while not bool(condition.call()) and Time.get_ticks_msec() < _deadline:
		await process_frame
	return bool(condition.call())


func _on_authoritative_position(position: Vector3, _last_processed_sequence: int) -> void:
	_position = position
	if position.z <= FRONTIER_EDGE_Z + 1.0 and _frontier_started_at_msec < 0:
		_frontier_started_at_msec = Time.get_ticks_msec()
		_x_at_start = position.x
	if position.z < FRONTIER_EDGE_Z and not _frontier_crossed:
		_frontier_crossed = true
		_frontier_crossed_at_msec = Time.get_ticks_msec()


func _on_geometry_assembly_completed(sector_id: String, result: Dictionary) -> void:
	if sector_id != FRONTIER_SECTOR or result.get("outcome", "") != "valid" or _frontier_geometry_ready:
		return
	_frontier_geometry_ready = true
	_frontier_geometry_ready_at_msec = Time.get_ticks_msec()
	_x_at_ready = _position.x


func _frame_stats() -> Dictionary:
	var sorted: Array[float] = _window_frame_ms.duplicate()
	sorted.sort()
	var over: int = sorted.filter(func(value: float) -> bool: return value > FRAME_BUDGET_MS).size()
	return {
		"count": sorted.size(), "all_frames": _all_frames, "budget_ms": FRAME_BUDGET_MS, "over_budget": over,
		"p50_ms": _percentile(sorted, 0.50), "p95_ms": _percentile(sorted, 0.95),
		"p99_ms": _percentile(sorted, 0.99), "max_ms": sorted.back() if not sorted.is_empty() else -1.0,
		"window": "frontier start until generated geometry ready",
	}


static func _percentile(sorted: Array[float], fraction: float) -> float:
	if sorted.is_empty():
		return -1.0
	return sorted[mini(sorted.size() - 1, int(ceil(fraction * sorted.size())) - 1)]


func _write_report() -> void:
	_report["frontier"] = {
		"sector_id": FRONTIER_SECTOR,
		"geometry_ready": _frontier_geometry_ready,
		"crossed": _frontier_crossed,
		"started_at_msec": _frontier_started_at_msec,
		"geometry_ready_at_msec": _frontier_geometry_ready_at_msec,
		"crossed_at_msec": _frontier_crossed_at_msec,
		"ready_latency_ms": _frontier_geometry_ready_at_msec - _frontier_started_at_msec if _frontier_geometry_ready_at_msec >= 0 and _frontier_started_at_msec >= 0 else -1,
		"cross_latency_ms": _frontier_crossed_at_msec - _frontier_started_at_msec if _frontier_crossed_at_msec >= 0 and _frontier_started_at_msec >= 0 else -1,
	}
	_report["frame_times"] = _frame_stats()
	_report["adjacent_motion"] = {"x_at_start": _x_at_start, "x_at_ready": _x_at_ready,
		"moved": is_finite(_x_at_start) and is_finite(_x_at_ready) and absf(_x_at_ready - _x_at_start) > 0.5}
	_report["reentry"] = _reentry
	_report["authoritative_position"] = [_position.x, _position.y, _position.z]
	_report["observed_at"] = Time.get_unix_time_from_system()
	var file := FileAccess.open(_output + ".pending", FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(_report))
	file.close()
	DirAccess.rename_absolute(_output + ".pending", _output)


func _finish(failure: String) -> void:
	for action: String in ["move_forward", "move_back", "move_right"]:
		Input.action_release(action)
	if failure != "coordinator stop":
		_report["status"] = "failed"
		_report["failure"] = failure
	_write_report()
	if is_instance_valid(_network):
		_network.disconnect_from_server()
	await process_frame
	await process_frame
	quit(0 if _report["status"] == "passed" else 1)
