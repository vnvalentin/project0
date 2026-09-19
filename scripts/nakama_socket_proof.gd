extends SceneTree
## Slice 179: isolated two-client relayed-match proof for the pinned Nakama
## Godot addon. It does not install NakamaMultiplayerBridge or Project0's
## multiplayer peer. Tokens are read only from environment variables.

const ProtocolScript: Script = preload("res://shared/nakama_gameplay_bridge_protocol.gd")
const NakamaClientScript: Script = preload("res://addons/com.heroiclabs.nakama/client/NakamaClient.gd")
const NakamaScript: Script = preload("res://addons/com.heroiclabs.nakama/Nakama.gd")
const OP_INPUT: int = 1701
const TIMEOUT_SECONDS: float = 10.0

var _socket_a: Object
var _socket_b: Object
var _match_id: String = ""
var _received_valid: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var server_key: String = OS.get_environment("PROJECT0_NAKAMA_SERVER_KEY").strip_edges()
	var host: String = OS.get_environment("PROJECT0_NAKAMA_HOST").strip_edges()
	var token_a: String = OS.get_environment("PROJECT0_NAKAMA_AUTH_TOKEN_A").strip_edges()
	var token_b: String = OS.get_environment("PROJECT0_NAKAMA_AUTH_TOKEN_B").strip_edges()
	if server_key.is_empty() or host.is_empty() or token_a.is_empty() or token_b.is_empty():
		_fail("PROJECT0_NAKAMA_HOST, SERVER_KEY, and both auth tokens are required")
		return

	var nakama: Node = NakamaScript.new()
	get_root().add_child(nakama)
	var client_a: Object = nakama.call("create_client", server_key, host, 7350, "http")
	var client_b: Object = nakama.call("create_client", server_key, host, 7350, "http")
	var session_a: Object = NakamaClientScript.restore_session(token_a)
	var session_b: Object = NakamaClientScript.restore_session(token_b)
	if session_a.expired or session_b.expired:
		_fail("proof tokens are expired")
		return

	_socket_a = nakama.call("create_socket_from", client_a)
	_socket_b = nakama.call("create_socket_from", client_b)
	_socket_b.received_match_state.connect(_on_match_state)
	var connected_a: Object = await _socket_a.connect_async(session_a)
	var connected_b: Object = await _socket_b.connect_async(session_b)
	if connected_a.is_exception() or connected_b.is_exception():
		_fail("socket connection failed")
		return

	var created: Object = await _socket_a.create_match_async()
	if created.is_exception() or String(created.match_id).is_empty():
		_fail("match creation failed")
		return
	_match_id = String(created.match_id)
	var joined: Object = await _socket_b.join_match_async(_match_id)
	if joined.is_exception():
		_fail("match join failed")
		return

	var envelope: Dictionary = ProtocolScript.build_input("proof-user-a", "proof-character-a", 1, {"move_x": 1.0, "move_z": 0.0})
	var valid: Dictionary = ProtocolScript.validate(envelope, ProtocolScript.KIND_INPUT)
	if valid["outcome"] != ProtocolScript.OUTCOME_OK:
		_fail("local protocol validation failed")
		return
	var sent: Object = await _socket_a.send_match_state_async(_match_id, OP_INPUT, JSON.stringify(envelope))
	if sent.is_exception():
		_fail("match state send failed")
		return

	var deadline: int = Time.get_ticks_msec() + int(TIMEOUT_SECONDS * 1000.0)
	while not _received_valid and Time.get_ticks_msec() < deadline:
		await process_frame
	if not _received_valid:
		_fail("valid envelope was not received")
		return

	await _socket_a.leave_match_async(_match_id)
	await _socket_b.leave_match_async(_match_id)
	_socket_a.close()
	_socket_b.close()
	print("Nakama socket proof passed: two clients, relayed match, validated envelope.")
	quit(0)


func _on_match_state(data: Variant) -> void:
	var parsed: Variant = JSON.parse_string(data.data)
	if parsed is Dictionary and ProtocolScript.validate(parsed, ProtocolScript.KIND_INPUT)["outcome"] == ProtocolScript.OUTCOME_OK:
		_received_valid = true


func _fail(detail: String) -> void:
	_cleanup_sockets()
	printerr("Nakama socket proof failed: %s" % detail)
	quit(1)


func _cleanup_sockets() -> void:
	if _socket_a != null:
		_socket_a.close()
		_socket_a = null
	if _socket_b != null:
		_socket_b.close()
		_socket_b = null
	_match_id = ""