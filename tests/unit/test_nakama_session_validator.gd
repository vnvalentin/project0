extends GutTest

const ValidatorScript: Script = preload("res://server/nakama_session_validator.gd")


func test_parse_response_extracts_server_validated_user() -> void:
	var body: PackedByteArray = JSON.stringify({"user": {"id": "nakama-user-1", "username": "hero"}}).to_utf8_buffer()
	var result: Dictionary = ValidatorScript.parse_response([HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), body])
	assert_eq(result["outcome"], ValidatorScript.OUTCOME_OK)
	assert_eq(result["nakama_user_id"], "nakama-user-1")
	assert_eq(result["username"], "hero")


func test_parse_response_rejects_missing_user_and_non_success() -> void:
	var missing: PackedByteArray = JSON.stringify({"user": {"username": "hero"}}).to_utf8_buffer()
	assert_eq(ValidatorScript.parse_response([HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), missing])["outcome"], ValidatorScript.OUTCOME_MALFORMED)
	var unauthorized: PackedByteArray = "{\"error\":\"unauthorized\"}".to_utf8_buffer()
	assert_eq(ValidatorScript.parse_response([HTTPRequest.RESULT_SUCCESS, 401, PackedStringArray(), unauthorized])["outcome"], ValidatorScript.OUTCOME_HTTP_ERROR)


func test_parse_response_bounds_timeout_and_transport() -> void:
	var empty: PackedByteArray = PackedByteArray()
	assert_eq(ValidatorScript.parse_response([HTTPRequest.RESULT_TIMEOUT, 0, PackedStringArray(), empty])["outcome"], ValidatorScript.OUTCOME_TIMEOUT)
	assert_eq(ValidatorScript.parse_response([HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), empty])["outcome"], ValidatorScript.OUTCOME_TRANSPORT_ERROR)