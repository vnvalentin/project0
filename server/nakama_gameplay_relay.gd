extends Node
class_name NakamaGameplayRelay
## Slice 181: server-side Nakama socket relay. Nakama is transport only; the
## injected NakamaGameplayBridge owns identity, input validation, and state.

const NakamaScript: Script = preload("res://addons/com.heroiclabs.nakama/Nakama.gd")
const NakamaClientScript: Script = preload("res://addons/com.heroiclabs.nakama/client/NakamaClient.gd")
const NetworkConfigScript: Script = preload("res://shared/network_config.gd")
const ProtocolScript: Script = preload("res://shared/nakama_gameplay_bridge_protocol.gd")
const BridgeScript: Script = preload("res://server/nakama_gameplay_bridge.gd")

const ENV_RELAY_TOKEN: String = "PROJECT0_NAKAMA_RELAY_TOKEN"
const ENV_MATCH_ID: String = "PROJECT0_NAKAMA_MATCH_ID"
const MATCH_NAME: String = "project0-shared-world"

var _bridge: Object
var _socket: Object = null
var _match_id: String = ""
var _nakama: Object = null
var _presences: Dictionary = {}


func _init(bridge: Object, socket: Object = null) -> void:
	_bridge = bridge
	_socket = socket


func set_bridge(bridge: Object) -> void:
	_bridge = bridge


func match_id() -> String:
	return _match_id


func available() -> bool:
	return _socket != null and not _match_id.is_empty()


func can_accept_bridge_message(_connection_id: String, _op_code: int) -> bool:
	return available()


func send_bridge_message(_connection_id: String, op_code: int, message: Dictionary) -> bool:
	if not available():
		return false
	var target_presence: Variant = _presences.get(_connection_id, null)
	var targets: Array = [] if target_presence == null else [target_presence]
	_socket.send_match_state_async(_match_id, op_code, JSON.stringify(message), targets)
	return true


func start_from_environment() -> Dictionary:
	var token: String = OS.get_environment(ENV_RELAY_TOKEN).strip_edges()
	if token.is_empty():
		return {"outcome": "not_configured"}
	var base_url: String = NetworkConfigScript.resolve_nakama_base_url()
	var parsed: Dictionary = _parse_base_url(base_url)
	if parsed.is_empty():
		return {"outcome": "invalid_config"}
	if _socket == null:
		_nakama = NakamaScript.new()
		add_child(_nakama)
		_socket = _nakama.create_socket(parsed["host"], parsed["port"], parsed["scheme"])
	var session: Object = NakamaClientScript.restore_session(token)
	if session == null or session.expired:
		return {"outcome": "invalid_relay_session"}
	var connected: Object = await _socket.connect_async(session)
	if connected.is_exception():
		return {"outcome": "connect_failed"}
	_socket.received_match_state.connect(_on_match_state)
	var configured_match: String = OS.get_environment(ENV_MATCH_ID).strip_edges()
	var joined: Object
	if configured_match.is_empty():
		joined = await _socket.create_match_async(MATCH_NAME)
	else:
		joined = await _socket.join_match_async(configured_match)
	if joined.is_exception():
		return {"outcome": "match_join_failed"}
	_match_id = String(joined.match_id)
	return {"outcome": ProtocolScript.OUTCOME_OK, "match_id": _match_id}


func bind_world_entry(peer_id: int, nakama_user_id: String, character_id: String, ticket: String, player_state: Object) -> Dictionary:
	if not available():
		return {"outcome": "unavailable"}
	return _bridge.bind_world_entry(nakama_user_id, peer_id, nakama_user_id, character_id, ticket, player_state)


func unbind_world_entry(nakama_user_id: String) -> void:
	_presences.erase(nakama_user_id)
	if _bridge != null:
		_bridge.unbind(nakama_user_id)


func _on_match_state(data: Object) -> void:
	if data == null or int(data.op_code) != BridgeScript.OP_INPUT:
		return
	var connection_id: String = String(data.presence.user_id) if data.presence != null else ""
	if connection_id.is_empty():
		return
	_presences[connection_id] = data.presence
	_bridge.receive_match_state(connection_id, data.data, Engine.get_physics_frames())


static func _parse_base_url(base_url: String) -> Dictionary:
	var scheme: String = "wss" if base_url.begins_with("https://") else "ws"
	var host_port: String = base_url.trim_prefix("https://").trim_prefix("http://").trim_prefix("wss://").trim_prefix("ws://")
	var slash: int = host_port.find("/")
	if slash >= 0:
		host_port = host_port.left(slash)
	var host: String = host_port
	var port: int = 443 if scheme == "wss" else 80
	var colon: int = host_port.rfind(":")
	if colon > 0 and host_port.substr(colon + 1).is_valid_int():
		host = host_port.left(colon)
		port = host_port.substr(colon + 1).to_int()
	if host.is_empty() or port < 1 or port > 65535:
		return {}
	return {"scheme": scheme, "host": host, "port": port}