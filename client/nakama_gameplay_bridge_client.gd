extends RefCounted
class_name NakamaGameplayBridgeClient
## Slice 180: optional Nakama match transport. Direct ENet/RPC remains default.

const ProtocolScript: Script = preload("res://shared/nakama_gameplay_bridge_protocol.gd")
const NetworkConfigScript: Script = preload("res://shared/network_config.gd")
const NakamaClientScript: Script = preload("res://addons/com.heroiclabs.nakama/client/NakamaClient.gd")

signal state_received(message: Dictionary)
signal error_received(message: Dictionary)

var _socket: Object = null
var _match_id: String = ""
var _nakama_user_id: String = ""
var _character_id: String = ""
var _next_sequence: int = 0


func enabled() -> bool:
	return NetworkConfigScript.client_nakama_gameplay_enabled()


func connect_shared_match(nakama: Object, auth_token: String, match_id: String = "") -> Dictionary:
	if not enabled() or nakama == null or auth_token.strip_edges().is_empty():
		return {"outcome": "disabled_or_unbound"}
	var base_url: String = NetworkConfigScript.resolve_nakama_base_url()
	var scheme: String = "https" if base_url.begins_with("https://") else "http"
	var host: String = base_url.trim_prefix("https://").trim_prefix("http://")
	var client: Object = nakama.call("create_client", NetworkConfigScript.resolve_nakama_server_key(), host, 7350, scheme)
	var session: Object = NakamaClientScript.restore_session(auth_token)
	if session == null or session.expired:
		return {"outcome": "expired_session"}
	_socket = nakama.call("create_socket_from", client)
	var connected: Object = await _socket.connect_async(session)
	if connected.is_exception():
		_socket.close()
		_socket = null
		return {"outcome": "connect_failed"}
	var resolved_match_id: String = match_id
	if resolved_match_id.is_empty():
		var created: Object = await _socket.create_match_async("project0-shared-world")
		if created.is_exception():
			return {"outcome": "match_create_failed"}
		resolved_match_id = String(created.match_id)
	else:
		var joined: Object = await _socket.join_match_async(resolved_match_id)
		if joined.is_exception():
			return {"outcome": "match_join_failed"}
	return {"outcome": ProtocolScript.OUTCOME_OK, "match_id": resolved_match_id, "socket": _socket}


func available() -> bool:
	return _socket != null and not _match_id.is_empty()


func submit_input(payload: Dictionary, sequence: int = 0) -> Dictionary:
	return submit_input_payload(payload, sequence)


func submit_input_payload(payload: Dictionary, sequence: int = 0) -> Dictionary:
	if _socket == null or _match_id.is_empty():
		return {"outcome": "unavailable"}
	if sequence <= 0:
		_next_sequence += 1
		sequence = _next_sequence
	else:
		_next_sequence = maxi(_next_sequence, sequence)
	var message: Dictionary = ProtocolScript.build_input(_nakama_user_id, _character_id, sequence, payload)
	var validation: Dictionary = ProtocolScript.validate(message, ProtocolScript.KIND_INPUT)
	if validation["outcome"] != ProtocolScript.OUTCOME_OK:
		return validation
	_socket.send_match_state_async(_match_id, 1701, JSON.stringify(message))
	return {"outcome": ProtocolScript.OUTCOME_OK, "message": message}


func attach(socket: Object, match_id: String, nakama_user_id: String, character_id: String) -> Dictionary:
	if not enabled() or socket == null or match_id.strip_edges().is_empty() or nakama_user_id.strip_edges().is_empty() or character_id.strip_edges().is_empty():
		return {"outcome": "disabled_or_unbound"}
	_socket = socket
	_match_id = match_id
	_nakama_user_id = nakama_user_id
	_character_id = character_id
	_socket.received_match_state.connect(_on_match_state)
	return {"outcome": ProtocolScript.OUTCOME_OK}


func _on_match_state(data: Variant) -> void:
	var parsed: Variant = data.data if data != null and "data" in data else data
	if parsed is String:
		parsed = JSON.parse_string(parsed)
	if not (parsed is Dictionary):
		return
	var validation: Dictionary = ProtocolScript.validate(parsed)
	if validation["outcome"] != ProtocolScript.OUTCOME_OK:
		return
	if parsed["kind"] == ProtocolScript.KIND_STATE:
		state_received.emit(parsed)
	elif parsed["kind"] == ProtocolScript.KIND_ERROR:
		error_received.emit(parsed)