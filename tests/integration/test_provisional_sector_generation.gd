extends GutTest
## Headless public-seam test for Slice 009's asynchronous provisional sector
## generation seam. Reuses Slice 008's fake Ollama HTTP harness so outcomes
## stay deterministic without a live Ollama instance.

const ProvisionalSectorGeneratorScript: Script = preload("res://server/provisional_sector_generator.gd")
const SectorBlueprintServiceScript: Script = preload("res://server/sector_blueprint_service.gd")
const SectorBlueprintSchemaScript: Script = preload("res://shared/sector_blueprint_schema.gd")
const FixturesScript: Script = preload("res://scripts/sector_blueprint_fixtures.gd")
const FakeOllamaHttpServerScript: Script = preload("res://scripts/fake_ollama_http_server.gd")


func _assert(condition: bool, message: String) -> void:
	assert_true(condition, message)


func _make_generator(fake_port: int) -> Node:
	var generator: Node = ProvisionalSectorGeneratorScript.new()
	add_child_autofree(generator)
	generator._blueprint_service.ollama_host = "http://127.0.0.1:%d" % fake_port
	generator._blueprint_service.request_timeout_sec = 2.0
	return generator


func test_request_is_accepted_synchronously_as_pending() -> void:
	var fake_server: Node = FakeOllamaHttpServerScript.new()
	var port: int = fake_server.start()
	add_child_autofree(fake_server)
	fake_server.next_response_status = 200
	fake_server.next_response_body = JSON.stringify({"response": FixturesScript.VALID})

	var generator: Node = _make_generator(port)
	var correlation_id: String = generator.request_provisional_sector("sector-0-0", "generate a sector")

	_assert(not correlation_id.is_empty(), "acceptance returns a non-empty correlation id without awaiting")
	_assert(generator.get_status("sector-0-0") == ProvisionalSectorGeneratorScript.STATUS_PENDING, "sector is pending immediately after acceptance")
	_assert(generator.get_provisional_result("sector-0-0").is_empty(), "no provisional result exists while pending")

	var signal_result: Array = await generator.provisional_sector_ready
	var sector_id: String = signal_result[0]
	_assert(sector_id == "sector-0-0", "completion signal reports the requested sector id")

	fake_server.stop()


func test_success_outcome_carries_validated_blueprint() -> void:
	var fake_server: Node = FakeOllamaHttpServerScript.new()
	var port: int = fake_server.start()
	add_child_autofree(fake_server)
	fake_server.next_response_status = 200
	fake_server.next_response_body = JSON.stringify({"response": FixturesScript.VALID})

	var generator: Node = _make_generator(port)
	generator.request_provisional_sector("sector-0-0", "generate a sector")
	await generator.provisional_sector_ready

	_assert(generator.get_status("sector-0-0") == ProvisionalSectorGeneratorScript.STATUS_READY, "sector reaches ready status on success")
	var result: Dictionary = generator.get_provisional_result("sector-0-0")
	_assert(result["request_outcome"] == SectorBlueprintServiceScript.REQUEST_OUTCOME_VALIDATED, "ready result reaches REQUEST_OUTCOME_VALIDATED")
	_assert(result["validation_outcome"] == SectorBlueprintSchemaScript.OUTCOME_VALID, "ready result validates as OUTCOME_VALID")
	_assert(result["blueprint"] != null, "ready result carries the validated blueprint")

	fake_server.stop()


func test_validation_failure_outcome_is_ready_with_no_blueprint() -> void:
	var fake_server: Node = FakeOllamaHttpServerScript.new()
	var port: int = fake_server.start()
	add_child_autofree(fake_server)
	fake_server.next_response_status = 200
	fake_server.next_response_body = JSON.stringify({"response": FixturesScript.UNSUPPORTED_KIND})

	var generator: Node = _make_generator(port)
	generator.request_provisional_sector("sector-bad-kind", "generate a sector")
	await generator.provisional_sector_ready

	_assert(generator.get_status("sector-bad-kind") == ProvisionalSectorGeneratorScript.STATUS_READY, "sector reaches ready status even on validation failure")
	var result: Dictionary = generator.get_provisional_result("sector-bad-kind")
	_assert(result["validation_outcome"] == SectorBlueprintSchemaScript.OUTCOME_UNSUPPORTED_KIND, "ready result surfaces the unsupported-kind validation outcome")
	_assert(result["blueprint"] == null, "ready result carries no blueprint on validation failure")

	fake_server.stop()


func test_transport_failure_outcome_is_ready_with_structured_error() -> void:
	var fake_server: Node = FakeOllamaHttpServerScript.new()
	var port: int = fake_server.start()
	add_child_autofree(fake_server)
	fake_server.next_response_status = 500
	fake_server.next_response_body = "internal error"

	var generator: Node = _make_generator(port)
	generator.request_provisional_sector("sector-http-error", "generate a sector")
	await generator.provisional_sector_ready

	var result: Dictionary = generator.get_provisional_result("sector-http-error")
	_assert(result["request_outcome"] == SectorBlueprintServiceScript.REQUEST_OUTCOME_TRANSPORT_ERROR, "HTTP 500 reaches REQUEST_OUTCOME_TRANSPORT_ERROR")
	_assert(result["blueprint"] == null, "transport failure carries no blueprint")

	fake_server.stop()


func test_timeout_outcome_is_ready_within_bounded_window() -> void:
	var fake_server: Node = FakeOllamaHttpServerScript.new()
	var port: int = fake_server.start()
	add_child_autofree(fake_server)
	fake_server.respond_at_all = false

	var generator: Node = _make_generator(port)
	generator._blueprint_service.request_timeout_sec = 1.0
	var start_ticks: int = Time.get_ticks_msec()
	generator.request_provisional_sector("sector-timeout", "generate a sector")
	await generator.provisional_sector_ready
	var elapsed_ticks: int = Time.get_ticks_msec() - start_ticks

	var result: Dictionary = generator.get_provisional_result("sector-timeout")
	_assert(result["request_outcome"] == SectorBlueprintServiceScript.REQUEST_OUTCOME_TIMEOUT, "silent fake server reaches REQUEST_OUTCOME_TIMEOUT")
	_assert(elapsed_ticks < 5000, "timeout arrives within a bounded window")

	fake_server.stop()


func test_scene_tree_keeps_processing_frames_while_request_is_in_flight() -> void:
	var fake_server: Node = FakeOllamaHttpServerScript.new()
	var port: int = fake_server.start()
	add_child_autofree(fake_server)
	fake_server.respond_at_all = false

	var generator: Node = _make_generator(port)
	generator._blueprint_service.request_timeout_sec = 1.5
	generator.request_provisional_sector("sector-non-blocking", "generate a sector")

	_assert(generator.get_status("sector-non-blocking") == ProvisionalSectorGeneratorScript.STATUS_PENDING, "sector is still pending immediately after the call returns")

	var ticks_observed: int = 0
	while ticks_observed < 5:
		await wait_process_frames(1)
		ticks_observed += 1
	_assert(ticks_observed == 5, "SceneTree processes frames while the request is in flight")

	await generator.provisional_sector_ready
	_assert(generator.get_status("sector-non-blocking") == ProvisionalSectorGeneratorScript.STATUS_READY, "sector eventually resolves to ready")

	fake_server.stop()


func test_concurrent_requests_have_independent_correlation_and_state() -> void:
	var fake_server: Node = FakeOllamaHttpServerScript.new()
	var port: int = fake_server.start()
	add_child_autofree(fake_server)
	fake_server.next_response_status = 200
	fake_server.next_response_body = JSON.stringify({"response": FixturesScript.VALID})

	var generator: Node = _make_generator(port)
	var first_id: String = generator.request_provisional_sector("sector-a", "first request")
	var second_id: String = generator.request_provisional_sector("sector-b", "second request")

	_assert(first_id != second_id, "distinct sector ids receive distinct correlation ids")

	await generator.provisional_sector_ready
	await generator.provisional_sector_ready

	_assert(generator.get_status("sector-a") == ProvisionalSectorGeneratorScript.STATUS_READY, "sector-a resolves independently")
	_assert(generator.get_status("sector-b") == ProvisionalSectorGeneratorScript.STATUS_READY, "sector-b resolves independently")
	_assert(generator.get_provisional_result("sector-a")["correlation_id"] == first_id, "sector-a keeps its own correlation id")
	_assert(generator.get_provisional_result("sector-b")["correlation_id"] == second_id, "sector-b keeps its own correlation id")

	fake_server.stop()


func test_repeated_request_for_same_sector_id_does_not_restart() -> void:
	var fake_server: Node = FakeOllamaHttpServerScript.new()
	var port: int = fake_server.start()
	add_child_autofree(fake_server)
	fake_server.next_response_status = 200
	fake_server.next_response_body = JSON.stringify({"response": FixturesScript.VALID})

	var generator: Node = _make_generator(port)
	var first_id: String = generator.request_provisional_sector("sector-dup", "first prompt")
	var second_id: String = generator.request_provisional_sector("sector-dup", "second prompt")

	_assert(first_id == second_id, "a second request for the same sector id returns the existing correlation id instead of starting a new request")

	await generator.provisional_sector_ready
	fake_server.stop()


func test_result_state_is_in_memory_only_and_unknown_before_any_request() -> void:
	var generator: Node = ProvisionalSectorGeneratorScript.new()
	add_child_autofree(generator)

	_assert(generator.get_status("never-requested") == ProvisionalSectorGeneratorScript.STATUS_UNKNOWN, "a sector id with no request reports STATUS_UNKNOWN")
	_assert(generator.get_provisional_result("never-requested").is_empty(), "a sector id with no request has no provisional result")

	var db_files: PackedStringArray = DirAccess.get_files_at("res://")
	for file_name: String in db_files:
		_assert(not file_name.ends_with(".db") and not file_name.ends_with(".sqlite"), "no SQLite file appears at the project root from this seam")
