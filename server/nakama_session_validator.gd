extends Node
class_name NakamaSessionValidator
## Slice 173: server-only validation of a Nakama bearer session through the
## authenticated account endpoint. Never decode or trust a client JWT locally.

const OUTCOME_OK: String = "ok"
const OUTCOME_CONFIG_ERROR: String = "config_error"
const OUTCOME_TRANSPORT_ERROR: String = "transport_error"
const OUTCOME_TIMEOUT: String = "timeout"
const OUTCOME_HTTP_ERROR: String = "http_error"
const OUTCOME_MALFORMED: String = "malformed"

const DEFAULT_TIMEOUT_SEC: float = 5.0
const DEFAULT_BASE_URL: String = "http://127.0.0.1:7350"
const ENV_BASE_URL: String = "PROJECT0_NAKAMA_URL"

@export var request_timeout_sec: float = DEFAULT_TIMEOUT_SEC

var _http_request: HTTPRequest = null
var _base_url: String = ""


func _init(base_url: String = "") -> void:
	_base_url = base_url.strip_edges().rstrip("/")
	if _base_url.is_empty():
		_base_url = OS.get_environment(ENV_BASE_URL).strip_edges().rstrip("/")
	if _base_url.is_empty():
		_base_url = DEFAULT_BASE_URL


func _ready() -> void:
	_http_request = HTTPRequest.new()
	_http_request.timeout = request_timeout_sec
	add_child(_http_request)


func validate(token: String) -> Dictionary:
	if token.strip_edges().is_empty() or _base_url.is_empty():
		return {"outcome": OUTCOME_CONFIG_ERROR}
	var error: Error = _http_request.request(
		"%s/v2/account" % _base_url,
		["Authorization: Bearer %s" % token.strip_edges()],
		HTTPClient.METHOD_GET
	)
	if error != OK:
		return {"outcome": OUTCOME_TRANSPORT_ERROR, "status": -1}
	return parse_response(await _http_request.request_completed)


static func parse_response(response: Array) -> Dictionary:
	var result_code: int = response[0]
	var status: int = response[1]
	var body_text: String = (response[3] as PackedByteArray).get_string_from_utf8()
	if result_code == HTTPRequest.RESULT_TIMEOUT:
		return {"outcome": OUTCOME_TIMEOUT, "status": status}
	if result_code != HTTPRequest.RESULT_SUCCESS:
		return {"outcome": OUTCOME_TRANSPORT_ERROR, "status": status}
	var parsed: Variant = JSON.parse_string(body_text)
	if not (parsed is Dictionary):
		return {"outcome": OUTCOME_MALFORMED, "status": status}
	if status < 200 or status >= 300:
		return {"outcome": OUTCOME_HTTP_ERROR, "status": status}
	var user: Variant = parsed.get("user", parsed)
	if not (user is Dictionary) or not (user.get("id") is String) or String(user["id"]).strip_edges().is_empty():
		return {"outcome": OUTCOME_MALFORMED, "status": status}
	return {
		"outcome": OUTCOME_OK,
		"status": status,
		"nakama_user_id": String(user["id"]),
		"username": String(user.get("username", user.get("display_name", ""))),
	}