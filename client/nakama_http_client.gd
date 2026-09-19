extends Node
class_name NakamaHttpClient
## Slice 167: bounded client-only HTTP seam for Nakama authentication/session
## entry. This is intentionally narrow: Character and world-entry authority stay
## Project0-owned in later slices.

const OUTCOME_OK: String = "ok"
const OUTCOME_CONFIG_ERROR: String = "config_error"
const OUTCOME_TRANSPORT_ERROR: String = "transport_error"
const OUTCOME_TIMEOUT: String = "timeout"
const OUTCOME_HTTP_ERROR: String = "http_error"
const OUTCOME_MALFORMED: String = "malformed"

const DEFAULT_TIMEOUT_SEC: float = 10.0

@export var request_timeout_sec: float = DEFAULT_TIMEOUT_SEC

var _http_request: HTTPRequest = null


func _ready() -> void:
	_http_request = HTTPRequest.new()
	_http_request.timeout = request_timeout_sec
	add_child(_http_request)


func login(base_url: String, server_key: String, email: String, password: String) -> Dictionary:
	return await _authenticate_email(base_url, server_key, email, password, false)


func register(base_url: String, server_key: String, email: String, password: String) -> Dictionary:
	return await _authenticate_email(base_url, server_key, email, password, true)


func refresh_session(base_url: String, server_key: String, refresh_token: String) -> Dictionary:
	if server_key.strip_edges().is_empty() or refresh_token.strip_edges().is_empty():
		return {"outcome": OUTCOME_CONFIG_ERROR, "status": -1}
	var result: Dictionary = await _post_json(base_url, server_key, "/v2/session/refresh", {"token": refresh_token})
	return parse_auth_result(result, "")


func logout(base_url: String, server_key: String, auth_token: String, refresh_token: String) -> Dictionary:
	if server_key.strip_edges().is_empty():
		return {"outcome": OUTCOME_CONFIG_ERROR, "status": -1}
	var result: Dictionary = await _post_json(base_url, server_key, "/v2/session/logout", {"token": auth_token, "refresh_token": refresh_token})
	if result["outcome"] != OUTCOME_OK:
		return {"outcome": result["outcome"], "status": result["status"]}
	return {"outcome": OUTCOME_OK, "status": result["status"]}


func _authenticate_email(base_url: String, server_key: String, email: String, password: String, create: bool) -> Dictionary:
	if server_key.strip_edges().is_empty():
		return {"outcome": OUTCOME_CONFIG_ERROR, "status": -1}
	var create_value: String = "true" if create else "false"
	var path: String = "/v2/account/authenticate/email?create=%s" % create_value
	var result: Dictionary = await _post_json(base_url, server_key, path, {"email": email, "password": password})
	return parse_auth_result(result, email)


func _post_json(base_url: String, server_key: String, path: String, body: Dictionary) -> Dictionary:
	var url: String = "%s%s" % [base_url.rstrip("/"), path]
	var headers: PackedStringArray = [
		"Content-Type: application/json",
		"Authorization: Basic %s" % basic_auth_value(server_key),
	]
	var error: Error = _http_request.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if error != OK:
		return {"outcome": OUTCOME_TRANSPORT_ERROR, "status": -1, "data": null}
	var response: Array = await _http_request.request_completed
	return parse_http_response(response)


static func basic_auth_value(server_key: String) -> String:
	return Marshalls.utf8_to_base64("%s:" % server_key)


static func parse_http_response(response: Array) -> Dictionary:
	var result_code: int = response[0]
	var status: int = response[1]
	var body_text: String = (response[3] as PackedByteArray).get_string_from_utf8()
	if result_code == HTTPRequest.RESULT_TIMEOUT:
		return {"outcome": OUTCOME_TIMEOUT, "status": status, "data": null}
	if result_code != HTTPRequest.RESULT_SUCCESS:
		return {"outcome": OUTCOME_TRANSPORT_ERROR, "status": status, "data": null}
	var parsed: Variant = JSON.parse_string(body_text)
	if not (parsed is Dictionary):
		return {"outcome": OUTCOME_MALFORMED, "status": status, "data": null}
	if status < 200 or status >= 300:
		return {"outcome": OUTCOME_HTTP_ERROR, "status": status, "data": parsed}
	return {"outcome": OUTCOME_OK, "status": status, "data": parsed}


static func parse_auth_result(result: Dictionary, fallback_username: String) -> Dictionary:
	if result["outcome"] != OUTCOME_OK:
		return {"outcome": result["outcome"], "status": result["status"]}
	var data: Dictionary = result["data"]
	if not (data.get("token") is String) or not (data.get("refresh_token") is String):
		return {"outcome": OUTCOME_MALFORMED, "status": result["status"]}
	var token: String = data["token"]
	var claims: Dictionary = parse_jwt_payload(token)
	if not (claims.get("uid") is String):
		return {"outcome": OUTCOME_MALFORMED, "status": result["status"]}
	var username: String = fallback_username
	if claims.get("usn") is String:
		username = claims["usn"]
	return {
		"outcome": OUTCOME_OK,
		"status": result["status"],
		"user_id": claims["uid"],
		"username": username,
		"auth_token": token,
		"refresh_token": data["refresh_token"],
	}


static func parse_jwt_payload(token: String) -> Dictionary:
	var parts: PackedStringArray = token.split(".")
	if parts.size() < 2:
		return {}
	var payload: String = String(parts[1]).replace("-", "+").replace("_", "/")
	while payload.length() % 4 != 0:
		payload += "="
	var payload_text: String = Marshalls.base64_to_utf8(payload)
	var parsed: Variant = JSON.parse_string(payload_text)
	if parsed is Dictionary:
		return parsed
	return {}