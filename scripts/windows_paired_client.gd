extends SceneTree

var _network: Node
var _gameplay: Node3D
var _session: String = ""
var _world: String = ""
var _ack: int = -1
var _output: String = ""
var _stop: String = ""
var _deadline: int = 0
var _report: Dictionary = {"status": "failed", "authenticated": false, "world_entered": false, "input_ack_sequence": -1}


func _initialize() -> void:
	call_deferred("_run")


func _wait_for(condition: Callable, phase: String) -> bool:
	while not bool(condition.call()) and Time.get_ticks_msec() < _deadline:
		await process_frame
	if not bool(condition.call()):
		_report["failure"] = phase
		return false
	return true


func _run() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.size() != 5:
		quit(1)
		return
	_output = arguments[2]
	_stop = arguments[3]
	_deadline = Time.get_ticks_msec() + 120000
	var ready: Variant = JSON.parse_string(FileAccess.get_file_as_string(arguments[0]))
	if not ready is Dictionary or ready.get("status") != "ready":
		await _finish(false, "readiness identity missing")
		return
	for key: String in ["schema_version", "run_id", "scenario_id", "correlation_id", "client_build", "server_build"]:
		_report[key] = ready[key]
	if FileAccess.get_sha256(arguments[4]) != ready["client_build"]["sha256"] or ClassDB.class_exists("SQLite"):
		await _finish(false, "client package or dependency mismatch")
		return
	_network = root.get_node_or_null("NetworkClient")
	if _network == null:
		await _finish(false, "packed NetworkClient missing")
		return
	_network.session_established_received.connect(func(outcome: String) -> void: _session = outcome)
	_network.world_entry_received.connect(func(outcome: String, _character: Dictionary) -> void: _world = outcome)
	_network.authoritative_position_received.connect(func(_position: Vector3, sequence: int) -> void: _ack = maxi(_ack, sequence))
	_gameplay = load("res://client/gameplay.tscn").instantiate() as Node3D
	root.add_child(_gameplay)
	current_scene = _gameplay
	_network.connect_to_server(String(ready["host"]), int(ready["port"]))
	if not await _wait_for(func() -> bool: return _network.status == "connected: player spawned", "connection"):
		await _finish(false, "connection")
		return
	_network.submit_present_assertion(FileAccess.get_file_as_string(arguments[1]).strip_edges())
	if not await _wait_for(func() -> bool: return not _session.is_empty(), "session") or _session != "ok":
		await _finish(false, "session rejected")
		return
	_report["authenticated"] = true
	_network.submit_enter_world()
	if not await _wait_for(func() -> bool: return not _world.is_empty(), "world entry") or _world != "ok":
		await _finish(false, "world entry rejected")
		return
	_report["world_entered"] = true
	Input.action_press("move_back")
	if not await _wait_for(func() -> bool: return _ack >= 0, "input acknowledgement"):
		await _finish(false, "input acknowledgement")
		return
	Input.action_release("move_back")
	_report["input_ack_sequence"] = _ack
	_report["observed_at"] = Time.get_unix_time_from_system()
	_report["status"] = "passed"
	_write_report()
	var stopped: bool = await _wait_for(func() -> bool: return FileAccess.file_exists(_stop), "coordinator finish")
	await _finish(stopped, "coordinator finish")


func _write_report() -> void:
	var file: FileAccess = FileAccess.open(_output, FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string(JSON.stringify(_report, "\t"))
	file.close()


func _finish(passed: bool, failure: String) -> void:
	Input.action_release("move_back")
	if not passed:
		_report["status"] = "failed"
		_report["failure"] = failure
		_report["observed_at"] = Time.get_unix_time_from_system()
		_write_report()
	if is_instance_valid(_network):
		_network.disconnect_from_server()
	if is_instance_valid(_gameplay):
		_gameplay.queue_free()
	await process_frame
	await process_frame
	quit(0 if passed else 1)