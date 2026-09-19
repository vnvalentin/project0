extends GutTest

const ProtocolScript: Script = preload("res://shared/nakama_gameplay_bridge_protocol.gd")


func test_input_round_trip_preserves_identity_sequence_and_payload() -> void:
	var message: Dictionary = ProtocolScript.build_input("nakama-user-1", "character-1", 7, {"move_x": 1.0, "move_z": -1.0})
	var result: Dictionary = ProtocolScript.validate(message, ProtocolScript.KIND_INPUT)
	assert_eq(result["outcome"], ProtocolScript.OUTCOME_OK)
	assert_eq(result["message"]["nakama_user_id"], "nakama-user-1")
	assert_eq(result["message"]["character_id"], "character-1")
	assert_eq(result["message"]["sequence"], 7)
	assert_eq(result["message"]["payload"]["move_x"], 1.0)


func test_input_rejects_authoritative_fields_and_invalid_sequence() -> void:
	var forged: Dictionary = ProtocolScript.build_input("user", "character", 1, {"position": {"x": 10}})
	assert_eq(ProtocolScript.validate(forged)["outcome"], ProtocolScript.REASON_AUTHORITY_FIELD)
	var invalid_sequence: Dictionary = ProtocolScript.build_input("user", "character", 0, {"move_x": 1})
	assert_eq(ProtocolScript.validate(invalid_sequence)["outcome"], ProtocolScript.REASON_INVALID_SEQUENCE)


func test_state_contains_server_authoritative_position_and_tick() -> void:
	var message: Dictionary = ProtocolScript.build_state("user", "character", 42, Vector3(1, 2, 3))
	var result: Dictionary = ProtocolScript.validate(message, ProtocolScript.KIND_STATE)
	assert_eq(result["outcome"], ProtocolScript.OUTCOME_OK)
	assert_eq(result["message"]["payload"]["server_tick"], 42)
	assert_eq(result["message"]["payload"]["position"]["z"], 3.0)


func test_validation_rejects_invalid_identity_version_kind_and_oversized_payload() -> void:
	assert_eq(ProtocolScript.validate(ProtocolScript.build_input("", "character", 1, {}))["outcome"], ProtocolScript.REASON_INVALID_IDENTITY)
	var wrong_version: Dictionary = ProtocolScript.build_input("user", "character", 1, {})
	wrong_version["version"] = 99
	assert_eq(ProtocolScript.validate(wrong_version)["outcome"], ProtocolScript.REASON_UNSUPPORTED_VERSION)
	var wrong_kind: Dictionary = ProtocolScript.build_input("user", "character", 1, {})
	wrong_kind["kind"] = "unknown"
	assert_eq(ProtocolScript.validate(wrong_kind)["outcome"], ProtocolScript.REASON_UNSUPPORTED_KIND)
	var oversized: Dictionary = ProtocolScript.build_input("user", "character", 1, {"data": "x".repeat(ProtocolScript.MAX_PAYLOAD_JSON_LENGTH)})
	assert_eq(ProtocolScript.validate(oversized)["outcome"], ProtocolScript.REASON_INVALID_PAYLOAD)


func test_presence_and_error_are_bounded_envelopes() -> void:
	assert_eq(ProtocolScript.validate(ProtocolScript.build_presence("user", "character", "online"))["outcome"], ProtocolScript.OUTCOME_OK)
	var error_result: Dictionary = ProtocolScript.validate(ProtocolScript.build_error("bridge_unavailable", "retry"), ProtocolScript.KIND_ERROR)
	assert_eq(error_result["outcome"], ProtocolScript.OUTCOME_OK)