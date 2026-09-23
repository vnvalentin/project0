extends GutTest

const ServerMainScript: Script = preload("res://server/server_main.gd")
const SectorBoundaryDetectorScript: Script = preload("res://server/sector_boundary_detector.gd")
const JitTraceContextScript: Script = preload("res://shared/jit_trace_context.gd")


class FakeGenerator extends Node:
	var status: String = "unknown"
	var requests: Array[Dictionary] = []

	func get_status(_sector_id: String) -> String:
		return status

	func request_provisional_sector(sector_id: String, _prompt: String, trace: Dictionary) -> String:
		requests.append({"sector_id": sector_id, "trace": trace.duplicate(true)})
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
	server.free()