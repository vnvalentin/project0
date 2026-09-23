extends GutTest
## Public-seam tests for Slice 046's authoritative sector transition detector.

const DetectorScript: Script = preload("res://server/sector_boundary_detector.gd")


func test_sector_mapping_uses_floor_for_negative_coordinates() -> void:
	assert_eq(DetectorScript.sector_id_for_position(Vector3(0.0, 99.0, 0.0)), "sector-0-0")
	assert_eq(DetectorScript.sector_id_for_position(Vector3(439.9, 0.0, -0.1)), "sector-0--1")
	assert_eq(DetectorScript.sector_id_for_position(Vector3(-0.1, 0.0, -440.0)), "sector--1--1")
	assert_eq(DetectorScript.sector_id_for_position(Vector3(440.0, 0.0, 440.0)), "sector-1-1")


func test_each_peer_requests_once_per_unseen_sector() -> void:
	var detector: SectorBoundaryDetector = DetectorScript.new()
	var requests: Array = []
	detector.set_request_callback(func(peer_id: int, sector_id: String, position: Vector3) -> void:
		requests.append([peer_id, sector_id])
	)

	var first: Dictionary = detector.observe_position(7, Vector3.ZERO)
	var same: Dictionary = detector.observe_position(7, Vector3(1.0, 0.0, 1.0))
	var next: Dictionary = detector.observe_position(7, Vector3(440.0, 0.0, 0.0))
	assert_true(first["requested"])
	assert_false(same["requested"])
	assert_true(next["requested"])
	assert_eq(requests.size(), 2)
	assert_eq(requests[0][0], 7)
	assert_eq(requests[1][1], "sector-1-0")


func test_peers_have_independent_transition_state() -> void:
	var detector: SectorBoundaryDetector = DetectorScript.new()
	var requests: Array = []
	detector.set_request_callback(func(peer_id: int, sector_id: String, position: Vector3) -> void:
		requests.append(peer_id)
	)
	detector.observe_position(1, Vector3.ZERO)
	detector.observe_position(2, Vector3.ZERO)
	assert_eq(requests, [1, 2])


func test_canonical_sector_suppresses_generation() -> void:
	var detector: SectorBoundaryDetector = DetectorScript.new()
	var requests: Array = []
	var reloads: Array = []
	detector.set_canon_lookup(func(sector_id: String) -> Dictionary:
		return {"outcome": "ok"} if sector_id == "sector-0-0" else {"outcome": "not_found"}
	)
	detector.set_request_callback(func(peer_id: int, sector_id: String, position: Vector3) -> void:
		requests.append(sector_id)
	)
	detector.set_reload_callback(func(peer_id: int, sector_id: String, position: Vector3) -> void:
		reloads.append([peer_id, sector_id, position])
	)
	var result: Dictionary = detector.observe_position(1, Vector3.ZERO)
	assert_false(result["requested"])
	assert_eq(requests.size(), 0)
	assert_true(result["reloaded"])
	assert_eq(reloads, [[1, "sector-0-0", Vector3.ZERO]])


func test_forget_peer_allows_reassessment_after_disconnect() -> void:
	var detector: SectorBoundaryDetector = DetectorScript.new()
	var requests: Array = []
	detector.set_request_callback(func(peer_id: int, sector_id: String, position: Vector3) -> void:
		requests.append(sector_id)
	)
	detector.observe_position(4, Vector3.ZERO)
	detector.forget_peer(4)
	var result: Dictionary = detector.observe_position(4, Vector3.ZERO)
	assert_true(result["requested"])
	assert_eq(requests.size(), 2)


func test_reentry_continues_the_original_generation_trace() -> void:
	var detector: SectorBoundaryDetector = DetectorScript.new()
	var canonical_sectors: Dictionary = {}
	var generation_traces: Array[Dictionary] = []
	var reload_traces: Array[Dictionary] = []
	detector.set_canon_lookup(func(sector_id: String) -> Dictionary:
		return {"outcome": "ok"} if canonical_sectors.has(sector_id) else {"outcome": "not_found"}
	)
	detector.set_request_callback(func(_peer_id: int, _sector_id: String, _position: Vector3, trace: Dictionary) -> void:
		generation_traces.append(trace)
	)
	detector.set_reload_callback(func(_peer_id: int, _sector_id: String, _position: Vector3, trace: Dictionary) -> void:
		reload_traces.append(trace)
	)

	detector.observe_position(7, Vector3(440.0, 0.0, 0.0))
	assert_eq(generation_traces.size(), 1, "the initial boundary crossing creates one root trace")
	var root_trace: Dictionary = generation_traces[0]
	assert_ne(root_trace.get("trace_id", ""), "")
	assert_ne(root_trace.get("span_id", ""), "")
	assert_ne(root_trace.get("spatial_guid", ""), "", "the root carries the stable sector spatial GUID")
	assert_eq(root_trace.get("parent_span_id"), null)
	assert_eq(root_trace.get("event_type"), "player_trigger_event")

	var presentation_trace: Dictionary = root_trace.duplicate(true)
	presentation_trace["parent_span_id"] = root_trace["span_id"]
	presentation_trace["span_id"] = "presentation-span"
	presentation_trace["event_type"] = "client_presentation_ack"
	detector.remember_canon_trace("sector-1-0", presentation_trace)
	canonical_sectors["sector-1-0"] = true

	detector.observe_position(7, Vector3.ZERO)
	detector.observe_position(7, Vector3(440.0, 0.0, 0.0))
	assert_eq(generation_traces.size(), 2, "entering another unexplored sector is the only new generation")
	assert_eq(reload_traces.size(), 1, "returning to Canon emits one re-entry span")
	var reentry_trace: Dictionary = reload_traces[0]
	assert_eq(reentry_trace.get("trace_id"), root_trace["trace_id"])
	assert_eq(reentry_trace.get("parent_span_id"), presentation_trace["span_id"])
	assert_ne(reentry_trace.get("span_id", ""), presentation_trace["span_id"])
	assert_eq(reentry_trace.get("event_type"), "canon_reentry")


func test_retained_canon_traces_are_bounded() -> void:
	var detector: SectorBoundaryDetector = DetectorScript.new()
	for index: int in range(DetectorScript.MAX_RETAINED_CANON_TRACES + 1):
		detector.remember_canon_trace("sector-%d-0" % index, {
			"trace_id": "trace-%d" % index,
			"span_id": "span-%d" % index,
		})
	assert_eq(detector._trace_by_sector.size(), DetectorScript.MAX_RETAINED_CANON_TRACES)
	assert_false(detector._trace_by_sector.has("sector-0-0"), "the oldest retained context is evicted")