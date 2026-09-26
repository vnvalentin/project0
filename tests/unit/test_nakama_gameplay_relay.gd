extends GutTest

const RelayScript: Script = preload("res://server/nakama_gameplay_relay.gd")
const ProtocolScript: Script = preload("res://shared/nakama_gameplay_bridge_protocol.gd")

class FakeSocket extends RefCounted:
	var sends: Array = []

	func send_match_state_async(match_id: String, op_code: int, data: String, presences: Array = []) -> void:
		sends.append({"match_id": match_id, "op_code": op_code, "data": data, "presences": presences})

class FakeBridge extends RefCounted:
	var received: Array = []
	var unbound_connection_ids: Array[String] = []

	func unbind(connection_id: String) -> void:
		unbound_connection_ids.append(connection_id)

	func receive_match_state(connection_id: String, data: String, tick: int) -> Dictionary:
		received.append({"connection_id": connection_id, "data": data, "tick": tick})
		return {"outcome": ProtocolScript.OUTCOME_OK}

class FakePresence extends RefCounted:
	var user_id: String = "nakama-user"

class FakeMatchData extends RefCounted:
	var op_code: int = 1701
	var presence: FakePresence = FakePresence.new()
	var data: String = "{}"

func test_relay_forwards_socket_data_to_bridge_and_writes_back_to_match() -> void:
	var socket: FakeSocket = FakeSocket.new()
	var bridge: FakeBridge = FakeBridge.new()
	var relay: Node = autofree(RelayScript.new(bridge, socket))
	relay._match_id = "shared-match"
	relay._on_match_state(FakeMatchData.new())
	assert_eq(bridge.received.size(), 1)
	assert_eq(bridge.received[0]["connection_id"], "nakama-user")
	assert_true(relay.send_bridge_message("nakama-user", 1703, {"kind": "error"}))
	assert_eq(socket.sends[0]["match_id"], "shared-match")

func test_relay_url_parser_rejects_invalid_port_without_exposing_secrets() -> void:
	assert_eq(RelayScript._parse_base_url("http://127.0.0.1:7350")["port"], 7350)
	assert_true(RelayScript._parse_base_url("http://127.0.0.1:0").is_empty())

func test_relay_unbind_allows_reconnect_for_same_identity() -> void:
	var bridge: FakeBridge = FakeBridge.new()
	var relay: Node = autofree(RelayScript.new(bridge, FakeSocket.new()))
	relay._match_id = "shared-match"
	relay._presences["nakama-user"] = FakePresence.new()
	relay.unbind_world_entry("nakama-user")
	assert_false(relay._presences.has("nakama-user"))
	assert_eq(bridge.unbound_connection_ids, ["nakama-user"])
