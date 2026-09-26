extends SceneTree

const TIMEOUT_MS: int = 15000

var _network: Node
var _transport_peer: ENetMultiplayerPeer
var _evidence_path: String = ""
var _world_outcome: String = ""
var _world_character: Dictionary = {}
var _positions: Array[Vector3] = []
var _version_rejection: String = ""
var _house_received: bool = false
var _connection_lost: bool = false
var _result: Dictionary = {
	"experiment_id": "exp_1101_gameplay_admission",
	"scenario": "missing_assertion",
	"passed": false,
	"failure": "",
}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_evidence_path = OS.get_environment("PROJECT0_1101_EVIDENCE")
	var host: String = OS.get_environment("PROJECT0_1101_GAME_HOST")
	var port_text: String = OS.get_environment("PROJECT0_1101_GAME_PORT")
	if _evidence_path.is_empty() or host.is_empty() or not port_text.is_valid_int():
		_finish("missing_configuration")
		return
	var port: int = int(port_text)
	if port < 1 or port > 65535:
		_finish("invalid_port")
		return
	_network = root.get_node("NetworkClient")
	_network.world_entry_received.connect(_on_world_entry)
	_network.authoritative_position_received.connect(_on_position)
	_network.version_handshake_rejected.connect(_on_version_rejection)
	root.multiplayer.server_disconnected.connect(_on_server_disconnected)
	var probe_mode: String = OS.get_environment("PROJECT0_1101_PROBE_MODE")
	_result["probe_mode"] = probe_mode
	_result["authentication_exercised"] = probe_mode == "MissingSession"
	if probe_mode == "Offline":
		_result["scenario"] = "offline_shutdown"
		_finish("")
		return
	if probe_mode == "VersionSignal":
		_result["scenario"] = "version_rejection_signal_contract"
		_result["simulated_signal"] = true
		_network.receive_version_handshake_rejected({"outcome": "DIAGNOSTIC_VERSION_REJECTION"})
		_finish("" if _version_rejection == "DIAGNOSTIC_VERSION_REJECTION" else "version_signal_failed")
		return
	if probe_mode == "Transport":
		_result["scenario"] = "transport_shutdown"
		_transport_peer = ENetMultiplayerPeer.new()
		if _transport_peer.create_client(host, port) != OK:
			_finish("transport_start_failed")
			return
		var transport_deadline: int = Time.get_ticks_msec() + TIMEOUT_MS
		while _transport_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING and Time.get_ticks_msec() < transport_deadline:
			_transport_peer.poll()
			await process_frame
		var connected: bool = _transport_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
		_result["transport_connected"] = connected
		_finish("" if connected else "transport_connect_failed")
		return
	if probe_mode == "VersionRPC":
		_result["scenario"] = "version_rpc_shutdown"
		_network.assigned_house_received.connect(_on_house_received)
		_network.connect_to_server(host, port)
		var rpc_deadline: int = Time.get_ticks_msec() + TIMEOUT_MS
		while not _house_received and _version_rejection.is_empty() and not _connection_lost and Time.get_ticks_msec() < rpc_deadline:
			await process_frame
		_result["server_rpc_received"] = _house_received
		_finish("" if _house_received else "version_rpc_failed")
		return
	var scene: PackedScene = load("res://client/character_gate.tscn")
	var character_gate: Node = scene.instantiate()
	root.add_child(character_gate)
	current_scene = character_gate
	await process_frame
	_network.connect_to_server(host, port)
	var deadline: int = Time.get_ticks_msec() + TIMEOUT_MS
	while not String(_network.status).begins_with("connected") and _version_rejection.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	if not _version_rejection.is_empty() or not String(_network.status).begins_with("connected"):
		_result["version_rejection"] = _version_rejection
		_finish("connection_or_version_failed")
		return
	_network.submit_enter_world()
	deadline = Time.get_ticks_msec() + TIMEOUT_MS
	while _world_outcome.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	_result["world_entry_outcome"] = _world_outcome
	_result["character_bound"] = not _world_character.is_empty()
	if _world_outcome != "NOT_AUTHENTICATED" or not _world_character.is_empty():
		_finish("unauthenticated_world_entry_not_rejected")
		return
	_positions.clear()
	var sequence: int = 1
	deadline = Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < deadline:
		_network.submit_input_intent(Vector2.RIGHT, sequence)
		sequence += 1
		await physics_frame
	var displacement: float = 0.0
	if _positions.size() > 1:
		displacement = _positions[0].distance_to(_positions[-1])
	_result["authoritative_state_count"] = _positions.size()
	_result["motion_observed"] = _positions.size() > 1
	_result["unauthenticated_displacement"] = displacement if _positions.size() > 1 else null
	_result["input_intents_sent"] = sequence - 1
	_result["connection_status_before_shutdown"] = String(_network.status)
	_result["gameplay_scene_entered"] = current_scene != null and current_scene.scene_file_path == "res://client/gameplay.tscn"
	if not String(_network.status).begins_with("connected"):
		_finish("connection_lost_during_probe")
		return
	if displacement > 0.01:
		_finish("unauthenticated_authoritative_movement")
		return
	if bool(_result["gameplay_scene_entered"]):
		_finish("unauthenticated_gameplay_scene")
		return
	_finish("")


func _on_world_entry(outcome: String, character: Dictionary) -> void:
	_world_outcome = outcome
	_world_character = character


func _on_position(position: Vector3, _sequence: int) -> void:
	_positions.append(position)


func _on_version_rejection(rejection: Dictionary) -> void:
	_version_rejection = String(rejection.get("outcome", "version_rejected"))
	_result["version_rejection"] = _version_rejection


func _on_server_disconnected() -> void:
	_connection_lost = true
	_result["server_disconnected"] = true
	if _network != null and _network.get_parent() == root:
		root.remove_child(_network)


func _on_house_received(_house_id: String) -> void:
	_house_received = true


func _finish(failure: String) -> void:
	_result["failure"] = failure
	_result["passed"] = failure.is_empty()
	_result["host"] = OS.get_environment("COMPUTERNAME")
	if _transport_peer != null:
		_transport_peer.close()
		_transport_peer = null
	if _network != null:
		if _network.get_parent() == root:
			root.remove_child(_network)
		_network.free()
		_network = null
	var multiplayer_api: MultiplayerAPI = root.multiplayer
	if multiplayer_api.multiplayer_peer != null:
		multiplayer_api.multiplayer_peer.close()
		multiplayer_api.multiplayer_peer = null
	multiplayer_api.clear()
	if current_scene != null:
		current_scene.free()
		current_scene = null
	if not _evidence_path.is_empty():
		var output: FileAccess = FileAccess.open(_evidence_path, FileAccess.WRITE)
		if output == null:
			push_error("Experiment evidence write failed")
			quit(1)
			return
		output.store_string(JSON.stringify(_result))
		output.close()
	print(JSON.stringify(_result))
	quit(0 if failure.is_empty() else 1)