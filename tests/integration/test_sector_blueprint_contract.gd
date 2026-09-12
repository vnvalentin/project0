extends GutTest
## Headless public-seam test for Slice 008's async validated sector blueprint contract.
## The fake Ollama HTTP harness keeps all service outcomes deterministic.
## Run with the repository validation runner.

const SectorBlueprintSchemaScript: Script = preload("res://shared/sector_blueprint_schema.gd")
const SectorBlueprintServiceScript: Script = preload("res://server/sector_blueprint_service.gd")
const FixturesScript: Script = preload("res://scripts/sector_blueprint_fixtures.gd")
const FakeOllamaHttpServerScript: Script = preload("res://scripts/fake_ollama_http_server.gd")


func _assert(condition: bool, message: String) -> void:
	assert_true(condition, message)


func test_validator_outcomes() -> void:
	var valid_parsed: Variant = JSON.parse_string(FixturesScript.VALID)
	var valid_result: Dictionary = SectorBlueprintSchemaScript.validate(valid_parsed)
	_assert(valid_result["outcome"] == SectorBlueprintSchemaScript.OUTCOME_VALID, "valid fixture validates as OUTCOME_VALID")
	_assert(valid_result["blueprint"] != null, "valid fixture returns a non-null blueprint")

	var malformed_parsed: Variant = JSON.parse_string(FixturesScript.MALFORMED_JSON)
	var malformed_result: Dictionary = SectorBlueprintSchemaScript.validate(malformed_parsed)
	_assert(malformed_result["outcome"] == SectorBlueprintSchemaScript.OUTCOME_MALFORMED_JSON, "malformed JSON fixture validates as OUTCOME_MALFORMED_JSON")

	var incomplete_parsed: Variant = JSON.parse_string(FixturesScript.INCOMPLETE_MISSING_TILES)
	var incomplete_result: Dictionary = SectorBlueprintSchemaScript.validate(incomplete_parsed)
	_assert(incomplete_result["outcome"] == SectorBlueprintSchemaScript.OUTCOME_INCOMPLETE, "fixture missing tiles validates as OUTCOME_INCOMPLETE")

	var unsupported_parsed: Variant = JSON.parse_string(FixturesScript.UNSUPPORTED_KIND)
	var unsupported_result: Dictionary = SectorBlueprintSchemaScript.validate(unsupported_parsed)
	_assert(unsupported_result["outcome"] == SectorBlueprintSchemaScript.OUTCOME_UNSUPPORTED_KIND, "fixture with lava_pit validates as OUTCOME_UNSUPPORTED_KIND")

	var wrong_version_parsed: Variant = JSON.parse_string(FixturesScript.WRONG_SCHEMA_VERSION)
	var wrong_version_result: Dictionary = SectorBlueprintSchemaScript.validate(wrong_version_parsed)
	_assert(wrong_version_result["outcome"] == SectorBlueprintSchemaScript.OUTCOME_WRONG_SCHEMA_VERSION, "fixture with schema_version 99 validates as OUTCOME_WRONG_SCHEMA_VERSION")

	var out_of_bounds_origin_result: Dictionary = SectorBlueprintSchemaScript.validate(JSON.parse_string(FixturesScript.OUT_OF_BOUNDS_ORIGIN))
	_assert(out_of_bounds_origin_result["outcome"] == SectorBlueprintSchemaScript.OUTCOME_OUT_OF_BOUNDS, "out-of-bounds origin validates as OUT_OF_BOUNDS")

	var out_of_bounds_tile_result: Dictionary = SectorBlueprintSchemaScript.validate(JSON.parse_string(FixturesScript.OUT_OF_BOUNDS_TILE))
	_assert(out_of_bounds_tile_result["outcome"] == SectorBlueprintSchemaScript.OUTCOME_OUT_OF_BOUNDS, "out-of-bounds tile validates as OUT_OF_BOUNDS")

	var non_object_result: Dictionary = SectorBlueprintSchemaScript.validate("just a string")
	_assert(non_object_result["outcome"] == SectorBlueprintSchemaScript.OUTCOME_MALFORMED_JSON, "a bare string validates as OUTCOME_MALFORMED_JSON")


func _make_service(fake_port: int) -> Node:
	var service: Node = SectorBlueprintServiceScript.new()
	service.ollama_host = "http://127.0.0.1:%d" % fake_port
	service.request_timeout_sec = 2.0
	add_child_autofree(service)
	return service


func test_service_valid_response_seam() -> void:
	var fake_server: Node = FakeOllamaHttpServerScript.new()
	var port: int = fake_server.start()
	_assert(port > 0, "fake Ollama HTTP harness starts and reports a listening port")
	add_child_autofree(fake_server)

	fake_server.next_response_status = 200
	fake_server.next_response_body = JSON.stringify({"response": FixturesScript.VALID})

	var service: Node = _make_service(port)
	var result: Dictionary = await service.request_sector_blueprint("generate a sector")

	_assert(result["request_outcome"] == SectorBlueprintServiceScript.REQUEST_OUTCOME_VALIDATED, "valid response reaches REQUEST_OUTCOME_VALIDATED")
	_assert(result["validation_outcome"] == SectorBlueprintSchemaScript.OUTCOME_VALID, "valid response validates as OUTCOME_VALID")
	_assert(not result["correlation_id"].is_empty(), "result carries a correlation id")
	_assert(service.get_provenance(result["correlation_id"]).has("requested_at_ticks_msec"), "provenance records a request timestamp")

	service.queue_free()
	fake_server.stop()
	fake_server.queue_free()
	await wait_process_frames(1)


func test_service_malformed_envelope_seam() -> void:
	var fake_server: Node = FakeOllamaHttpServerScript.new()
	var port: int = fake_server.start()
	add_child_autofree(fake_server)
	fake_server.next_response_status = 200
	fake_server.next_response_body = "not even json"

	var service: Node = _make_service(port)
	var result: Dictionary = await service.request_sector_blueprint("generate a sector")

	_assert(result["request_outcome"] == SectorBlueprintServiceScript.REQUEST_OUTCOME_TRANSPORT_ERROR, "malformed envelope reaches REQUEST_OUTCOME_TRANSPORT_ERROR")
	_assert(result["blueprint"] == null, "malformed envelope carries no blueprint")

	service.queue_free()
	fake_server.stop()
	fake_server.queue_free()
	await wait_process_frames(1)


func test_service_http_error_seam() -> void:
	var fake_server: Node = FakeOllamaHttpServerScript.new()
	var port: int = fake_server.start()
	add_child_autofree(fake_server)
	fake_server.next_response_status = 500
	fake_server.next_response_body = "internal error"

	var service: Node = _make_service(port)
	var result: Dictionary = await service.request_sector_blueprint("generate a sector")

	_assert(result["request_outcome"] == SectorBlueprintServiceScript.REQUEST_OUTCOME_TRANSPORT_ERROR, "HTTP 500 reaches REQUEST_OUTCOME_TRANSPORT_ERROR")

	service.queue_free()
	fake_server.stop()
	fake_server.queue_free()
	await wait_process_frames(1)


func test_service_timeout_seam() -> void:
	var fake_server: Node = FakeOllamaHttpServerScript.new()
	var port: int = fake_server.start()
	add_child_autofree(fake_server)
	fake_server.respond_at_all = false

	var service: Node = _make_service(port)
	service.request_timeout_sec = 1.0
	var start_ticks: int = Time.get_ticks_msec()
	var result: Dictionary = await service.request_sector_blueprint("generate a sector")
	var elapsed_ticks: int = Time.get_ticks_msec() - start_ticks

	_assert(result["request_outcome"] == SectorBlueprintServiceScript.REQUEST_OUTCOME_TIMEOUT, "silent fake server reaches REQUEST_OUTCOME_TIMEOUT")
	_assert(elapsed_ticks < 5000, "timeout arrives within a bounded window")

	service.queue_free()
	fake_server.stop()
	fake_server.queue_free()
	await wait_process_frames(1)


func test_service_does_not_block_scene_tree() -> void:
	var fake_server: Node = FakeOllamaHttpServerScript.new()
	var port: int = fake_server.start()
	add_child_autofree(fake_server)
	fake_server.respond_at_all = false

	var service: Node = _make_service(port)
	service.request_timeout_sec = 1.5
	service.call_deferred("request_sector_blueprint", "generate a sector")

	var ticks_observed: int = 0
	while ticks_observed < 5:
		await wait_process_frames(1)
		ticks_observed += 1
	_assert(ticks_observed == 5, "SceneTree processes frames while request is in flight")

	var signal_result: Array = await service.blueprint_request_completed
	var result: Dictionary = signal_result[1]
	_assert(result["request_outcome"] == SectorBlueprintServiceScript.REQUEST_OUTCOME_TIMEOUT, "concurrent request resolves to a bounded timeout")

	service.queue_free()
	fake_server.stop()
	fake_server.queue_free()
	await wait_process_frames(1)


func test_correlation_ids_are_unique_and_recorded() -> void:
	var fake_server: Node = FakeOllamaHttpServerScript.new()
	var port: int = fake_server.start()
	add_child_autofree(fake_server)
	fake_server.next_response_status = 200
	fake_server.next_response_body = JSON.stringify({"response": FixturesScript.VALID})

	var service: Node = _make_service(port)
	var first_result: Dictionary = await service.request_sector_blueprint("first request")
	var second_result: Dictionary = await service.request_sector_blueprint("second request")

	_assert(first_result["correlation_id"] != second_result["correlation_id"], "sequential requests receive distinct correlation ids")
	_assert(not service.get_provenance(first_result["correlation_id"]).is_empty(), "first provenance remains retrievable")
	_assert(not service.get_provenance(second_result["correlation_id"]).is_empty(), "second provenance is retrievable")

	service.queue_free()
	fake_server.stop()
	fake_server.queue_free()
	await wait_process_frames(1)
