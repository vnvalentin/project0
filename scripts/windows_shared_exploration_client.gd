extends SceneTree

const SCENARIO: String = "shared-exploration-v1"
const FRONTIER_SECTOR: String = "sector-1-0"
const FRONTIER_EDGE_X: float = 440.0
var _network: Node
var _gameplay: Node3D
var _client_id: String
var _character_id: String
var _output: String
var _stop: String
var _deadline: int
var _authenticated := false
var _world_entered := false
var _remote_identities: Dictionary = {}
var _authoritative_position: Vector3 = Vector3.ZERO
var _frontier_started_at_msec: int = -1
var _frontier_geometry_ready_at_msec: int = -1
var _frontier_crossed_at_msec: int = -1
var _frontier_geometry_ready := false
var _frontier_crossed := false
var _report: Dictionary = {"status": "failed", "scenario_id": SCENARIO,
	"authenticated": false, "world_entered": false, "remote_players": {}}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 7:
		quit(1)
		return
	_client_id = arguments[0]
	_character_id = arguments[1]
	_output = arguments[2]
	_stop = arguments[3]
	_deadline = Time.get_ticks_msec() + 120000
	var ready: Variant = JSON.parse_string(FileAccess.get_file_as_string(arguments[4]))
	if not ready is Dictionary or ready.get("scenario_id") != SCENARIO:
		await _finish("readiness identity missing")
		return
	for key: String in ["schema_version", "run_id", "scenario_id", "correlation_id", "client_build", "server_build"]:
		_report[key] = ready[key]
	_report["client_id"] = _client_id
	_report["character_id"] = _character_id
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
	_network.remote_player_identity_received.connect(_on_remote_identity)
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
	_report["status"] = "passed"
	Input.action_press("move_right")
	while not FileAccess.file_exists(_stop) and Time.get_ticks_msec() < _deadline:
		await physics_frame
		_write_report()
	Input.action_release("move_back")
	Input.action_release("move_forward")
	await _finish("coordinator stop" if FileAccess.file_exists(_stop) else "deadline")


func _wait_for(condition: Callable) -> bool:
	while not bool(condition.call()) and Time.get_ticks_msec() < _deadline:
		await process_frame
	return bool(condition.call())


func _on_remote_identity(peer_id: int, display_name: String, _cosmetic: Dictionary) -> void:
	_remote_identities[peer_id] = "a" if display_name.ends_with(" A") else "b"


func _on_authoritative_position(position: Vector3, _last_processed_sequence: int) -> void:
	_authoritative_position = position
	if position.x >= FRONTIER_EDGE_X - 1.0 and _frontier_started_at_msec < 0:
		_frontier_started_at_msec = Time.get_ticks_msec()
	if position.x > FRONTIER_EDGE_X and not _frontier_crossed:
		_frontier_crossed = true
		_frontier_crossed_at_msec = Time.get_ticks_msec()


func _on_geometry_assembly_completed(sector_id: String, result: Dictionary) -> void:
	if sector_id != FRONTIER_SECTOR or result.get("outcome", "") != "valid":
		return
	_frontier_geometry_ready = true
	if _frontier_geometry_ready_at_msec < 0:
		_frontier_geometry_ready_at_msec = Time.get_ticks_msec()


func _write_report() -> void:
	var remotes: Dictionary = {}
	var container: Node = _gameplay.get_node_or_null("RemotePlayers")
	if container != null:
		for child: Node3D in container.get_children():
			var peer_id: int = String(child.name).trim_prefix("RemotePlayer_").to_int()
			if _remote_identities.has(peer_id):
				var position: Array = [float(child.position.x), float(child.position.y), float(child.position.z)]
				remotes[_remote_identities[peer_id]] = {"position": position,
					"character_id": "shared-%s-%s" % [_report.get("run_id", ""), _remote_identities[peer_id]]}
	_report["remote_players"] = remotes
	_report["authoritative_position"] = [_authoritative_position.x, _authoritative_position.y, _authoritative_position.z]
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
	_report["own_position"] = _own_position()
	_report["observed_at"] = Time.get_unix_time_from_system()
	var file := FileAccess.open(_output + ".pending", FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(_report))
	file.close()
	DirAccess.rename_absolute(_output + ".pending", _output)


func _own_position() -> Array:
	var player: Node3D = _gameplay.get_node_or_null("Player")
	return [float(player.position.x), float(player.position.y), float(player.position.z)] if player != null else []


func _finish(failure: String) -> void:
	Input.action_release("move_right")
	if failure == "coordinator stop":
		_report["status"] = "passed"
	else:
		_report["failure"] = failure
	_write_report()
	if is_instance_valid(_network):
		_network.disconnect_from_server()
	await process_frame
	await process_frame
	quit(0 if _report["status"] == "passed" else 1)