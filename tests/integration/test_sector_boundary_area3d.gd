extends GutTest
## Headless experiment for #991: authenticated authoritative movement crosses a
## real Area3D boundary and dispatches one non-blocking generation request.

const DetectorScript: Script = preload("res://server/sector_boundary_detector.gd")
const GeneratorScript: Script = preload("res://server/provisional_sector_generator.gd")
const PlayerStateScript: Script = preload("res://server/server_player_state.gd")
const SessionRegistryScript: Script = preload("res://server/session_registry.gd")
const LocomotionContractScript: Script = preload("res://shared/locomotion_contract.gd")
const FixturesScript: Script = preload("res://scripts/sector_blueprint_fixtures.gd")
const FakeOllamaHttpServerScript: Script = preload("res://scripts/fake_ollama_http_server.gd")

const PEER_ID: int = 41
const TARGET_SECTOR_ID: String = "sector-1-0"
const PHYSICS_DELTA: float = 1.0 / 60.0
const TRACE_PATH: String = "res://build/validation/issue-991-boundary-trace.json"


func test_authenticated_player_crosses_area_once_without_stopping() -> void:
	var sessions: SessionRegistry = SessionRegistryScript.new()
	sessions.bind(PEER_ID, "account-991", "boundary-runner")
	assert_true(sessions.is_authenticated(PEER_ID), "the experiment starts with an authenticated peer")

	var fake_server: Node = FakeOllamaHttpServerScript.new()
	add_child_autofree(fake_server)
	var fake_port: int = fake_server.start()
	assert_gt(fake_port, 0, "the deterministic generation fixture starts")
	fake_server.next_response_body = JSON.stringify({"response": FixturesScript.VALID})

	var generator: Node = GeneratorScript.new()
	generator.ollama_host = "http://127.0.0.1:%d" % fake_port
	generator.request_timeout_sec = 2.0
	add_child_autofree(generator)

	var detector: SectorBoundaryDetector = DetectorScript.new()
	detector.set_canon_lookup(func(_sector_id: String) -> Dictionary:
		return {"outcome": "not_found"}
	)

	var trigger_events: Array[Dictionary] = []
	var request_events: Array[Dictionary] = []
	detector.sector_generation_requested.connect(func(peer_id: int, sector_id: String, position: Vector3) -> void:
		trigger_events.append({
			"name": "SECTOR_BOUNDARY_TRIGGERED",
			"peer_id": peer_id,
			"sector_id": sector_id,
			"position": _vector_trace(position),
		})
	)
	detector.set_request_callback(func(peer_id: int, sector_id: String, position: Vector3) -> void:
		var prompt: String = "Generate the validated sector blueprint for %s near world position (%0.2f, %0.2f)." % [sector_id, position.x, position.z]
		var correlation_id: String = generator.request_provisional_sector(sector_id, prompt)
		request_events.append({
			"peer_id": peer_id,
			"sector_id": sector_id,
			"correlation_id": correlation_id,
			"status_at_dispatch": generator.get_status(sector_id),
		})
	)

	var boundary: Area3D = Area3D.new()
	boundary.name = "UnmappedSectorBoundary"
	boundary.position = Vector3(440.15, 0.0, 0.0)
	boundary.collision_layer = 0
	boundary.collision_mask = 1
	var boundary_shape: CollisionShape3D = CollisionShape3D.new()
	var boundary_box: BoxShape3D = BoxShape3D.new()
	boundary_box.size = Vector3(0.2, 4.0, 8.0)
	boundary_shape.shape = boundary_box
	boundary.add_child(boundary_shape)
	add_child_autofree(boundary)

	var player_body: CharacterBody3D = CharacterBody3D.new()
	player_body.name = "AuthenticatedServerPlayer"
	player_body.collision_layer = 1
	player_body.collision_mask = 0
	var player_shape: CollisionShape3D = CollisionShape3D.new()
	var player_box: BoxShape3D = BoxShape3D.new()
	player_box.size = Vector3(0.1, 1.8, 0.1)
	player_shape.shape = player_box
	player_body.add_child(player_shape)
	add_child_autofree(player_body)

	var player_state: Node = PlayerStateScript.new()
	add_child_autofree(player_state)
	player_state.start_for_peer(PEER_ID, Vector3(439.0, 0.0, 0.0))
	player_state.set_physics_process(false)
	player_state.apply_input_intent(
		PEER_ID,
		LocomotionContractScript.make_intent(Vector2.RIGHT, LocomotionContractScript.MODE_NONE),
		1
	)
	player_body.position = player_state.position

	var intersection: Dictionary = {
		"timestamp_usec": 0,
		"position": Vector3.ZERO,
	}
	boundary.body_entered.connect(func(body: Node3D) -> void:
		if body != player_body or not sessions.is_authenticated(PEER_ID):
			return
		intersection["timestamp_usec"] = Time.get_ticks_usec()
		intersection["position"] = player_state.position
		detector.observe_position(PEER_ID, player_state.position)
	)

	await wait_physics_frames(2)
	for _tick: int in 30:
		player_state._physics_process(PHYSICS_DELTA)
		player_body.position = player_state.position
		await wait_physics_frames(1)
		if not trigger_events.is_empty():
			break

	assert_eq(trigger_events.size(), 1, "one physical boundary intersection emits one structured trigger")
	assert_eq(request_events.size(), 1, "one physical boundary intersection accepts one async request")
	assert_eq(trigger_events[0]["sector_id"], TARGET_SECTOR_ID, "the crossing targets the unmapped adjacent sector")
	assert_eq(request_events[0]["status_at_dispatch"], GeneratorScript.STATUS_PENDING, "generation is pending when the callback returns")

	var continuation_start: Vector3 = player_state.position
	for _tick: int in 12:
		player_state._physics_process(PHYSICS_DELTA)
		player_body.position = player_state.position
		await wait_physics_frames(1)
	var continuation_distance: float = player_state.position.distance_to(continuation_start)

	assert_gt(continuation_distance, 0.5, "authoritative movement continues while generation is asynchronous")
	assert_eq(trigger_events.size(), 1, "continued movement emits no duplicate boundary trigger")
	assert_eq(request_events.size(), 1, "continued movement dispatches no duplicate request")

	for _tick: int in 120:
		if generator.get_status(TARGET_SECTOR_ID) == GeneratorScript.STATUS_READY:
			break
		await wait_process_frames(1)
	assert_eq(generator.get_status(TARGET_SECTOR_ID), GeneratorScript.STATUS_READY, "the deferred HTTP request completes without blocking movement")

	var trace: Dictionary = {
		"experiment": 991,
		"peer_id": PEER_ID,
		"authenticated": sessions.is_authenticated(PEER_ID),
		"movement_vector": _vector_trace(Vector3.RIGHT),
		"boundary_intersection_timestamp_usec": intersection["timestamp_usec"],
		"position_at_intersection": _vector_trace(intersection["position"]),
		"trigger": trigger_events[0],
		"outbound_request": request_events[0],
		"trigger_count": trigger_events.size(),
		"async_request_count": request_events.size(),
		"continued_movement_distance": continuation_distance,
		"request_final_status": generator.get_status(TARGET_SECTOR_ID),
		"request_completion_timestamp_usec": Time.get_ticks_usec(),
		"runtime_failures": 0,
	}
	var trace_json: String = JSON.stringify(trace, "\t")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TRACE_PATH.get_base_dir()))
	var trace_file: FileAccess = FileAccess.open(TRACE_PATH, FileAccess.WRITE)
	assert_not_null(trace_file, "the complete structured trace artifact can be opened")
	trace_file.store_string(trace_json)
	trace_file.close()
	print("ISSUE_991_TRACE_PATH %s" % TRACE_PATH)

	fake_server.stop()


func _vector_trace(value: Vector3) -> Dictionary:
	return {"x": value.x, "y": value.y, "z": value.z}