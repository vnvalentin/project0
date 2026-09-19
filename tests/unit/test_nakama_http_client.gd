extends GutTest

const NakamaHttpClientScript: Script = preload("res://client/nakama_http_client.gd")
const NetworkConfigScript: Script = preload("res://shared/network_config.gd")

var _saved_enabled: String = ""
var _saved_url: String = ""
var _saved_key: String = ""


func before_each() -> void:
	_saved_enabled = OS.get_environment(NetworkConfigScript.CLIENT_NAKAMA_LOGIN_ENV_VAR)
	_saved_url = OS.get_environment(NetworkConfigScript.NAKAMA_URL_ENV_VAR)
	_saved_key = OS.get_environment(NetworkConfigScript.NAKAMA_SERVER_KEY_ENV_VAR)


func after_each() -> void:
	OS.set_environment(NetworkConfigScript.CLIENT_NAKAMA_LOGIN_ENV_VAR, _saved_enabled)
	OS.set_environment(NetworkConfigScript.NAKAMA_URL_ENV_VAR, _saved_url)
	OS.set_environment(NetworkConfigScript.NAKAMA_SERVER_KEY_ENV_VAR, _saved_key)


func test_nakama_login_flag_defaults_off() -> void:
	OS.set_environment(NetworkConfigScript.CLIENT_NAKAMA_LOGIN_ENV_VAR, "")
	assert_false(NetworkConfigScript.client_nakama_login_enabled())
	OS.set_environment(NetworkConfigScript.CLIENT_NAKAMA_LOGIN_ENV_VAR, "1")
	assert_true(NetworkConfigScript.client_nakama_login_enabled())


func test_nakama_config_trims_url_and_reads_server_key() -> void:
	OS.set_environment(NetworkConfigScript.NAKAMA_URL_ENV_VAR, "https://example.test:7350///")
	OS.set_environment(NetworkConfigScript.NAKAMA_SERVER_KEY_ENV_VAR, "  client-key  ")
	assert_eq(NetworkConfigScript.resolve_nakama_base_url(), "https://example.test:7350")
	assert_eq(NetworkConfigScript.resolve_nakama_server_key(), "client-key")


func test_parse_auth_result_extracts_user_id_from_jwt() -> void:
	var token: String = _jwt({"uid": "nakama-user-1", "usn": "hero@example.test"})
	var result: Dictionary = NakamaHttpClientScript.parse_auth_result({
		"outcome": NakamaHttpClientScript.OUTCOME_OK,
		"status": 200,
		"data": {"token": token, "refresh_token": "refresh-1"},
	}, "fallback@example.test")
	assert_eq(result["outcome"], NakamaHttpClientScript.OUTCOME_OK)
	assert_eq(result["user_id"], "nakama-user-1")
	assert_eq(result["username"], "hero@example.test")
	assert_eq(result["auth_token"], token)
	assert_eq(result["refresh_token"], "refresh-1")


func test_parse_auth_result_rejects_missing_token_fields() -> void:
	var result: Dictionary = NakamaHttpClientScript.parse_auth_result({
		"outcome": NakamaHttpClientScript.OUTCOME_OK,
		"status": 200,
		"data": {"token": "not-a-jwt"},
	}, "fallback@example.test")
	assert_eq(result["outcome"], NakamaHttpClientScript.OUTCOME_MALFORMED)


func test_parse_http_response_bounds_non_2xx() -> void:
	var body: PackedByteArray = JSON.stringify({"message": "unauthorized"}).to_utf8_buffer()
	var result: Dictionary = NakamaHttpClientScript.parse_http_response([HTTPRequest.RESULT_SUCCESS, 401, PackedStringArray(), body])
	assert_eq(result["outcome"], NakamaHttpClientScript.OUTCOME_HTTP_ERROR)
	assert_eq(result["status"], 401)


func test_basic_auth_uses_server_key_as_username() -> void:
	assert_eq(NakamaHttpClientScript.basic_auth_value("key-1"), Marshalls.utf8_to_base64("key-1:"))


func test_player_identity_clear_session_clears_nakama_tokens() -> void:
	PlayerIdentity.nakama_user_id = "nakama-user-1"
	PlayerIdentity.nakama_auth_token = "auth-token"
	PlayerIdentity.nakama_refresh_token = "refresh-token"
	PlayerIdentity.clear_session()
	assert_eq(PlayerIdentity.nakama_user_id, "")
	assert_eq(PlayerIdentity.nakama_auth_token, "")
	assert_eq(PlayerIdentity.nakama_refresh_token, "")


func _jwt(payload: Dictionary) -> String:
	var header: String = _base64_url(JSON.stringify({"alg": "HS256", "typ": "JWT"}))
	var body: String = _base64_url(JSON.stringify(payload))
	return "%s.%s.signature" % [header, body]


func _base64_url(value: String) -> String:
	return Marshalls.utf8_to_base64(value).replace("+", "-").replace("/", "_").replace("=", "")