extends GutTest

const BridgeScript: Script = preload("res://server/nakama_gameplay_bridge.gd")
const ProtocolScript: Script = preload("res://shared/nakama_gameplay_bridge_protocol.gd")
const FakesScript: Script = preload("res://tests/unit/nakama_gameplay_bridge_fakes.gd")

func _bridge() -> Array:
	var socket: Object = FakesScript.FakeSocket.new()
	var state: Object = FakesScript.FakeState.new()
	var bridge: NakamaGameplayBridge = BridgeScript.new(socket)
	assert_eq(bridge.bind_world_entry("connection", 7, "nakama-user", "character", "ticket", state)["outcome"], ProtocolScript.OUTCOME_OK)
	return [bridge, socket, state]

func test_accepts_bound_movement_and_emits_authoritative_state() -> void:
	var parts: Array = _bridge()
	var result: Dictionary = parts[0].receive_match_state("connection", ProtocolScript.build_input("nakama-user", "character", 1, {"move_x": 1.0, "move_z": -1.0}), 42)
	assert_eq(result["outcome"], ProtocolScript.OUTCOME_OK)
	assert_eq(parts[2].input_calls.size(), 1)
	assert_eq(parts[1].messages[0]["message"]["kind"], ProtocolScript.KIND_STATE)
	assert_eq(parts[1].messages[0]["message"]["payload"]["server_tick"], 42)

func test_rejects_wrong_identity_and_duplicate_without_dispatch() -> void:
	var parts: Array = _bridge()
	var wrong: Dictionary = ProtocolScript.build_input("other-user", "character", 1, {"move_x": 1.0})
	assert_eq(parts[0].receive_match_state("connection", wrong, 1)["outcome"], ProtocolScript.REASON_INVALID_IDENTITY)
	var valid: Dictionary = ProtocolScript.build_input("nakama-user", "character", 2, {"move_x": 1.0})
	assert_eq(parts[0].receive_match_state("connection", valid, 1)["outcome"], ProtocolScript.OUTCOME_OK)
	assert_eq(parts[0].receive_match_state("connection", valid, 2)["outcome"], BridgeScript.REASON_DUPLICATE)
	assert_eq(parts[2].input_calls.size(), 1)

func test_rejects_ticket_reuse_and_socket_backpressure() -> void:
	var socket: Object = FakesScript.FakeSocket.new()
	var bridge: NakamaGameplayBridge = BridgeScript.new(socket)
	var state: Object = FakesScript.FakeState.new()
	assert_eq(bridge.bind_world_entry("a", 1, "user", "character", "ticket", state)["outcome"], ProtocolScript.OUTCOME_OK)
	assert_eq(bridge.bind_world_entry("b", 2, "user2", "character2", "ticket", state)["outcome"], BridgeScript.REASON_TICKET)
	socket.accepting = false
	var result: Dictionary = bridge.receive_match_state("a", ProtocolScript.build_input("user", "character", 1, {"move_x": 1.0}), 1)
	assert_eq(result["outcome"], BridgeScript.REASON_BACKPRESSURE)
	assert_eq(state.input_calls.size(), 0)