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
	detector.set_canon_lookup(func(sector_id: String) -> Dictionary:
		return {"outcome": "ok"} if sector_id == "sector-0-0" else {"outcome": "not_found"}
	)
	detector.set_request_callback(func(peer_id: int, sector_id: String, position: Vector3) -> void:
		requests.append(sector_id)
	)
	var result: Dictionary = detector.observe_position(1, Vector3.ZERO)
	assert_false(result["requested"])
	assert_eq(requests.size(), 0)


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