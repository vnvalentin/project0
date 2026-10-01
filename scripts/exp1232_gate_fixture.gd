extends "res://scripts/exp1231_gate_fixture.gd"
## Experiment #1232 server fixture. Records the server receive sequence at the
## RPC boundary. Concurrent cases hold both intents until both are received, so
## neither is evaluated before the other arrived; they are then resolved in
## receive order. The retry case withholds the first confirmation after COMMIT.

const EXP1232_SECOND_ACTOR: Vector3 = Vector3(0.6, 1.0, -3.4)
const EXP1232_CONCURRENT_CASES: PackedStringArray = ["order_a_first", "order_b_first"]

var _exp1232_pending: Array[Dictionary] = []


func _exp_occluder_position() -> Vector3:
	return EXP1232_SECOND_ACTOR


func _on_environmental_interaction_intent(sender_peer_id: int, intent: Dictionary) -> void:
	var received: Array = _exp_observation.get("received", [])
	received.append({
		"receive_seq": received.size() + 1,
		"sender_peer_id": sender_peer_id,
		"role": _exp1232_role(sender_peer_id),
		"client_seq": intent.get("client_seq"),
		"server_tick": _current_server_tick(),
		"received_usec": Time.get_ticks_usec(),
	})
	_exp_observation["received"] = received
	_exp1232_pending.append({"receive_seq": received.size(), "sender_peer_id": sender_peer_id, "intent": intent})
	_exp_write()
	if EXP1232_CONCURRENT_CASES.has(_exp_case) and _exp1232_pending.size() < 2:
		return
	var batch: Array[Dictionary] = _exp1232_pending.duplicate()
	_exp1232_pending.clear()
	for item: Dictionary in batch:
		_exp1232_process(item, batch.size())


func _exp1232_process(item: Dictionary, pending_count: int) -> void:
	var sender_peer_id: int = item["sender_peer_id"]
	var resolution: Dictionary = _resolve_environmental_interaction(sender_peer_id, item["intent"])
	var record: Dictionary = _exp_observation["resolutions"].back()
	record["processing_seq"] = _exp_observation["resolutions"].size()
	record["receive_seq"] = item["receive_seq"]
	record["role"] = _exp1232_role(sender_peer_id)
	record["pending_at_processing"] = pending_count
	var withheld: bool = _exp_case == "retry_after_withheld_confirmation" and item["receive_seq"] == 1
	record["confirmation_withheld"] = withheld
	_exp_write()
	if withheld or resolution.is_empty():
		return
	var network_client: Node = root.get_node_or_null("NetworkClient")
	if network_client != null:
		network_client.rpc_id(sender_peer_id, "receive_environmental_interaction_resolution", resolution)


func _exp1232_role(peer_id: int) -> String:
	for role: String in _exp_observation["bound"]:
		if int(_exp_observation["bound"][role]["peer_id"]) == peer_id:
			return role
	return ""
