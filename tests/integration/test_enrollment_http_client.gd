extends GutTest
## Slice 091: public-seam tests for client/enrollment_http_client.gd. Drives the
## real HTTPRequest transport against the existing fake HTTP server fixture
## (scripts/fake_ollama_http_server.gd), which answers one scripted response per
## connection — enough for the single-call-per-test coverage of each method's
## bounded success/failure mapping. The real enrollment routes are covered
## Python-side (test_app_characters.py) and Godot-side end-to-end by the
## loopback GUT suite.

const FakeServerScript: Script = preload("res://scripts/fake_ollama_http_server.gd")
const EnrollmentHttpClientScript: Script = preload("res://client/enrollment_http_client.gd")

var _server: Node = null
var _client: Node = null
var _base_url: String = ""


func before_each() -> void:
	_server = FakeServerScript.new()
	add_child_autofree(_server)
	var port: int = _server.start()
	assert_ne(port, -1, "the fake HTTP server binds an ephemeral loopback port")
	_base_url = "http://127.0.0.1:%d" % port

	_client = EnrollmentHttpClientScript.new()
	_client.request_timeout_sec = 2.0
	add_child_autofree(_client)


func after_each() -> void:
	_server.stop()


func test_login_returns_account_assertion() -> void:
	_server.next_response_status = 200
	_server.next_response_body = JSON.stringify({"assertion": "acct-token"})

	var result: Dictionary = await _client.login(_base_url, "alice", "pw123456")

	assert_eq(result["outcome"], "ok", "a 2xx login is ok")
	assert_eq(String(result.get("assertion", "")), "acct-token", "the account assertion is returned")


func test_login_non_2xx_is_http_error() -> void:
	_server.next_response_status = 401
	_server.next_response_body = JSON.stringify({"detail": "bad_credentials"})

	var result: Dictionary = await _client.login(_base_url, "alice", "wrong")

	assert_eq(result["outcome"], "http_error", "a 401 login maps to http_error")
	assert_eq(int(result.get("status", 0)), 401, "the status is carried")


func test_list_characters_returns_array() -> void:
	_server.next_response_body = JSON.stringify({"characters": [{"character_id": "c1"}, {"character_id": "c2"}]})

	var result: Dictionary = await _client.list_characters(_base_url, "tok")

	assert_eq(result["outcome"], "ok", "list is ok")
	assert_eq((result["characters"] as Array).size(), 2, "both characters are returned")


func test_create_character_returns_character() -> void:
	_server.next_response_body = JSON.stringify({"character": {"character_id": "c9", "display_name": "Hero"}})

	var result: Dictionary = await _client.create_character(_base_url, "tok", "Hero", {})

	assert_eq(result["outcome"], "ok", "create is ok")
	assert_eq(String((result["character"] as Dictionary).get("character_id", "")), "c9", "the created character is returned")


func test_select_character_returns_character_assertion() -> void:
	_server.next_response_body = JSON.stringify({"assertion": "character-token"})

	var result: Dictionary = await _client.select_character(_base_url, "tok", "c1")

	assert_eq(result["outcome"], "ok", "select is ok")
	assert_eq(String(result.get("assertion", "")), "character-token", "the character assertion is returned")


func test_delete_character_ok() -> void:
	_server.next_response_body = JSON.stringify({"outcome": "ok"})

	var result: Dictionary = await _client.delete_character(_base_url, "tok", "c1")

	assert_eq(result["outcome"], "ok", "delete is ok")


func test_malformed_response_body_is_rejected() -> void:
	_server.next_response_body = "this is not json"

	var result: Dictionary = await _client.login(_base_url, "alice", "pw123456")

	assert_eq(result["outcome"], "malformed", "a non-JSON body is rejected fail-closed")


func test_unreachable_server_is_transport_error() -> void:
	# Port 1 has no listener; the request fails to connect.
	var result: Dictionary = await _client.login("http://127.0.0.1:1", "alice", "pw123456")

	assert_eq(result["outcome"], "transport_error", "an unreachable server maps to transport_error")


func test_resolve_base_url_reads_env_and_trims_slash() -> void:
	var saved: String = OS.get_environment(EnrollmentHttpClientScript.ENV_BASE_URL)
	OS.set_environment(EnrollmentHttpClientScript.ENV_BASE_URL, "https://enroll.example.test/")
	assert_eq(EnrollmentHttpClientScript.resolve_base_url(), "https://enroll.example.test", "trailing slash is trimmed")
	OS.set_environment(EnrollmentHttpClientScript.ENV_BASE_URL, "")
	assert_eq(EnrollmentHttpClientScript.resolve_base_url(), EnrollmentHttpClientScript.DEFAULT_BASE_URL, "unset falls back to the default")
	OS.set_environment(EnrollmentHttpClientScript.ENV_BASE_URL, saved)
