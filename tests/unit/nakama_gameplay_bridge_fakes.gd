extends RefCounted

class FakeSocket extends RefCounted:
	var messages: Array[Dictionary] = []
	var accepting: bool = true

	func can_accept_bridge_message(_connection_id: String, _op_code: int) -> bool:
		return accepting

	func send_bridge_message(connection_id: String, op_code: int, message: Dictionary) -> bool:
		if not accepting:
			return false
		messages.append({"connection_id": connection_id, "op_code": op_code, "message": message})
		return true

class FakeState extends RefCounted:
	var position: Vector3 = Vector3(2, 0, 3)
	var input_calls: Array = []
	var action_calls: Array = []

	func apply_input_intent(peer_id: int, intent: Dictionary, sequence: int) -> void:
		input_calls.append({"peer_id": peer_id, "intent": intent, "sequence": sequence})

	func apply_action_intent(peer_id: int, intent: Object) -> Object:
		action_calls.append({"peer_id": peer_id, "intent": intent})
		return Resolution.new("ACCEPTED", "")

class Resolution extends RefCounted:
	var result: String
	var rejection_reason: String

	func _init(p_result: String, p_reason: String) -> void:
		result = p_result
		rejection_reason = p_reason