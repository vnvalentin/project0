extends SceneTree
## Linux supporting load peer. Uses production client admission and geometry readiness.
const Session: Script = preload("res://scripts/gameplay_test_session.gd")
const Config: Script = preload("res://shared/network_config.gd")
var _position: Vector3 = Vector3(439.5, 1, 438.5)
var _updates: int = 0
var _result: Dictionary = {"entered": false, "updates": 0, "error": null}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	OS.set_environment(Session.ASSERTION_ENV, FileAccess.get_file_as_string(OS.get_environment("M4_ASSERTION_PATH")))
	var network: Node = root.get_node("NetworkClient")
	var gameplay: Node = load("res://client/gameplay.tscn").instantiate()
	root.add_child(gameplay)
	current_scene = gameplay
	await process_frame
	network.authoritative_position_received.connect(func(position: Vector3, _sequence: int) -> void:
		_position = position
		_updates += 1)
	network.connect_to_server("127.0.0.1", Config.resolve_server_port())
	if not await Session.enter_world(network):
		_result["error"] = "admission_failed"
		_finish()
		return
	_result["entered"] = true
	var deadline: int = Time.get_ticks_msec() + 150000
	var direction: String = "move_right"
	Input.action_press(direction)
	while Time.get_ticks_msec() < deadline and not FileAccess.file_exists(OS.get_environment("M4_STOP")):
		await physics_frame
		var next: String = direction
		if _position.x > 441.0:
			next = "move_left"
		elif _position.x < 439.0:
			next = "move_right"
		if next != direction:
			Input.action_release(direction)
			direction = next
			Input.action_press(direction)
	Input.action_release(direction)
	_result["stopped_by_owner"] = FileAccess.file_exists(OS.get_environment("M4_STOP"))
	_finish()

func _finish() -> void:
	_result["updates"] = _updates
	var file: FileAccess = FileAccess.open(OS.get_environment("M4_PEER_RESULT"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_result))
		file.close()
	quit(0 if _result["error"] == null else 1)
