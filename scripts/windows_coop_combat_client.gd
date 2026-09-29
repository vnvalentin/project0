extends SceneTree

const SCENARIO: String = "coop-combat-v1"
const TARGET_ID: String = "target_dummy_0"
const TARGET_POSITION := Vector3(0.0, 1.0, -2.0)
const CombatContractsScript: Script = preload("res://shared/combat_contracts.gd")
var _network: Node
var _gameplay: Node3D
var _client_id: String
var _character_id: String
var _output: String
var _stop: String
var _deadline: int
var _authenticated := false
var _world_entered := false
var _resolution: Dictionary = {}
var _hit_event: Dictionary = {}
var _report: Dictionary = {"status": "failed", "scenario_id": SCENARIO,
	"authenticated": false, "world_entered": false}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	print("COOP_COMBAT_ARGS ", arguments.size())
	if arguments.size() != 7:
		push_error("coop combat probe expected 7 user arguments")
		quit(1)
		return
	_client_id = arguments[0]
	_character_id = arguments[1]
	_output = arguments[2]
	_stop = arguments[3]
	_deadline = Time.get_ticks_msec() + 120000
	var ready: Variant = JSON.parse_string(FileAccess.get_file_as_string(arguments[4]))
	if not ready is Dictionary or ready.get("scenario_id") != SCENARIO:
		push_error("coop combat probe readiness identity missing")
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
	_network.action_resolution_received.connect(_on_resolution)
	_network.combat_event_received.connect(_on_combat_event)
	_gameplay = load("res://client/gameplay.tscn").instantiate() as Node3D
	root.add_child(_gameplay)
	current_scene = _gameplay
	_network.connect_to_server(String(ready["host"]), int(ready["port"]))
	if not await _wait_for(func() -> bool: return _network.status == "connected: player spawned"):
		await _finish("connection")
		return
	_network.submit_present_assertion(FileAccess.get_file_as_string(arguments[6]).strip_edges())
	if not await _wait_for(func() -> bool: return _authenticated):
		push_error("coop combat probe session admission timed out")
		await _finish("session")
		return
	_report["authenticated"] = true
	_network.submit_enter_world()
	if not await _wait_for(func() -> bool: return _world_entered):
		push_error("coop combat probe world entry timed out")
		await _finish("world entry")
		return
	_report["world_entered"] = true
	if _client_id == "a":
		await _move_to_target_and_strike()
	if not await _wait_for(func() -> bool: return _client_id == "a" and not _resolution.is_empty() and not _hit_event.is_empty() or _client_id == "b" and not _hit_event.is_empty()):
		push_error("coop combat probe authoritative combat observation timed out")
		await _finish("authoritative combat observation")
		return
	_report["status"] = "passed"
	_write_report()
	while not FileAccess.file_exists(_stop) and Time.get_ticks_msec() < _deadline:
		await physics_frame
		_write_report()
	await _finish("coordinator stop" if FileAccess.file_exists(_stop) else "deadline")


func _move_to_target_and_strike() -> void:
	var player: Node3D = _gameplay.get_node_or_null("Player")
	if player == null:
		return
	Input.action_press("move_forward")
	Input.action_press("move_left")
	var move_ticks := 0
	while player.position.distance_to(TARGET_POSITION) > 1.5 and move_ticks < 300:
		await physics_frame
		move_ticks += 1
	Input.action_release("move_forward")
	Input.action_release("move_left")
	for _tick in 15:
		await physics_frame
	print("COOP_COMBAT_POSITION ", player.position)
	var aim_direction: Vector3 = TARGET_POSITION - player.position
	aim_direction.y = 0.0
	_network.submit_action_intent(0, Engine.get_physics_frames(), CombatContractsScript.ACTION_KIND_MELEE_STRIKE, aim_direction.normalized())


func _on_resolution(sequence: int, result: String, rejection_reason: String, server_tick: int) -> void:
	if sequence == 0:
		print("COOP_COMBAT_RESOLUTION ", result, " ", rejection_reason, " ", server_tick)
		_resolution = {"sequence": sequence, "result": result, "rejection_reason": rejection_reason,
			"server_tick": server_tick}
		_write_report()


func _on_combat_event(kind: String, attacker_peer_id: int, target_id: String, _impact_position: Vector3, server_tick: int) -> void:
	if kind == CombatContractsScript.COMBAT_EVENT_HIT and target_id == TARGET_ID:
		print("COOP_COMBAT_HIT ", attacker_peer_id, " ", server_tick)
		_hit_event = {"kind": kind, "attacker_peer_id": attacker_peer_id, "target_id": target_id,
			"server_tick": server_tick}
		_write_report()


func _wait_for(condition: Callable) -> bool:
	while not bool(condition.call()) and Time.get_ticks_msec() < _deadline:
		await process_frame
	return bool(condition.call())


func _write_report() -> void:
	_report["resolution"] = _resolution
	_report["hit_event"] = _hit_event
	_report["observed_at"] = Time.get_unix_time_from_system()
	var file := FileAccess.open(_output + ".pending", FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(_report))
	file.close()
	DirAccess.rename_absolute(_output + ".pending", _output)


func _finish(failure: String) -> void:
	print("COOP_COMBAT_FINISH ", failure)
	Input.action_release("move_forward")
	Input.action_release("move_left")
	if failure != "coordinator stop":
		_report["failure"] = failure
		_write_report()
	if is_instance_valid(_network):
		_network.disconnect_from_server()
	await process_frame
	await process_frame
	quit(0 if _report["status"] == "passed" else 1)
