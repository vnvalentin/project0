extends GutTest
## Headless public-seam smoke test for Slice 008's async validated sector
## blueprint contract. Two parts:
## 1. Pure validator assertions against SectorBlueprintSchema using fixture
##    JSON strings (no network, no async).
## 2. Async SectorBlueprintService assertions against a local fake HTTP
##    harness (FakeOllamaHttpServer) that stands in for Ollama, proving the
##    request/response/timeout seam end-to-end and that a request in flight
##    does not block the SceneTree's own frame processing — all without
##    requiring a real Ollama instance, per
##    .scratch/game-vision/issues/15-sector-blueprint-contract.md.
##
## Run with the repository validation runner.

const SectorBlueprintSchemaScript: Script = preload("res://shared/sector_blueprint_schema.gd")
const SectorBlueprintServiceScript: Script = preload("res://server/sector_blueprint_service.gd")
const FixturesScript: Script = preload("res://scripts/sector_blueprint_fixtures.gd")
const FakeOllamaHttpServerScript: Script = preload("res://scripts/fake_ollama_http_server.gd")

func _assert(condition: bool, message: String) -> void:
	assert_true(condition, message)


## Part 1: pure validator outcomes, no network, no async.
func test_validator_outcomes() -> void:
	var valid_parsed: Variant = JSON.parse_string(FixturesScript.VALID)
	var valid_result: Dictionary = SectorBlueprintSchemaScript.validate(valid_parsed)
	_assert(valid_result["outcome"] == SectorBlueprintSchemaScript.OUTCOME_VALID, "valid fixture validates as OUTCOME_VALID")
	_assert(valid_result["blueprint"] != null, "valid fixture returns a non-null blueprint")

	var malformed_parsed: Variant = JSON.parse_string(FixturesScript.MALFORMED_JSON)
	var malformed_result: Dictionary = SectorBlueprintSchemaScript.validate(malformed_parsed)
	_assert(malformed_result["outcome"] == SectorBlueprintSchemaScript.OUTCOME_MALFORMED_JSON, "malformed JSON fixture (parses to null) validates as OUTCOME_MALFORMED_JSON")

	var incomplete_parsed: Variant = JSON.parse_string(FixturesScript.INCOMPLETE_MISSING_TILES)
	var incomplete_result: Dictionary = SectorBlueprintSchemaScript.validate(incomplete_parsed)
	_assert(incomplete_result["outcome"] == SectorBlueprintSchemaScript.OUTCOME_INCOMPLETE, "fixture missing 'tiles' validates as OUTCOME_INCOMPLETE")

	var unsupported_parsed: Variant = JSON.parse_string(FixturesScript.UNSUPPORTED_KIND)
	var unsupported_result: Dictionary = SectorBlueprintSchemaScript.validate(unsupported_parsed)
	_assert(unsupported_result["outcome"] == SectorBlueprintSchemaScript.OUTCOME_UNSUPPORTED_KIND, "fixture with tile kind 'lava_pit' validates as OUTCOME_UNSUPPORTED_KIND")

	var wrong_version_parsed: Variant = JSON.parse_string(FixturesScript.WRONG_SCHEMA_VERSION)
	var wrong_version_result: Dictionary = SectorBlueprintSchemaScript.validate(wrong_version_parsed)
	_assert(wrong_version_result["outcome"] == SectorBlueprintSchemaScript.OUTCOME_WRONG_SCHEMA_VERSION, "fixture with schema_version 99 validates as OUTCOME_WRONG_SCHEMA_VERSION")

	var out_of_bounds_origin_result: Dictionary = SectorBlueprintSchemaScript.validate(JSON.parse_string(FixturesScript.OUT_OF_BOUNDS_ORIGIN))
	_assert(out_of_bounds_origin_result["outcome"] == SectorBlueprintSchemaScript.OUTCOME_OUT_OF_BOUNDS, "fixture with an out-of-bounds origin validates as OUTCOME_OUT_OF_BOUNDS")

	var out_of_bounds_tile_result: Dictionary = SectorBlueprintSchemaScript.validate(JSON.parse_string(FixturesScript.OUT_OF_BOUNDS_TILE))
	_assert(out_of_bounds_tile_result["outcome"] == SectorBlueprintSchemaScript.OUTCOME_OUT_OF_BOUNDS, "fixture with an out-of-bounds tile validates as OUTCOME_OUT_OF_BOUNDS")

	# Fail-closed on inputs with no shape at all.
	var non_object_result: Dictionary = SectorBlueprintSchemaScript.validate("just a string")
	_assert(non_object_result["outcome"] == SectorBlueprintSchemaScript.OUTCOME_MALFORMED_JSON, "a bare string (not an object) validates as OUTCOME_MALFORMED_JSON")


## Part 2: async service seam against a real HTTP round trip via the fake
## Ollama harness, proving success/error/timeout outcomes without Ollama.
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

	var envelope: Dictionary = {"response": FixturesScript.VALID}
	fake_server.next_response_status = 200
	fake_server.next_response_body = JSON.stringify(envelope)

	var service: Node = _make_service(port)
	var result: Dictionary = await service.request_sector_blueprint("generate a sector")

	_assert(result["request_outcome"] == SectorBlueprintServiceScript.REQUEST_OUTCOME_VALIDATED, "valid fake-server response reaches REQUEST_OUTCOME_VALIDATED")
	_assert(result["validation_outcome"] == SectorBlueprintSchemaScript.OUTCOME_VALID, "valid fake-server response validates as OUTCOME_VALID")
	_assert(not result["correlation_id"].is_empty(), "result carries a non-empty correlation id")
	_assert(service.get_provenance(result["correlation_id"]).has("requested_at_ticks_msec"), "provenance for the correlation id is recorded with a request timestamp")

	service.queue_free()
	fake_server.stop()
	fake_server.queue_free()
	await process_frame


func test_service_malformed_envelope_seam() -> void:
	var fake_server: Node = FakeOllamaHttpServerScript.new()
	var port: int = fake_server.start()
	add_child_autofree(fake_server)

	fake_server.next_response_status = 200
	fake_server.next_response_body = "not even json"

	var service: Node = _make_service(port)
	var result: Dictionary = await service.request_sector_blueprint("generate a sector")

	_assert(result["request_outcome"] == SectorBlueprintServiceScript.REQUEST_OUTCOME_TRANSPORT_ERROR, "malformed Ollama envelope reaches REQUEST_OUTCOME_TRANSPORT_ERROR")
	_assert(result["blueprint"] == null, "malformed envelope result carries no blueprint")

	service.queue_free()
	fake_server.stop()
	fake_server.queue_free()
	await process_frame


func test_service_http_error_seam() -> void:
	var fake_server: Node = FakeOllamaHttpServerScript.new()
	var port: int = fake_server.start()
	add_child_autofree(fake_server)

	fake_server.next_response_status = 500
	fake_server.next_response_body = "internal error"

	var service: Node = _make_service(port)
	var result: Dictionary = await service.request_sector_blueprint("generate a sector")

	_assert(result["request_outcome"] == SectorBlueprintServiceScript.REQUEST_OUTCOME_TRANSPORT_ERROR, "HTTP 500 from fake server reaches REQUEST_OUTCOME_TRANSPORT_ERROR")

	service.queue_free()
	fake_server.stop()
	fake_server.queue_free()
	await process_frame


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

	_assert(result["request_outcome"] == SectorBlueprintServiceScript.REQUEST_OUTCOME_TIMEOUT, "a silent fake server reaches REQUEST_OUTCOME_TIMEOUT")
	_assert(elapsed_ticks < 5000, "timeout outcome arrives within a bounded window (< 5s) rather than hanging")

	service.queue_free()
	fake_server.stop()
	fake_server.queue_free()
	await process_frame


## Highest-risk BDD scenario: an in-flight request must not block the
## SceneTree's own frame processing (i.e. the multiplayer loop). Proven by
## starting a request that will not resolve for 1.5s (the fake server never
## replies), observing that several process_frame signals still fire while it
## is in flight (fire-and-forget via call_deferred, since GDScript's `await`
## on a coroutine call blocks the *caller* until that coroutine's next signal
## await, which would defeat the purpose of this assertion), and only then
## awaiting the service's own completion signal for the bounded timeout
## outcome.
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
		await process_frame
		ticks_observed += 1
	_assert(ticks_observed == 5, "SceneTree processed multiple frames while a blueprint request was still in flight (loop not blocked)")

	var signal_result: Array = await service.blueprint_request_completed
	var result: Dictionary = signal_result[1]
	_assert(result["request_outcome"] == SectorBlueprintServiceScript.REQUEST_OUTCOME_TIMEOUT, "the concurrently-observed request still resolves to a bounded timeout outcome")

	service.queue_free()
	fake_server.stop()
	fake_server.queue_free()
	await process_frame


func test_correlation_ids_are_unique_and_recorded() -> void:
	var fake_server: Node = FakeOllamaHttpServerScript.new()
	var port: int = fake_server.start()
	add_child_autofree(fake_server)

	var envelope: Dictionary = {"response": FixturesScript.VALID}
	fake_server.next_response_status = 200
	fake_server.next_response_body = JSON.stringify(envelope)

	var service: Node = _make_service(port)
	var first_result: Dictionary = await service.request_sector_blueprint("first request")
	var second_result: Dictionary = await service.request_sector_blueprint("second request")

	_assert(first_result["correlation_id"] != second_result["correlation_id"], "two sequential requests receive distinct correlation ids")
	_assert(not service.get_provenance(first_result["correlation_id"]).is_empty(), "first request's provenance remains retrievable after a second request")
	_assert(not service.get_provenance(second_result["correlation_id"]).is_empty(), "second request's provenance is retrievable")

	service.queue_free()
	fake_server.stop()
	fake_server.queue_free()
	await process_frame
