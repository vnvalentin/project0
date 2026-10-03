extends "res://server/server_main.gd"


func _start_server() -> void:
	await super._start_server()
	var ready_path: String = OS.get_environment("PROJECT0_TEST_SERVER_READY_FILE")
	if ready_path.is_empty():
		return
	if _peer == null or _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED or _operator_control_endpoint == null:
		quit(1)
		return
	var control_listener: TCPServer = _operator_control_endpoint.get("_server")
	if control_listener == null or not control_listener.is_listening():
		quit(1)
		return
	var ready: Dictionary = {
		"process_id": OS.get_process_id(),
		"nonce": OS.get_environment("PROJECT0_TEST_SERVER_NONCE"),
		"game_port": _peer.host.get_local_port(),
		"control_port": control_listener.get_local_port(),
	}
	var output: FileAccess = FileAccess.open(ready_path + ".pending", FileAccess.WRITE)
	if output == null:
		push_error("Owned server readiness publication failed")
		quit(1)
		return
	output.store_string(JSON.stringify(ready))
	output.close()
	if DirAccess.rename_absolute(ready_path + ".pending", ready_path) != OK:
		push_error("Owned server readiness publication failed")
		quit(1)


func _on_peer_connected(peer_id: int) -> void:
	super._on_peer_connected(peer_id)
	_peer.get_peer(peer_id).set_timeout(32, 1000, 5000)