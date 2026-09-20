extends RefCounted
class_name NakamaGameplayBridge
## Slice 180: transport adapter only. Project0 owns identity, simulation, and
## authoritative state; the injected socket is the only output boundary.

const ProtocolScript: Script = preload("res://shared/nakama_gameplay_bridge_protocol.gd")
const CombatContractsScript: Script = preload("res://shared/combat_contracts.gd")

const OP_INPUT: int = 1701
const OP_STATE: int = 1702
const OP_ERROR: int = 1703
const MAX_PENDING: int = 32

const REASON_UNBOUND: String = "unbound"
const REASON_TICKET: String = "invalid_ticket"
const REASON_DUPLICATE: String = "duplicate"
const REASON_BACKPRESSURE: String = "backpressure"
const REASON_DISPATCH: String = "dispatch_rejected"

var _socket: Object
var _bindings: Dictionary = {}
var _consumed_tickets: Dictionary = {}
var _pending: int = 0


func _init(socket: Object = null) -> void:
	_socket = socket


func bind_world_entry(connection_id: String, peer_id: int, nakama_user_id: String, character_id: String, world_entry_ticket: String, player_state: Object) -> Dictionary:
	if connection_id.strip_edges().is_empty() or peer_id < 1 or nakama_user_id.strip_edges().is_empty() or character_id.strip_edges().is_empty() or world_entry_ticket.strip_edges().is_empty() or player_state == null:
		return {"outcome": REASON_UNBOUND}
	if _consumed_tickets.has(world_entry_ticket):
		return {"outcome": REASON_TICKET}
	_consumed_tickets[world_entry_ticket] = true
	_bindings[connection_id] = {
		"peer_id": peer_id,
		"nakama_user_id": nakama_user_id,
		"character_id": character_id,
		"world_entry_ticket": world_entry_ticket,
		"player_state": player_state,
		"last_sequence": 0,
	}
	return {"outcome": ProtocolScript.OUTCOME_OK}


func unbind(connection_id: String) -> void:
	_bindings.erase(connection_id)


func receive_match_state(connection_id: String, raw_data: Variant, server_tick: int) -> Dictionary:
	if not _bindings.has(connection_id):
		return _reject(connection_id, REASON_UNBOUND)
	if _pending >= MAX_PENDING:
		return _reject(connection_id, REASON_BACKPRESSURE)
	if _socket == null or (_socket.has_method("can_accept_bridge_message") and not _socket.can_accept_bridge_message(connection_id, OP_STATE)):
		return _reject(connection_id, REASON_BACKPRESSURE)
	var message: Variant = raw_data
	if raw_data is String:
		message = JSON.parse_string(raw_data)
	var validation: Dictionary = ProtocolScript.validate(message, ProtocolScript.KIND_INPUT)
	if validation["outcome"] != ProtocolScript.OUTCOME_OK:
		return _reject(connection_id, String(validation["outcome"]))
	var binding: Dictionary = _bindings[connection_id]
	var envelope: Dictionary = validation["message"]
	if String(envelope["nakama_user_id"]) != binding["nakama_user_id"] or String(envelope["character_id"]) != binding["character_id"]:
		return _reject(connection_id, ProtocolScript.REASON_INVALID_IDENTITY)
	var sequence: int = int(envelope["sequence"])
	if sequence <= int(binding["last_sequence"]):
		return _reject(connection_id, REASON_DUPLICATE)
	var payload: Dictionary = envelope["payload"]
	var state: Object = binding["player_state"]
	var dispatch_result: Dictionary = _dispatch(state, int(binding["peer_id"]), sequence, payload)
	if dispatch_result["outcome"] != ProtocolScript.OUTCOME_OK:
		return _reject(connection_id, String(dispatch_result["outcome"]))
	binding["last_sequence"] = sequence
	var state_message: Dictionary = ProtocolScript.build_state(
		binding["nakama_user_id"], binding["character_id"], server_tick, state.position, dispatch_result.get("payload", {})
	)
	if not _send(connection_id, OP_STATE, state_message):
		return _reject(connection_id, REASON_BACKPRESSURE)
	return {"outcome": ProtocolScript.OUTCOME_OK, "message": state_message}


func _dispatch(state: Object, peer_id: int, sequence: int, payload: Dictionary) -> Dictionary:
	if payload.has("move_x") or payload.has("move_z"):
		if not payload.get("move_x", 0.0) is float and not payload.get("move_x", 0.0) is int:
			return {"outcome": ProtocolScript.REASON_INVALID_PAYLOAD}
		if not payload.get("move_z", 0.0) is float and not payload.get("move_z", 0.0) is int:
			return {"outcome": ProtocolScript.REASON_INVALID_PAYLOAD}
		var intent: Dictionary = {
			"direction": Vector2(float(payload.get("move_x", 0.0)), float(payload.get("move_z", 0.0))),
			"mode": String(payload.get("mode", "NONE")),
		}
		state.apply_input_intent(peer_id, intent, sequence)
		return {"outcome": ProtocolScript.OUTCOME_OK}
	if payload.has("action_kind"):
		var aim: Vector3 = Vector3(float(payload.get("aim_x", 0.0)), float(payload.get("aim_y", 0.0)), float(payload.get("aim_z", 0.0)))
		var intent: Object = CombatContractsScript.ActionIntent.new(peer_id, sequence, 0, String(payload["action_kind"]), aim)
		var resolution: Object = state.apply_action_intent(peer_id, intent)
		if resolution == null:
			return {"outcome": REASON_DISPATCH}
		return {"outcome": ProtocolScript.OUTCOME_OK, "payload": {"action_result": resolution.result, "action_rejection_reason": resolution.rejection_reason}}
	return {"outcome": ProtocolScript.REASON_INVALID_PAYLOAD}


func _reject(connection_id: String, reason: String) -> Dictionary:
	var message: Dictionary = ProtocolScript.build_error(reason, "gameplay input rejected")
	_send(connection_id, OP_ERROR, message)
	return {"outcome": reason, "message": message}


func _send(connection_id: String, op_code: int, message: Dictionary) -> bool:
	if _socket == null:
		return false
	_pending += 1
	var accepted: bool = true
	if _socket.has_method("send_bridge_message"):
		accepted = bool(_socket.send_bridge_message(connection_id, op_code, message))
	elif _socket.has_method("send_match_state_async"):
		_socket.send_match_state_async(connection_id, op_code, JSON.stringify(message))
	else:
		accepted = false
	_pending -= 1
	if accepted:
		_pending -= 1
	return accepted