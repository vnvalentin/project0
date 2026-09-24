extends GutTest
## Headless public-seam test for Slice 008's async validated sector blueprint contract.
## The fake Ollama HTTP harness keeps all service outcomes deterministic.
## Run with the repository validation runner.

const SectorBlueprintSchemaScript: Script = preload("res://shared/sector_blueprint_schema.gd")
const SectorBlueprintServiceScript: Script = preload("res://server/sector_blueprint_service.gd")
const FixturesScript: Script = preload("res://scripts/sector_blueprint_fixtures.gd")
const FakeOllamaHttpServerScript: Script = preload("res://scripts/fake_ollama_http_server.gd")
const EXPECTED_FALLBACK: Dictionary = {
	"schema_version": 1,
	"sector_id": "sector-9-4",
	"origin": {"x": 0, "y": 0},
	"tiles": [{"x": 0, "y": 0, "kind": "floor"}],
}
const EXPERIMENT_TRACE_PATH: String = "res://build/validation/experiment-994-blueprint-schema-gate.json"


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

	var fractional_version: Dictionary = JSON.parse_string(FixturesScript.VALID)
	fractional_version["schema_version"] = 1.5
	var fractional_version_result: Dictionary = SectorBlueprintSchemaScript.validate(fractional_version)
	_assert(fractional_version_result["outcome"] != SectorBlueprintSchemaScript.OUTCOME_VALID, "literal schema rejects a fractional schema_version")

	var out_of_bounds_origin_result: Dictionary = SectorBlueprintSchemaScript.validate(JSON.parse_string(FixturesScript.OUT_OF_BOUNDS_ORIGIN))
	_assert(out_of_bounds_origin_result["outcome"] == SectorBlueprintSchemaScript.OUTCOME_OUT_OF_BOUNDS, "out-of-bounds origin validates as OUT_OF_BOUNDS")

	var out_of_bounds_tile_result: Dictionary = SectorBlueprintSchemaScript.validate(JSON.parse_string(FixturesScript.OUT_OF_BOUNDS_TILE))
	_assert(out_of_bounds_tile_result["outcome"] == SectorBlueprintSchemaScript.OUTCOME_OUT_OF_BOUNDS, "out-of-bounds tile validates as OUT_OF_BOUNDS")

	var non_object_result: Dictionary = SectorBlueprintSchemaScript.validate("just a string")
	_assert(non_object_result["outcome"] == SectorBlueprintSchemaScript.OUTCOME_MALFORMED_JSON, "a bare string validates as OUTCOME_MALFORMED_JSON")


func test_validator_accepts_representative_boundary_prompt_candidate() -> void:
	var candidate: Dictionary = JSON.parse_string(FixturesScript.VALID)
	candidate["schema_version"] = 3
	candidate["sector_id"] = "sector-3-2"
	var result: Dictionary = SectorBlueprintSchemaScript.validate_generated(candidate)
	_assert(result["outcome"] == SectorBlueprintSchemaScript.OUTCOME_VALID, "a candidate shaped like the boundary prompt's contract passes the unchanged validator")
	_assert(result["blueprint"]["sector_id"] == "sector-3-2", "the accepted blueprint retains the requested sector's own id")


func _make_service(fake_port: int) -> Node:
	var service: Node = SectorBlueprintServiceScript.new()
	service.ollama_host = "http://127.0.0.1:%d" % fake_port
	service.request_timeout_sec = 2.0
	add_child_autofree(service)
	return service


func test_experiment_994_schema_gate_and_fallback_trace() -> void:
	var fake_server: Node = FakeOllamaHttpServerScript.new()
	var port: int = fake_server.start()
	_assert(port > 0, "experiment harness starts and reports a listening port")
	add_child_autofree(fake_server)

	var service: Node = _make_service(port)
	var dispatched_results: Array[Dictionary] = []
	service.blueprint_request_completed.connect(func(_correlation_id: String, result: Dictionary) -> void:
		dispatched_results.append(result)
	)

	fake_server.next_response_body = JSON.stringify({"response": FixturesScript.VALID_WITH_STRUCTURE})
	var accepted: Dictionary = await service.request_sector_blueprint("accepted case", "sector-9-4")
	fake_server.next_response_body = JSON.stringify({"response": FixturesScript.UNSUPPORTED_KIND})
	var rejected: Dictionary = await service.request_sector_blueprint("invalid case", "sector-9-4")
	fake_server.respond_at_all = false
	service.request_timeout_sec = 1.0
	service._llm_client.request_timeout_sec = 1.0
	var timed_out: Dictionary = await service.request_sector_blueprint("timeout case", "sector-9-4")

	var cases: Array[Dictionary] = [
		_trace_case("accepted", accepted, _dispatch_count(dispatched_results, accepted["correlation_id"])),
		_trace_case("contract_invalid", rejected, _dispatch_count(dispatched_results, rejected["correlation_id"])),
		_trace_case("timeout", timed_out, _dispatch_count(dispatched_results, timed_out["correlation_id"])),
	]
	var experiment_checks: Dictionary = {
		"accepted_source": accepted["source"] == SectorBlueprintServiceScript.SOURCE_LLM,
		"accepted_without_fallback": accepted["fallback_selected"] == false,
		"accepted_guid": not accepted["blueprint"]["structures"][0]["entity_guid"].is_empty(),
		"invalid_schema_decision": rejected["validation_outcome"] == SectorBlueprintSchemaScript.OUTCOME_UNSUPPORTED_KIND,
		"invalid_fallback": rejected["source"] == SectorBlueprintServiceScript.SOURCE_FALLBACK and rejected["blueprint"] == EXPECTED_FALLBACK,
		"invalid_value_scrubbed": not rejected["detail"].contains("lava_pit"),
		"timeout_outcome": timed_out["request_outcome"] == SectorBlueprintServiceScript.REQUEST_OUTCOME_TIMEOUT,
		"deterministic_fallback": timed_out["blueprint"] == EXPECTED_FALLBACK and rejected["blueprint"] == timed_out["blueprint"],
	}
	for case: Dictionary in cases:
		experiment_checks["%s_single_dispatch" % case["case"]] = case["downstream_dispatch_count"] == 1
	var runtime_failures: Array[String] = []
	for check_name: String in experiment_checks:
		if not experiment_checks[check_name]:
			runtime_failures.append(check_name)
	var trace: Dictionary = {
		"experiment": 994,
		"completion_status": "passed" if runtime_failures.is_empty() else "failed",
		"runtime_failures": runtime_failures,
		"cases": cases,
	}
	var trace_file: FileAccess = FileAccess.open(EXPERIMENT_TRACE_PATH, FileAccess.WRITE)
	_assert(trace_file != null, "machine-readable experiment trace opens for writing")
	if trace_file != null:
		trace_file.store_string(JSON.stringify(trace, "\t"))
		trace_file.close()

	_assert(accepted["source"] == SectorBlueprintServiceScript.SOURCE_LLM, "accepted case forwards validated LLM data")
	_assert(accepted["fallback_selected"] == false, "accepted case does not select fallback")
	_assert(not accepted["blueprint"]["structures"][0]["entity_guid"].is_empty(), "accepted entity receives an RFC-v5 GUID")
	_assert(rejected["validation_outcome"] == SectorBlueprintSchemaScript.OUTCOME_UNSUPPORTED_KIND, "contract-invalid case records the schema decision")
	_assert(rejected["source"] == SectorBlueprintServiceScript.SOURCE_FALLBACK, "contract-invalid case selects fallback")
	_assert(rejected["blueprint"] == EXPECTED_FALLBACK, "contract-invalid raw data is not forwarded")
	_assert(not rejected["detail"].contains("lava_pit"), "contract-invalid model values are not echoed through the downstream seam")
	_assert(timed_out["request_outcome"] == SectorBlueprintServiceScript.REQUEST_OUTCOME_TIMEOUT, "timeout case records the bounded timeout")
	_assert(timed_out["blueprint"] == EXPECTED_FALLBACK, "timeout case selects the deterministic fallback")
	_assert(rejected["blueprint"] == timed_out["blueprint"], "invalid and timed-out requests produce identical fallback blueprints")
	for case: Dictionary in cases:
		_assert(case["downstream_dispatch_count"] == 1, "%s dispatches exactly once" % case["case"])

	service.queue_free()
	fake_server.stop()
	fake_server.queue_free()
	await wait_process_frames(1)


func _trace_case(case_name: String, result: Dictionary, downstream_dispatch_count: int) -> Dictionary:
	var guid_values: Array[String] = []
	for structure: Dictionary in result["blueprint"].get("structures", []):
		guid_values.append(structure.get("entity_guid", ""))
	for spawn_point: Dictionary in result["blueprint"].get("spawn_points", []):
		guid_values.append(spawn_point.get("entity_guid", ""))
	return {
		"case": case_name,
		"source": result["source"],
		"source_outcome": result["request_outcome"],
		"schema_decision": result["validation_outcome"],
		"guid_values": guid_values,
		"fallback_selected": result["fallback_selected"],
		"downstream_dispatch_count": downstream_dispatch_count,
		"completion_status": "completed",
		"runtime_failures": [],
	}


func _dispatch_count(dispatched_results: Array[Dictionary], correlation_id: String) -> int:
	var count: int = 0
	for result: Dictionary in dispatched_results:
		if result["correlation_id"] == correlation_id:
			count += 1
	return count


func test_service_valid_response_seam() -> void:
	var fake_server: Node = FakeOllamaHttpServerScript.new()
	var port: int = fake_server.start()
	_assert(port > 0, "fake Ollama HTTP harness starts and reports a listening port")
	add_child_autofree(fake_server)

	fake_server.next_response_status = 200
	fake_server.next_response_body = JSON.stringify({"response": FixturesScript.VALID_WITH_STRUCTURE})

	var service: Node = _make_service(port)
	var result: Dictionary = await service.request_sector_blueprint("generate a sector")

	_assert(result["request_outcome"] == SectorBlueprintServiceScript.REQUEST_OUTCOME_VALIDATED, "valid response reaches REQUEST_OUTCOME_VALIDATED")
	_assert(result["validation_outcome"] == SectorBlueprintSchemaScript.OUTCOME_VALID, "valid response validates as OUTCOME_VALID")
	_assert(result["source"] == SectorBlueprintServiceScript.SOURCE_LLM, "valid response preserves the accepted LLM source")
	assert_eq(result["blueprint"]["structures"][0]["entity_guid"], "fbc95d31-d969-5c26-94a8-feb468910fbc", "accepted structure receives the fixed RFC-v5 identifier")
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
	var result: Dictionary = await service.request_sector_blueprint("generate a sector", "sector-9-4")

	_assert(result["request_outcome"] == SectorBlueprintServiceScript.REQUEST_OUTCOME_TRANSPORT_ERROR, "malformed envelope reaches REQUEST_OUTCOME_TRANSPORT_ERROR")
	_assert(result["source"] == SectorBlueprintServiceScript.SOURCE_FALLBACK, "malformed envelope selects fallback")
	_assert(result["blueprint"] == EXPECTED_FALLBACK, "malformed raw data is replaced by the deterministic fallback")
	_assert(SectorBlueprintSchemaScript.validate(result["blueprint"])["outcome"] == SectorBlueprintSchemaScript.OUTCOME_VALID, "malformed fallback satisfies the literal schema contract")

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


func test_service_fallback_normalizes_empty_sector_id() -> void:
	var fake_server: Node = FakeOllamaHttpServerScript.new()
	var port: int = fake_server.start()
	add_child_autofree(fake_server)
	fake_server.next_response_status = 500
	fake_server.next_response_body = "internal error"

	var service: Node = _make_service(port)
	var result: Dictionary = await service.request_sector_blueprint("generate a sector", "")

	_assert(SectorBlueprintSchemaScript.validate(result["blueprint"])["outcome"] == SectorBlueprintSchemaScript.OUTCOME_VALID, "fallback remains schema-valid for an empty requested sector id")

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
	var result: Dictionary = await service.request_sector_blueprint("generate a sector", "sector-9-4")
	var elapsed_ticks: int = Time.get_ticks_msec() - start_ticks

	_assert(result["request_outcome"] == SectorBlueprintServiceScript.REQUEST_OUTCOME_TIMEOUT, "silent fake server reaches REQUEST_OUTCOME_TIMEOUT")
	_assert(result["source"] == SectorBlueprintServiceScript.SOURCE_FALLBACK, "timeout selects fallback")
	_assert(result["blueprint"] == EXPECTED_FALLBACK, "timeout selects the same deterministic fallback as malformed input")
	_assert(SectorBlueprintSchemaScript.validate(result["blueprint"])["outcome"] == SectorBlueprintSchemaScript.OUTCOME_VALID, "timeout fallback satisfies the literal schema contract")
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
