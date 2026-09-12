extends Node
class_name LocalLLMClient
## Async client for a local Ollama API instance (e.g. Llama-3-8B on a Tesla P100).
## Server-side only: used by JIT world generation to request structured JSON blueprints.

signal generation_completed(success: bool, parsed_json: Variant, raw_text: String)

@export var ollama_host: String = "http://127.0.0.1:11434"
@export var model_name: String = "llama3:latest"
@export var request_timeout_sec: float = 60.0

var _http_request: HTTPRequest


func _ready() -> void:
	_http_request = HTTPRequest.new()
	_http_request.timeout = request_timeout_sec
	add_child(_http_request)
	_http_request.request_completed.connect(_on_request_completed)


## Sends a prompt to Ollama's /api/generate endpoint and awaits the response.
## Returns a Dictionary: {"success": bool, "data": Variant, "raw": String, "error": String}
func generate_json(prompt: String) -> Dictionary:
	var url: String = "%s/api/generate" % ollama_host
	var headers: PackedStringArray = ["Content-Type: application/json"]

	var body_dict: Dictionary = {
		"model": model_name,
		"prompt": prompt,
		"format": "json",
		"stream": false,
	}
	var body: String = JSON.stringify(body_dict)

	var error: Error = _http_request.request(url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		var fail_result: Dictionary = {
			"success": false,
			"data": null,
			"raw": "",
			"error": "Failed to start request: %s" % error,
		}
		return fail_result

	var response: Array = await _http_request.request_completed
	return _parse_response(response)


func _on_request_completed(_result: int, _response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	# Consumed via the awaited signal in generate_json(); no-op here.
	pass


func _parse_response(response: Array) -> Dictionary:
	var result_code: int = response[0]
	var response_code: int = response[1]
	var body_bytes: PackedByteArray = response[3]
	var body_text: String = body_bytes.get_string_from_utf8()

	if result_code != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		var fail_result: Dictionary = {
			"success": false,
			"data": null,
			"raw": body_text,
			"error": "HTTP request failed (result=%s, code=%s)" % [result_code, response_code],
		}
		return fail_result

	var envelope: Variant = JSON.parse_string(body_text)
	if envelope == null or not (envelope is Dictionary) or not envelope.has("response"):
		var fail_result: Dictionary = {
			"success": false,
			"data": null,
			"raw": body_text,
			"error": "Malformed Ollama envelope",
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
		}
		return fail_result

	var ok_result: Dictionary = {
		"success": true,
		"data": parsed,
		"raw": inner_text,
		"error": "",
	}
	return ok_result
