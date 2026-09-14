extends GutTest
## Headless public-seam test for Slice 051's bounded request-outcome
## telemetry on LocalLLMClient (P-009). The fake Ollama HTTP harness keeps
## every outcome deterministic; no live Ollama instance is used here.

const LocalLLMClientScript: Script = preload("res://shared/local_llm_client.gd")
const FixturesScript: Script = preload("res://scripts/sector_blueprint_fixtures.gd")
const FakeOllamaHttpServerScript: Script = preload("res://scripts/fake_ollama_http_server.gd")


func _make_client(fake_port: int) -> Node:
	var client: Node = LocalLLMClientScript.new()
	client.ollama_host = "http://127.0.0.1:%d" % fake_port
	client.model_name = "llama3:latest"
	client.request_timeout_sec = 2.0
	add_child_autofree(client)
	return client


func _assert_bounded_telemetry(telemetry: Dictionary, expected_outcome: String) -> void:
	assert_eq(telemetry["outcome"], expected_outcome, "telemetry outcome matches expected classification")
	assert_true(telemetry["duration_ms"] >= 0, "telemetry duration_ms is non-negative")
	assert_eq(telemetry["model"], "llama3:latest", "telemetry carries the configured model")
	assert_true(String(telemetry["host"]).begins_with("http://127.0.0.1:"), "telemetry carries the configured host")
	assert_false(telemetry.has("prompt"), "telemetry never carries prompt text")
	assert_false(telemetry.has("raw"), "telemetry never carries the raw model body")
	assert_false(telemetry.has("data"), "telemetry never carries parsed model data")


func test_configured_model_success_reports_success_outcome() -> void:
	var fake_server: Node = FakeOllamaHttpServerScript.new()
	var port: int = fake_server.start()
	assert_true(port > 0, "fake Ollama HTTP harness starts and reports a listening port")
	add_child_autofree(fake_server)

	fake_server.next_response_status = 200
	fake_server.next_response_body = JSON.stringify({"response": FixturesScript.VALID})

	var client: Node = _make_client(port)
	var reported: Array = []
	client.request_outcome_reported.connect(func(telemetry: Dictionary) -> void:
		reported.append(telemetry)
	)

	var result: Dictionary = await client.generate_json("generate a sector")

	assert_true(result["success"], "valid envelope + valid inner JSON is a successful result")
	assert_eq(result["outcome"], LocalLLMClientScript.OUTCOME_SUCCESS, "result outcome is success")
	assert_true(result["duration_ms"] >= 0, "result duration_ms is non-negative")
	assert_eq(reported.size(), 1, "exactly one telemetry event is reported")
	_assert_bounded_telemetry(reported[0], LocalLLMClientScript.OUTCOME_SUCCESS)

	fake_server.stop()
	await wait_process_frames(1)


func test_http_error_reports_http_error_outcome() -> void:
	var fake_server: Node = FakeOllamaHttpServerScript.new()
	var port: int = fake_server.start()
	add_child_autofree(fake_server)
	fake_server.next_response_status = 500
	fake_server.next_response_body = "internal error"

	var client: Node = _make_client(port)
	var reported: Array = []
	client.request_outcome_reported.connect(func(telemetry: Dictionary) -> void:
		reported.append(telemetry)
	)

	var result: Dictionary = await client.generate_json("generate a sector")

	assert_false(result["success"], "HTTP 500 is not a successful result")
	assert_eq(result["outcome"], LocalLLMClientScript.OUTCOME_HTTP_ERROR, "result outcome is http_error")
	assert_eq(reported[0]["response_code"], 500, "telemetry carries the HTTP response code")
	_assert_bounded_telemetry(reported[0], LocalLLMClientScript.OUTCOME_HTTP_ERROR)

	fake_server.stop()
	await wait_process_frames(1)


func test_malformed_envelope_reports_malformed_envelope_outcome() -> void:
	var fake_server: Node = FakeOllamaHttpServerScript.new()
	var port: int = fake_server.start()
	add_child_autofree(fake_server)
	fake_server.next_response_status = 200
	fake_server.next_response_body = JSON.stringify({"not_response": "oops"})

	var client: Node = _make_client(port)
	var reported: Array = []
	client.request_outcome_reported.connect(func(telemetry: Dictionary) -> void:
		reported.append(telemetry)
	)

	var result: Dictionary = await client.generate_json("generate a sector")

	assert_false(result["success"], "envelope missing 'response' key is not a successful result")
	assert_eq(result["outcome"], LocalLLMClientScript.OUTCOME_MALFORMED_ENVELOPE, "result outcome is malformed_envelope")
	_assert_bounded_telemetry(reported[0], LocalLLMClientScript.OUTCOME_MALFORMED_ENVELOPE)

	fake_server.stop()
	await wait_process_frames(1)


func test_invalid_inner_json_reports_invalid_json_outcome() -> void:
	var fake_server: Node = FakeOllamaHttpServerScript.new()
	var port: int = fake_server.start()
	add_child_autofree(fake_server)
	fake_server.next_response_status = 200
	fake_server.next_response_body = JSON.stringify({"response": "not json"})

	var client: Node = _make_client(port)
	var reported: Array = []
	client.request_outcome_reported.connect(func(telemetry: Dictionary) -> void:
		reported.append(telemetry)
	)

	var result: Dictionary = await client.generate_json("generate a sector")

	assert_false(result["success"], "non-JSON inner response text is not a successful result")
	assert_eq(result["outcome"], LocalLLMClientScript.OUTCOME_INVALID_JSON, "result outcome is invalid_json")
	_assert_bounded_telemetry(reported[0], LocalLLMClientScript.OUTCOME_INVALID_JSON)

	fake_server.stop()
	await wait_process_frames(1)


func test_timeout_reports_timeout_outcome() -> void:
	var fake_server: Node = FakeOllamaHttpServerScript.new()
	var port: int = fake_server.start()
	add_child_autofree(fake_server)
	fake_server.respond_at_all = false

	var client: Node = _make_client(port)
	client.request_timeout_sec = 1.0
	var reported: Array = []
	client.request_outcome_reported.connect(func(telemetry: Dictionary) -> void:
		reported.append(telemetry)
	)

	var start_ticks: int = Time.get_ticks_msec()
	var result: Dictionary = await client.generate_json("generate a sector")
	var elapsed_ticks: int = Time.get_ticks_msec() - start_ticks

	assert_false(result["success"], "a silent server produces no successful result")
	assert_eq(result["outcome"], LocalLLMClientScript.OUTCOME_TIMEOUT, "result outcome is timeout")
	assert_true(elapsed_ticks < 5000, "timeout arrives within a bounded window")
	_assert_bounded_telemetry(reported[0], LocalLLMClientScript.OUTCOME_TIMEOUT)

	fake_server.stop()
	await wait_process_frames(1)
