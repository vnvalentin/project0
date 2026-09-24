extends GutTest

const ServerMainScript: Script = preload("res://server/server_main.gd")
const SectorBoundaryDetectorScript: Script = preload("res://server/sector_boundary_detector.gd")
const JitTraceContextScript: Script = preload("res://shared/jit_trace_context.gd")
const SectorBlueprintSchemaScript: Script = preload("res://shared/sector_blueprint_schema.gd")


class FakeGenerator extends Node:
	var status: String = "unknown"
	var requests: Array[Dictionary] = []

	func get_status(_sector_id: String) -> String:
		return status

	func request_provisional_sector(sector_id: String, prompt: String, selected_profile: String, trace: Dictionary) -> String:
		requests.append({
			"sector_id": sector_id,
			"prompt": prompt,
			"selected_profile": selected_profile,
			"trace": trace.duplicate(true),
		})
		status = "pending"
		return "correlation-%d" % requests.size()


class FakeCanonRepository extends RefCounted:
	var blueprint: Dictionary = {}

	func get_canonical_sector(_sector_id: String) -> Dictionary:
		return {"outcome": "ok", "sector": {"blueprint": blueprint}}


class FakeTelemetrySink extends RefCounted:
	var envelopes: Array[Dictionary] = []

	func emit(envelope: Dictionary) -> Dictionary:
		envelopes.append(envelope)
		return {"outcome": "ok"}


func test_first_peer_remains_generation_owner_for_duplicate_sector_request() -> void:
	var server: SceneTree = ServerMainScript.new()
	var generator: FakeGenerator = FakeGenerator.new()
	server._provisional_sector_generator = generator
	var first_trace: Dictionary = JitTraceContextScript.root(7, "sector-1-0")
	var second_trace: Dictionary = JitTraceContextScript.root(8, "sector-1-0")

	server._request_sector_from_boundary(7, "sector-1-0", Vector3(440.0, 0.0, 0.0), first_trace)
	server._request_sector_from_boundary(8, "sector-1-0", Vector3(441.0, 0.0, 0.0), second_trace)

	assert_eq(server._jit_peer_by_sector["sector-1-0"], 7)
	assert_eq(generator.requests.size(), 2)
	assert_eq(generator.requests[1]["trace"]["trace_id"], first_trace["trace_id"], "the generator retains its first trace")
	generator.free()
	server.free()


func test_presentation_context_is_retained_before_telemetry_persistence() -> void:
	var server: SceneTree = ServerMainScript.new()
	var network_client: Node = Node.new()
	network_client.name = "NetworkClient"
	server.root.add_child(network_client)
	var detector: SectorBoundaryDetector = SectorBoundaryDetectorScript.new()
	server._sector_boundary_detector = detector
	server._jit_peer_by_sector["sector-1-0"] = 7
	server._jit_commit_trace_by_sector["sector-1-0"] = JitTraceContextScript.child(
		JitTraceContextScript.root(7, "sector-1-0"),
		"canon_db_commit",
	)

	server._on_canonical_sector_ready("sector-1-0", {})

	assert_true(detector._trace_by_sector.has("sector-1-0"), "send-time server context survives telemetry outage")
	assert_eq(
		detector._trace_by_sector["sector-1-0"]["event_type"],
		"client_presentation_ack",
		"the retained parent is the server-issued presentation span",
	)
	network_client.free()
	server.free()


func test_canon_reentry_is_emitted_by_server_before_client_presentation() -> void:
	var server: SceneTree = ServerMainScript.new()
	var repository: FakeCanonRepository = FakeCanonRepository.new()
	repository.blueprint = {"sector_id": "sector-1-0"}
	var sink: FakeTelemetrySink = FakeTelemetrySink.new()
	server._canon_repository = repository
	server._telemetry_sink = sink
	var reentry_trace: Dictionary = JitTraceContextScript.child(
		JitTraceContextScript.root(7, "sector-1-0"),
		"canon_reentry",
	)

	server._reload_sector_from_boundary(7, "sector-1-0", Vector3.ZERO, reentry_trace)

	assert_eq(sink.envelopes.size(), 1)
	assert_eq(sink.envelopes[0]["event_type"], "canon_reentry")
	assert_eq(sink.envelopes[0]["payload"]["span_id"], reentry_trace["span_id"])


func test_boundary_prompt_carries_schema_contract_for_the_requested_sector() -> void:
	var server: SceneTree = ServerMainScript.new()
	var generator: FakeGenerator = FakeGenerator.new()
	server._provisional_sector_generator = generator

	server._request_sector_from_boundary(7, "sector-3-2", Vector3(1320.0, 0.0, 880.0), JitTraceContextScript.root(7, "sector-3-2"))

	assert_eq(generator.requests.size(), 1)
	var prompt: String = generator.requests[0]["prompt"]
	assert_true(prompt.contains("\"sector_id\": \"sector-3-2\""), "prompt states the authoritative, request-specific sector_id")
	assert_true(prompt.contains("\"schema_version\": 3"), "prompt states the supported schema version")
	assert_true(prompt.contains("\"origin\": {\"x\": 0, \"y\": 0}"), "prompt states the fixed sector-local origin so a candidate cannot claim a mismatched origin")
	assert_true(prompt.contains("\"tiles\": 1..%d" % SectorBlueprintSchemaScript.MAX_TILE_COUNT), "prompt states the non-empty bounded tiles field")
	assert_true(prompt.contains("{\"x\": int, \"y\": int, \"kind\": string}"), "prompt states each tile's required fields")
	for kind: String in SectorBlueprintSchemaScript.SUPPORTED_TILE_KINDS:
		assert_true(prompt.contains(kind), "prompt allows tile kind '%s'" % kind)
	var bound: String = str(SectorBlueprintSchemaScript.MAX_COORDINATE_ABS)
	assert_true(prompt.contains("-%s..%s" % [bound, bound]), "prompt states the coordinate bound of %s" % bound)
	assert_true(prompt.contains("Return ONLY one JSON object"), "prompt excludes prose and thinking from the response")
	assert_true(prompt.contains("Output valid JSON only."), "prompt constrains the model to valid JSON-only output")

	server._request_sector_from_boundary(9, "sector-5-1", Vector3(2200.0, 0.0, 440.0), JitTraceContextScript.root(9, "sector-5-1"))
	assert_true(generator.requests[1]["prompt"].contains("\"sector_id\": \"sector-5-1\""), "a different boundary crossing embeds its own authoritative sector_id, not the earlier request's")
	assert_false(generator.requests[1]["prompt"].contains("sector-3-2"), "a different boundary crossing does not leak the earlier request's sector_id")

	generator.free()
	server.free()