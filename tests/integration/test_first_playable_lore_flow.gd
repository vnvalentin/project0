extends GutTest
## Headless experiment for #571: an authenticated physical boundary crossing
## presents one server-accepted narrative while movement continues.

const DetectorScript: Script = preload("res://server/sector_boundary_detector.gd")
const PlayerStateScript: Script = preload("res://server/server_player_state.gd")
const SessionRegistryScript: Script = preload("res://server/session_registry.gd")
const ValidatorScript: Script = preload("res://server/world_directive_validator.gd")
const LocomotionContractScript: Script = preload("res://shared/locomotion_contract.gd")

const PEER_ID: int = 57
const TARGET_SECTOR_ID: String = "sector-1-0"
const APPROVED_NARRATIVE: String = "A moss-covered road follows the ridge."
const PHYSICS_DELTA: float = 1.0 / 60.0
const TRACE_PATH: String = "res://build/validation/issue-571-lore-flow-trace.json"


func test_authenticated_boundary_crossing_presents_only_accepted_lore() -> void:
	var sessions: SessionRegistry = SessionRegistryScript.new()
	sessions.bind(PEER_ID, "account-571", "lore-runner")
	assert_true(sessions.is_authenticated(PEER_ID), "the experiment starts with an authenticated peer")

	var accepted_label: Label = Label.new()
	accepted_label.visible = false
	add_child_autofree(accepted_label)
	var rejected_label: Label = Label.new()
	rejected_label.visible = false
	add_child_autofree(rejected_label)

	var accepted_presentations: Array[Dictionary] = []
	var rejected_presentations: Array[Dictionary] = []
	var fallback_directive: Dictionary = _valid_directive("directive-fallback", "Fallback text must remain hidden.")
	var rejected_proposal: Dictionary = _valid_directive("directive-rejected", "Rejected text must remain hidden.")
	rejected_proposal["biome"] = "volcanic"
	var rejected_result: Dictionary = _present_if_accepted(
		rejected_proposal,
		fallback_directive,
		rejected_label,
		rejected_presentations
	)
	assert_ne(rejected_result["outcome"], ValidatorScript.OUTCOME_ACCEPTED, "unsupported vocabulary is not accepted")
	assert_eq(rejected_presentations.size(), 0, "a non-accepted directive emits no presentation event")
	assert_false(rejected_label.visible, "a non-accepted directive leaves the client label hidden")
	assert_eq(rejected_label.text, "", "neither rejected nor fallback narrative reaches the client label")

	var detector: SectorBoundaryDetector = DetectorScript.new()
	detector.set_canon_lookup(func(_sector_id: String) -> Dictionary:
		return {"outcome": "not_found"}
	)
	var boundary_events: Array[Dictionary] = []
	var accepted_results: Array[Dictionary] = []
	detector.sector_generation_requested.connect(func(peer_id: int, sector_id: String, position: Vector3) -> void:
		boundary_events.append({
			"peer_id": peer_id,
			"sector_id": sector_id,
			"position": _vector_trace(position),
		})
	)
	detector.set_request_callback(func(_peer_id: int, _sector_id: String, _position: Vector3) -> void:
		accepted_results.append(_present_if_accepted(
			_valid_directive("directive-571", APPROVED_NARRATIVE),
			fallback_directive,
			accepted_label,
			accepted_presentations
		))
	)

	var boundary: Area3D = Area3D.new()
	boundary.name = "LoreSectorBoundary"
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
	player_body.name = "AuthenticatedLorePlayer"
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
	var network_client: Node = get_tree().root.get_node_or_null("NetworkClient")
	if network_client != null:
		network_client.name = "NetworkClientDisabledForIssue571"

	boundary.body_entered.connect(func(body: Node3D) -> void:
		if body != player_body or not sessions.is_authenticated(PEER_ID):
			return
		detector.observe_position(PEER_ID, player_state.position)
	)

	await wait_physics_frames(2)
	for _tick: int in 30:
		player_state._physics_process(PHYSICS_DELTA)
		player_body.position = player_state.position
		await wait_physics_frames(1)
		if not accepted_presentations.is_empty():
			break

	var accepted_result: Dictionary = accepted_results[0] if not accepted_results.is_empty() else {}
	assert_eq(boundary_events.size(), 1, "one physical boundary crossing emits one server event")
	assert_eq(boundary_events[0]["sector_id"], TARGET_SECTOR_ID, "the player crosses into the adjacent sector")
	assert_eq(accepted_result.get("outcome", ""), ValidatorScript.OUTCOME_ACCEPTED, "the fixed World Directive passes server validation")
	assert_eq(accepted_presentations.size(), 1, "accepted narrative is presented exactly once")
	assert_true(accepted_label.visible, "the accepted client label becomes visible")
	assert_eq(accepted_label.text, APPROVED_NARRATIVE, "the label displays the normalized accepted narrative")

	var continuation_start: Vector3 = player_state.position
	for _tick: int in 12:
		player_state._physics_process(PHYSICS_DELTA)
		player_body.position = player_state.position
		await wait_physics_frames(1)
	var continuation_distance: float = player_state.position.distance_to(continuation_start)
	if network_client != null:
		network_client.name = "NetworkClient"

	assert_gt(continuation_distance, 0.5, "authoritative movement continues after narrative presentation")
	assert_eq(boundary_events.size(), 1, "continued movement emits no duplicate boundary event")
	assert_eq(accepted_presentations.size(), 1, "continued movement emits no duplicate narrative")

	var trace: Dictionary = {
		"experiment": 571,
		"peer_id": PEER_ID,
		"authenticated": sessions.is_authenticated(PEER_ID),
		"boundary_count": boundary_events.size(),
		"boundary_event": boundary_events[0],
		"accepted_proposal": _valid_directive("directive-571", APPROVED_NARRATIVE),
		"accepted_validator_outcome": accepted_result.get("outcome", ""),
		"normalized_narrative": accepted_result.get("directive", {}).get("narrative", ""),
		"accepted_presentation_count": accepted_presentations.size(),
		"accepted_label_visible": accepted_label.visible,
		"accepted_label_text": accepted_label.text,
		"rejected_validator_outcome": rejected_result.get("outcome", ""),
		"rejected_presentation_count": rejected_presentations.size(),
		"rejected_label_visible": rejected_label.visible,
		"rejected_label_text": rejected_label.text,
		"continued_movement_distance": continuation_distance,
		"runtime_failures": 0,
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TRACE_PATH.get_base_dir()))
	var trace_file: FileAccess = FileAccess.open(TRACE_PATH, FileAccess.WRITE)
	assert_not_null(trace_file, "the structured Lore-flow trace can be opened")
	trace_file.store_string(JSON.stringify(trace, "\t"))
	trace_file.close()
	print("ISSUE_571_TRACE_PATH %s" % TRACE_PATH)


func _present_if_accepted(
	proposal: Dictionary,
	fallback: Dictionary,
	label: Label,
	presentations: Array[Dictionary]
) -> Dictionary:
	var result: Dictionary = ValidatorScript.validate(proposal, fallback)
	if result.get("outcome", "") != ValidatorScript.OUTCOME_ACCEPTED:
		return result
	var narrative: String = result["directive"]["narrative"]
	label.text = narrative
	label.visible = true
	presentations.append({"narrative": narrative})
	return result


func _valid_directive(directive_id: String, narrative: String) -> Dictionary:
	return {
		"schema_version": 1,
		"directive_id": directive_id,
		"directive_revision": 1,
		"builder_version": "builder-571",
		"tuning_version": "tuning-571",
		"resource_set_version": "resources-571",
		"biome": "forest",
		"theme": "ancient",
		"palette_tags": ["verdant", "stone"],
		"atmosphere_tags": ["mist"],
		"density_band": 2,
		"threat_band": 1,
		"poi_requirements": [{"poi_id": "ridge-road", "predicate": "VALLEY"}],
		"narrative": narrative,
		"context_refs": [TARGET_SECTOR_ID],
	}


func _vector_trace(value: Vector3) -> Dictionary:
	return {"x": value.x, "y": value.y, "z": value.z}