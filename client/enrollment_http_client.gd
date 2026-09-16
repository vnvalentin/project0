extends Node
class_name EnrollmentHttpClient
## Slice 091 (ADR 0005 Option A): the Godot client's HTTPS seam to the public
## enrollment service — pre-tunnel login and account-scoped character
## list/create/select/delete. Consumes the Slice 088 `/login` and Slice 090
## `/characters/*` routes. Bounded and fail-closed: every method is a coroutine
## returning a typed result Dictionary and never raises. Uses the same
## `HTTPRequest` + `await request_completed` pattern as the codebase's other
## bounded HTTP clients (one child HTTPRequest runs one request at a time, so
## callers await a method before starting the next).
##
## Client-only per CLAUDE.md: this talks to the public HTTPS surface, never to
## the login authority's loopback endpoint or the ENet login server directly.

const DEFAULT_BASE_URL: String = "https://enroll.valentin.vip"
const ENV_BASE_URL: String = "PROJECT0_ENROLLMENT_URL"
const DEFAULT_TIMEOUT_SEC: float = 10.0

const OUTCOME_OK: String = "ok"
const OUTCOME_TRANSPORT_ERROR: String = "transport_error"
const OUTCOME_TIMEOUT: String = "timeout"
const OUTCOME_HTTP_ERROR: String = "http_error"
const OUTCOME_MALFORMED: String = "malformed"

@export var request_timeout_sec: float = DEFAULT_TIMEOUT_SEC

var _http_request: HTTPRequest = null


func _ready() -> void:
	_http_request = HTTPRequest.new()
	_http_request.timeout = request_timeout_sec
	add_child(_http_request)


## Resolves the public enrollment base URL: PROJECT0_ENROLLMENT_URL or the
## compiled-in default. Trailing slashes and a trailing "/redeem" are trimmed so
## a value provisioned for the launcher's redeem flow still yields correct
## /login and /characters/* paths (mirrors the Go launcher's enrollmentBaseURL).
## Never returns an empty string.
static func resolve_base_url() -> String:
	var value: String = OS.get_environment(ENV_BASE_URL).strip_edges()
	if value.is_empty():
		return DEFAULT_BASE_URL
	value = value.rstrip("/")
	if value.ends_with("/redeem"):
		value = value.substr(0, value.length() - "/redeem".length())
	return value.rstrip("/")


## Log in over HTTPS. Returns {"outcome": OUTCOME_OK, "assertion": String} on a
## 2xx with a string assertion, else {"outcome": <bounded failure>, "status": int}.
func login(base_url: String, username: String, password: String) -> Dictionary:
	var result: Dictionary = await _post_json(base_url, "/login", {"username": username, "password": password})
	return _require_string_field(result, "assertion")

func register(base_url: String, username: String, password: String) -> Dictionary:
	var result: Dictionary = await _post_json(base_url, "/register", {"username": username, "password": password})
	if result["outcome"] != OUTCOME_OK:
		return {"outcome": result["outcome"], "status": result["status"]}
	var data: Dictionary = result["data"]
	if not (data.get("account_id") is String) or not (data.get("username") is String):
		return {"outcome": OUTCOME_MALFORMED, "status": result["status"]}
	return {"outcome": OUTCOME_OK, "account_id": data["account_id"], "username": data["username"]}


## List the account's Characters. Returns {"outcome": OUTCOME_OK, "characters": Array}.
func list_characters(base_url: String, assertion: String) -> Dictionary:
	var result: Dictionary = await _post_json(base_url, "/characters/list", {"assertion": assertion})
	return _require_array_field(result, "characters")


## Create a Character. Returns {"outcome": OUTCOME_OK, "character": Dictionary}.
func create_character(base_url: String, assertion: String, name: String, cosmetic: Dictionary) -> Dictionary:
	var result: Dictionary = await _post_json(base_url, "/characters/create", {"assertion": assertion, "name": name, "cosmetic": cosmetic})
	return _require_dict_field(result, "character")


## Select a Character and receive the signed CHARACTER assertion for world entry.
## Returns {"outcome": OUTCOME_OK, "assertion": String}.
func select_character(base_url: String, assertion: String, character_id: String) -> Dictionary:
	var result: Dictionary = await _post_json(base_url, "/characters/select", {"assertion": assertion, "character_id": character_id})
	return _require_string_field(result, "assertion")


## Soft-delete a Character. Returns {"outcome": OUTCOME_OK}.
func delete_character(base_url: String, assertion: String, character_id: String) -> Dictionary:
	var result: Dictionary = await _post_json(base_url, "/characters/delete", {"assertion": assertion, "character_id": character_id})
	if result["outcome"] != OUTCOME_OK:
		return {"outcome": result["outcome"], "status": result["status"]}
	return {"outcome": OUTCOME_OK}


## Posts a JSON body and awaits the response, returning
## {"outcome": ..., "status": int, "data": Variant}. outcome is OUTCOME_OK only
## for a 2xx JSON-object response; a non-2xx is OUTCOME_HTTP_ERROR (data carries
## the parsed error body when present), a timeout OUTCOME_TIMEOUT, any other
## transport failure OUTCOME_TRANSPORT_ERROR, and a non-JSON body OUTCOME_MALFORMED.
func _post_json(base_url: String, path: String, body: Dictionary) -> Dictionary:
	var url: String = "%s%s" % [base_url.rstrip("/"), path]
	var headers: PackedStringArray = ["Content-Type: application/json"]
	var error: Error = _http_request.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if error != OK:
		return {"outcome": OUTCOME_TRANSPORT_ERROR, "status": -1, "data": null}
	var response: Array = await _http_request.request_completed
	return _parse(response)


func _parse(response: Array) -> Dictionary:
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


## Shared shape for /login and /characters/select, whose success body is a
## single string `field` (the account or character assertion respectively).
func _require_string_field(result: Dictionary, field: String) -> Dictionary:
	if result["outcome"] != OUTCOME_OK:
		return {"outcome": result["outcome"], "status": result["status"]}
	var data: Dictionary = result["data"]
	if not (data.get(field) is String):
		return {"outcome": OUTCOME_MALFORMED, "status": result["status"]}
	return {"outcome": OUTCOME_OK, field: data[field]}


## Extractor for a success body carrying a single Array `field` (list).
func _require_array_field(result: Dictionary, field: String) -> Dictionary:
	if result["outcome"] != OUTCOME_OK:
		return {"outcome": result["outcome"], "status": result["status"]}
	var data: Dictionary = result["data"]
	if not (data.get(field) is Array):
		return {"outcome": OUTCOME_MALFORMED, "status": result["status"]}
	return {"outcome": OUTCOME_OK, field: data[field]}


## Extractor for a success body carrying a single Dictionary `field` (create).
func _require_dict_field(result: Dictionary, field: String) -> Dictionary:
	if result["outcome"] != OUTCOME_OK:
		return {"outcome": result["outcome"], "status": result["status"]}
	var data: Dictionary = result["data"]
	if not (data.get(field) is Dictionary):
		return {"outcome": OUTCOME_MALFORMED, "status": result["status"]}
	return {"outcome": OUTCOME_OK, field: data[field]}
