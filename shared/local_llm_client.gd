extends Node
class_name LocalLLMClient
## Async client for a local Ollama API instance (e.g. Llama-3-8B on a Tesla P100).
## Server-side only: used by JIT world generation to request structured JSON blueprints.
##
## Configuration precedence (Slice 051 / P-009): the exports below carry the
## existing hard-coded defaults so pre-existing callers (SectorBlueprintService,
## ProvisionalSectorGenerator) that assign ollama_host/model_name/
## request_timeout_sec directly, before this node enters the tree, keep working
## unchanged. A caller that instead wants environment-driven configuration must
## explicitly call configure_from_env() after .new() and before add_child();
## _ready() never applies env config on its own, so a bare LocalLLMClient.new()
## with no explicit setup keeps today's compiled-in defaults. configure_from_env()
## only overwrites a field still equal to its default, so it composes safely
## with a caller that sets some but not all fields before calling it.

signal generation_completed(success: bool, parsed_json: Variant, raw_text: String)

## Bounded request-outcome telemetry (CLAUDE.md "Telemetry And Andon Signals"):
## classifies every generate_json() call without ever carrying prompt text,
## raw model body, or secrets. Consumers get outcome/response_code/duration_ms/
## model/host only.
signal request_outcome_reported(telemetry: Dictionary)

const OUTCOME_SUCCESS: String = "success"
const OUTCOME_HTTP_ERROR: String = "http_error"
const OUTCOME_MALFORMED_ENVELOPE: String = "malformed_envelope"
const OUTCOME_INVALID_JSON: String = "invalid_json"
const OUTCOME_TRANSPORT_ERROR: String = "transport_error"
const OUTCOME_TIMEOUT: String = "timeout"

const DEFAULT_OLLAMA_HOST: String = "http://127.0.0.1:11434"
const DEFAULT_MODEL_NAME: String = "llama3:latest"
const DEFAULT_TIMEOUT_SEC: float = 60.0

const ENV_OLLAMA_HOST: String = "PROJECT0_OLLAMA_HOST"
const ENV_MODEL_NAME: String = "PROJECT0_OLLAMA_MODEL"
const ENV_TIMEOUT_SEC: String = "PROJECT0_OLLAMA_TIMEOUT_SEC"

@export var ollama_host: String = DEFAULT_OLLAMA_HOST
@export var model_name: String = DEFAULT_MODEL_NAME
@export var request_timeout_sec: float = DEFAULT_TIMEOUT_SEC

var _http_request: HTTPRequest


func _ready() -> void:
	_http_request = HTTPRequest.new()
	_http_request.timeout = request_timeout_sec
	add_child(_http_request)
	_http_request.request_completed.connect(_on_request_completed)


## Pure static resolver: reads PROJECT0_OLLAMA_HOST/PROJECT0_OLLAMA_MODEL/
## PROJECT0_OLLAMA_TIMEOUT_SEC from the process environment, falling back to
## this client's compiled-in defaults. A non-finite or <= 0 timeout value
## falls back to the default rather than producing an unusable HTTPRequest
## timeout. Returns {"host": String, "model": String, "timeout_sec": float}.
static func resolve_config() -> Dictionary:
	var host: String = DEFAULT_OLLAMA_HOST
	if OS.has_environment(ENV_OLLAMA_HOST):
		var host_value: String = OS.get_environment(ENV_OLLAMA_HOST)
		if not host_value.is_empty():
			host = host_value

	var model: String = DEFAULT_MODEL_NAME
	if OS.has_environment(ENV_MODEL_NAME):
		var model_value: String = OS.get_environment(ENV_MODEL_NAME)
		if not model_value.is_empty():
			model = model_value

	var timeout_sec: float = DEFAULT_TIMEOUT_SEC
	if OS.has_environment(ENV_TIMEOUT_SEC):
		var timeout_text: String = OS.get_environment(ENV_TIMEOUT_SEC)
		if timeout_text.is_valid_float():
			var candidate: float = timeout_text.to_float()
			if is_finite(candidate) and candidate > 0.0:
				timeout_sec = candidate

	return {
		"host": host,
		"model": model,
		"timeout_sec": timeout_sec,
	}


## Explicit opt-in for server boot paths that want environment-driven
## configuration. Must be called after .new() and before this node enters the
## tree (mirrors the existing convention documented on
## ProvisionalSectorGenerator's exports). Only overwrites a field still equal
## to this client's compiled-in default, so a caller that already assigned
## ollama_host/model_name/request_timeout_sec explicitly is left untouched.
func configure_from_env() -> void:
	var config: Dictionary = resolve_config()
	if ollama_host == DEFAULT_OLLAMA_HOST:
		ollama_host = config["host"]
	if model_name == DEFAULT_MODEL_NAME:
		model_name = config["model"]
	if is_equal_approx(request_timeout_sec, DEFAULT_TIMEOUT_SEC):
		request_timeout_sec = config["timeout_sec"]


## Sends a prompt to Ollama's /api/generate endpoint and awaits the response.
## Returns a Dictionary: {"success": bool, "data": Variant, "raw": String,
## "error": String, "outcome": String, "duration_ms": int}. Also emits
## request_outcome_reported() with a bounded telemetry Dictionary carrying no
## prompt text, raw body, or secrets.
## An optional server-owned absolute monotonic deadline includes preparation
## time. At/after it no candidate is accepted; cancellation resumes on the first
## runnable frame, not a hard real-time scheduling guarantee. The native Timer
## is disabled only for this path. clock_usec is an injectable monotonic clock.
func generate_json(prompt: String, deadline_usec: int = 0, clock_usec: Callable = Callable()) -> Dictionary:
	var started_usec: int = _now_usec(clock_usec)
	var url: String = "%s/api/generate" % ollama_host
	var headers: PackedStringArray = ["Content-Type: application/json"]

	var body_dict: Dictionary = {
		"model": model_name,
		"prompt": prompt,
		"format": "json",
		"think": false,
		"stream": false,
	}
	var body: String = JSON.stringify(body_dict)

	if deadline_usec > 0 and _now_usec(clock_usec) >= deadline_usec:
		return _deadline_result(started_usec, clock_usec)
	var responses: Array[Array] = []
	var capture: Callable = func(result_code: int, response_code: int, response_headers: PackedStringArray, response_body: PackedByteArray) -> void:
		responses.append([result_code, response_code, response_headers, response_body])
	if deadline_usec > 0:
		_http_request.request_completed.connect(capture)

	_http_request.timeout = 0.0 if deadline_usec > 0 else request_timeout_sec
	var error: Error = _http_request.request(url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		if deadline_usec > 0:
			_http_request.request_completed.disconnect(capture)
		var fail_result: Dictionary = {
			"success": false,
			"data": null,
			"raw": "",
			"error": "Failed to start request: %s" % error,
			"outcome": OUTCOME_TRANSPORT_ERROR,
			"duration_ms": (_now_usec(clock_usec) - started_usec) / 1000,
		}
		_report_outcome(fail_result, -1)
		return fail_result

	var response: Array
	if deadline_usec > 0:
		while responses.is_empty() and _now_usec(clock_usec) < deadline_usec:
			await get_tree().process_frame
		_http_request.request_completed.disconnect(capture)
		if _now_usec(clock_usec) >= deadline_usec:
			_http_request.cancel_request()
			return _deadline_result(started_usec, clock_usec)
		response = responses[0]
	else:
		response = await _http_request.request_completed
	var result: Dictionary = _parse_response(response)
	if deadline_usec > 0 and _now_usec(clock_usec) >= deadline_usec:
		return _deadline_result(started_usec, clock_usec)
	result["duration_ms"] = (_now_usec(clock_usec) - started_usec) / 1000
	_report_outcome(result, response[1])
	return result


func _deadline_result(started_usec: int, clock_usec: Callable) -> Dictionary:
	var result: Dictionary = {
		"success": false,
		"data": null,
		"raw": "",
		"error": "JIT generation deadline exceeded (result=%d)" % HTTPRequest.RESULT_TIMEOUT,
		"outcome": OUTCOME_TIMEOUT,
		"duration_ms": (_now_usec(clock_usec) - started_usec) / 1000,
	}
	_report_outcome(result, -1)
	return result


func _now_usec(clock_usec: Callable) -> int:
	return int(clock_usec.call()) if clock_usec.is_valid() else Time.get_ticks_usec()


func _report_outcome(result: Dictionary, response_code: int) -> void:
	var telemetry: Dictionary = {
		"outcome": result["outcome"],
		"response_code": response_code,
		"duration_ms": result["duration_ms"],
		"model": model_name,
		"host": ollama_host,
	}
	request_outcome_reported.emit(telemetry)


func _on_request_completed(_result: int, _response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	# Consumed via the awaited signal in generate_json(); no-op here.
	pass


func _parse_response(response: Array) -> Dictionary:
	var result_code: int = response[0]
	var response_code: int = response[1]
	var body_bytes: PackedByteArray = response[3]
	var body_text: String = body_bytes.get_string_from_utf8()

	if result_code != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		var outcome: String = OUTCOME_TIMEOUT if result_code == HTTPRequest.RESULT_TIMEOUT else (OUTCOME_HTTP_ERROR if result_code == HTTPRequest.RESULT_SUCCESS else OUTCOME_TRANSPORT_ERROR)
		var fail_result: Dictionary = {
			"success": false,
			"data": null,
			"raw": body_text,
			"error": "HTTP request failed (result=%s, code=%s)" % [result_code, response_code],
			"outcome": outcome,
		}
		return fail_result

	var envelope: Variant = JSON.parse_string(body_text)
	if envelope == null or not (envelope is Dictionary) or not envelope.has("response"):
		var fail_result: Dictionary = {
			"success": false,
			"data": null,
			"raw": body_text,
			"error": "Malformed Ollama envelope",
			"outcome": OUTCOME_MALFORMED_ENVELOPE,
		}
		return fail_result

	var inner_text: String = envelope["response"]
	var parsed: Variant = JSON.parse_string(inner_text)
	if parsed == null:
		var fail_result: Dictionary = {
			"success": false,
			"data": null,
			"raw": inner_text,
			"error": "Model output was not valid JSON",
			"outcome": OUTCOME_INVALID_JSON,
		}
		return fail_result

	var ok_result: Dictionary = {
		"success": true,
		"data": parsed,
		"raw": inner_text,
		"error": "",
		"outcome": OUTCOME_SUCCESS,
	}
	return ok_result
