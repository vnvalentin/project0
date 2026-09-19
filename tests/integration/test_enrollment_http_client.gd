extends GutTest
## Slice 091: pure tests for client/enrollment_http_client.gd's bounded
## outcome mapping. Feeds synthetic HTTPRequest-`request_completed` arrays to
## `_parse` and synthetic result dicts to the field extractors — no real socket,
## so the coverage is deterministic and cannot race the HTTPRequest/Node
## lifecycle. The real end-to-end HTTP path is covered by the enrollment route
## tests (infra/enrollment/tests/test_app_characters.py) and the loopback GUT
## suite (test_login_loopback_http_endpoint.gd).

const EnrollmentHttpClientScript: Script = preload("res://client/enrollment_http_client.gd")

var _client: Object = null


func before_each() -> void:
	# new() without adding to the tree: _ready never runs, so no HTTPRequest node
	# is created — these tests exercise only pure parse/extraction methods.
	_client = EnrollmentHttpClientScript.new()


func after_each() -> void:
	_client.free()


func _response(result_code: int, status: int, body: String) -> Array:
	return [result_code, status, PackedStringArray(), body.to_utf8_buffer()]


func test_parse_2xx_json_object_is_ok() -> void:
	var result: Dictionary = _client._parse(_response(HTTPRequest.RESULT_SUCCESS, 200, JSON.stringify({"a": 1})))
	assert_eq(result["outcome"], "ok", "a 2xx JSON object is ok")
	assert_eq(int((result["data"] as Dictionary).get("a", 0)), 1, "the parsed body is returned")


func test_parse_non_2xx_is_http_error_and_keeps_body() -> void:
	var result: Dictionary = _client._parse(_response(HTTPRequest.RESULT_SUCCESS, 401, JSON.stringify({"detail": "bad_credentials"})))
	assert_eq(result["outcome"], "http_error", "a non-2xx maps to http_error")
	assert_eq(int(result["status"]), 401, "the status is carried")
	assert_eq(String((result["data"] as Dictionary).get("detail", "")), "bad_credentials", "the error body is carried")


func test_parse_timeout() -> void:
	var result: Dictionary = _client._parse(_response(HTTPRequest.RESULT_TIMEOUT, 0, ""))
	assert_eq(result["outcome"], "timeout", "a timeout result maps to timeout")


func test_parse_connection_failure_is_transport_error() -> void:
	var result: Dictionary = _client._parse(_response(HTTPRequest.RESULT_CANT_CONNECT, 0, ""))
	assert_eq(result["outcome"], "transport_error", "a non-success non-timeout result maps to transport_error")


func test_parse_non_json_body_is_malformed() -> void:
	var result: Dictionary = _client._parse(_response(HTTPRequest.RESULT_SUCCESS, 200, "this is not json"))
	assert_eq(result["outcome"], "malformed", "a non-JSON 2xx body is rejected fail-closed")


func test_require_string_field_ok_wrong_type_and_passthrough() -> void:
	var ok: Dictionary = _client._require_string_field({"outcome": "ok", "status": 200, "data": {"assertion": "tok"}}, "assertion")
	assert_eq(ok["outcome"], "ok", "a string field is extracted")
	assert_eq(String(ok["assertion"]), "tok", "the value is returned")

	var wrong: Dictionary = _client._require_string_field({"outcome": "ok", "status": 200, "data": {"assertion": 123}}, "assertion")
	assert_eq(wrong["outcome"], "malformed", "a non-string field is malformed")

	var passthrough: Dictionary = _client._require_string_field({"outcome": "http_error", "status": 401}, "assertion")
	assert_eq(passthrough["outcome"], "http_error", "a non-ok result passes through unchanged")


func test_require_array_field() -> void:
	var ok: Dictionary = _client._require_array_field({"outcome": "ok", "status": 200, "data": {"characters": [1, 2]}}, "characters")
	assert_eq(ok["outcome"], "ok", "an array field is extracted")
	assert_eq((ok["characters"] as Array).size(), 2, "the array is returned")

	var wrong: Dictionary = _client._require_array_field({"outcome": "ok", "status": 200, "data": {"characters": "nope"}}, "characters")
	assert_eq(wrong["outcome"], "malformed", "a non-array field is malformed")


func test_require_dict_field() -> void:
	var ok: Dictionary = _client._require_dict_field({"outcome": "ok", "status": 200, "data": {"character": {"id": "c1"}}}, "character")
	assert_eq(ok["outcome"], "ok", "a dict field is extracted")

	var wrong: Dictionary = _client._require_dict_field({"outcome": "ok", "status": 200, "data": {"character": []}}, "character")
	assert_eq(wrong["outcome"], "malformed", "a non-dict field is malformed")


func test_resolve_base_url_reads_env_trims_slash_and_defaults() -> void:
	var saved: String = OS.get_environment(EnrollmentHttpClientScript.ENV_BASE_URL)
	OS.set_environment(EnrollmentHttpClientScript.ENV_BASE_URL, "https://enroll.example.test/")
	assert_eq(EnrollmentHttpClientScript.resolve_base_url(), "https://enroll.example.test", "a trailing slash is trimmed")
	OS.set_environment(EnrollmentHttpClientScript.ENV_BASE_URL, "")
	assert_eq(EnrollmentHttpClientScript.resolve_base_url(), EnrollmentHttpClientScript.DEFAULT_BASE_URL, "unset falls back to the default")
	OS.set_environment(EnrollmentHttpClientScript.ENV_BASE_URL, "https://enroll.example.test/redeem")
	assert_eq(EnrollmentHttpClientScript.resolve_base_url(), "https://enroll.example.test", "a trailing /redeem suffix is trimmed so /login resolves")
	OS.set_environment(EnrollmentHttpClientScript.ENV_BASE_URL, "https://enroll.example.test/redeem/")
	assert_eq(EnrollmentHttpClientScript.resolve_base_url(), "https://enroll.example.test", "a trailing /redeem/ suffix is trimmed")
	OS.set_environment(EnrollmentHttpClientScript.ENV_BASE_URL, saved)
