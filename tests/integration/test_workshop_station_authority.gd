extends GutTest
## #951 public authority adapter seam with real admission and native physics.

const SessionsScript: Script = preload("res://server/session_registry.gd")
const CharactersScript: Script = preload("res://server/character_service.gd")
const GatewayScript: Script = preload("res://server/login_gateway.gd")
const AdmittedScript: Script = preload("res://server/admitted_player_state.gd")
const PEER_ID: int = 951

var _sessions: SessionRegistry
var _gateway: Node
var _state: Node
var _network_client: Node


func before_each() -> void:
	assert_null(get_tree().root.get_node_or_null("LoginGateway"))
	_network_client = get_tree().root.get_node("NetworkClient")
	get_tree().root.remove_child(_network_client)
	_sessions = SessionsScript.new()
	var characters: Node = CharactersScript.new(null, _sessions)
	add_child_autofree(characters)
	_gateway = GatewayScript.new(null, characters, _sessions)
	_gateway.name = "LoginGateway"
	get_tree().root.add_child(_gateway)
	_state = AdmittedScript.new()
	add_child_autofree(_state)
	_state.start_for_peer(PEER_ID, Vector3.ZERO)
	_state.set_physics_process(false)
	_sessions.bind(PEER_ID, "fixture-account-951", "fixture-player-951")
	_sessions.set_selected_character_snapshot(PEER_ID, "fixture-character-951", "Fixture", {})
	_state.bind_character("fixture-character-951", "Fixture", {})


func after_each() -> void:
	_gateway.free()
	get_tree().root.add_child(_network_client)


func test_real_station_volume_accepts_only_current_admitted_character() -> void:
	for path: String in ["res://server/workshop_station_contract.gd", "res://server/workshop_character_sensor.gd", "res://server/workshop_station_volume.gd"]:
		assert_true(ResourceLoader.exists(path), "The public station authority component must exist: " + path)
		if not ResourceLoader.exists(path):
			return
	var contract: Script = load("res://server/workshop_station_contract.gd")
	var sensor_script: Script = load("res://server/workshop_character_sensor.gd")
	var volume_script: Script = load("res://server/workshop_station_volume.gd")
	var parsed: Dictionary = contract.parse_server_descriptor(_descriptor())
	assert_eq(parsed["outcome"], "ok")
	if parsed["outcome"] != "ok":
		return
	var sensor: CharacterBody3D = sensor_script.new()
	add_child_autofree(sensor)
	assert_eq(sensor.bind_admitted_player(_state)["outcome"], "ok")
	var area: Area3D = volume_script.new(parsed["station"])
	add_child_autofree(area)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_true(area.overlaps_body(sensor), "Native Area3D sees the actual CharacterBody3D")
	var admission: Dictionary = area.validate_character(sensor)
	assert_eq(admission["outcome"], "ok")
	assert_eq(admission.get("character_id"), "fixture-character-951")


func _descriptor() -> Dictionary:
	return {
		"schema_version": 1, "station_id": "fixture-station-951",
		"interior_id": "fixture-interior-951", "anchor_revision": 1,
		"bounds_min": [-2, -1, -2], "bounds_max": [2, 3, 2],
		"active": true, "revision": 1,
	}


func test_admitted_identity_rejects_old_node_after_same_character_session_replacement() -> void:
	assert_true(_state.has_method("current_admitted_identity"), "Admission owner must expose its current bound identity")
	if not _state.has_method("current_admitted_identity"):
		return
	var initial: Dictionary = _state.current_admitted_identity()
	assert_eq(initial["outcome"], "ok")
	_sessions.clear(PEER_ID)
	_sessions.bind(PEER_ID, "fixture-account-951", "fixture-player-951")
	_sessions.set_selected_character_snapshot(PEER_ID, "fixture-character-951", "Fixture", {})
	assert_eq(_state.current_admitted_identity()["outcome"], "not_admitted", "Same Character cannot revive an old world-bound epoch")
	_state.bind_character("fixture-character-951", "Fixture", {})
	var rebound: Dictionary = _state.current_admitted_identity()
	assert_eq(rebound["outcome"], "ok")
	assert_ne(rebound["session_epoch"], initial["session_epoch"])


func test_fresh_center_rejects_cached_overlap_and_waits_for_settled_move_in() -> void:
	var sensor: CharacterBody3D = _sensor()
	var area: Area3D = _volume(_descriptor())
	await _settle_physics()
	assert_eq(area.validate_character(sensor)["outcome"], "ok")
	_state.position = Vector3(8, 0, 0) # Owned server-pose fixture, no client input.
	assert_true(area.overlaps_body(sensor), "Native overlap cache still describes the previous physics step")
	assert_eq(area.validate_character(sensor)["outcome"], "outside_station")
	_state.position = Vector3.ZERO
	assert_eq(area.validate_character(sensor)["outcome"], "physics_not_settled", "A cached overlap cannot qualify the newly mirrored pose")
	await _settle_physics()
	assert_eq(area.validate_character(sensor)["outcome"], "ok")
	_state.position = Vector3(2, 0, 0)
	assert_eq(area.validate_character(sensor)["outcome"], "outside_station", "Upper bound is exclusive even while the sensor shape overlaps")
	_state.position = Vector3(-2, 0, 0)
	sensor.current_actor()
	await _settle_physics()
	assert_eq(area.validate_character(sensor)["outcome"], "ok", "Lower bound includes the authoritative center")


func test_existing_sensor_is_invalidated_by_same_character_session_replacement() -> void:
	var sensor: CharacterBody3D = _sensor()
	var area: Area3D = _volume(_descriptor())
	await _settle_physics()
	_sessions.clear(PEER_ID)
	_sessions.bind(PEER_ID, "fixture-account-951", "fixture-player-951")
	_sessions.set_selected_character_snapshot(PEER_ID, "fixture-character-951", "Fixture", {})
	_state.bind_character("fixture-character-951", "Fixture", {})
	assert_eq(area.validate_character(sensor)["outcome"], "not_admitted", "A rebound source must not revive the old sensor")
	assert_true(sensor.is_queued_for_deletion())
	var replacement: CharacterBody3D = _sensor()
	await _settle_physics()
	assert_eq(area.validate_character(replacement)["outcome"], "ok")


func test_inactive_transformed_and_foreign_bindings_fail_closed() -> void:
	var sensor: CharacterBody3D = _sensor()
	var area: Area3D = _volume(_descriptor())
	var inactive: Dictionary = _descriptor()
	inactive["active"] = false
	var inactive_area: Area3D = _volume(inactive)
	var foreign: CharacterBody3D = CharacterBody3D.new()
	add_child_autofree(foreign)
	await _settle_physics()
	assert_eq(area.validate_character(foreign)["outcome"], "invalid_character_binding")
	assert_eq(inactive_area.validate_character(sensor)["outcome"], "inactive_station")
	area.rotation.y = 0.01
	assert_eq(area.validate_character(sensor)["outcome"], "invalid_station_binding")
	area.rotation = Vector3.ZERO
	var shape: CollisionShape3D = area.get_child(0)
	shape.position.x = 0.01
	assert_eq(area.validate_character(sensor)["outcome"], "invalid_station_binding")
	shape.position = Vector3.ZERO
	shape.disabled = true
	assert_eq(area.validate_character(sensor)["outcome"], "invalid_station_binding")
	shape.disabled = false
	sensor.scale = Vector3(2, 1, 1)
	assert_eq(area.validate_character(sensor)["outcome"], "invalid_character_binding")


func test_source_exit_tears_down_sensor_and_missing_gateway_rejects() -> void:
	var sensor: CharacterBody3D = _sensor()
	var area: Area3D = _volume(_descriptor())
	await _settle_physics()
	get_tree().root.remove_child(_gateway)
	assert_eq(area.validate_character(sensor)["outcome"], "not_admitted")
	get_tree().root.add_child(_gateway)
	assert_true(sensor.is_queued_for_deletion())
	var replacement: CharacterBody3D = _sensor()
	remove_child(_state)
	assert_true(replacement.is_queued_for_deletion(), "Source exit owns sensor teardown")
	add_child(_state)


func test_closed_descriptor_rejects_invalid_geometry_and_returns_independent_values() -> void:
	var contract: Script = load("res://server/workshop_station_contract.gd")
	for alteration: Dictionary in [
		{"bounds_min": [0, 0, 0], "bounds_max": [0, 1, 1]},
		{"bounds_min": [NAN, 0, 0]}, {"bounds_max": [INF, 1, 1]},
		{"bounds_max": [1073741825, 1, 1]}, {"bounds_min": [true, 0, 0]},
		{"bounds_min": [0, 0]}, {"active": 1}, {"revision": 2},
		{"anchor_revision": true}, {"station_id": " "}, {"client_in_area": true},
	]:
		var invalid: Dictionary = _descriptor()
		invalid.merge(alteration, true)
		assert_eq(contract.parse_server_descriptor(invalid)["outcome"], "invalid_station", str(alteration))
	var source: Dictionary = _descriptor()
	var parsed: Dictionary = contract.parse_server_descriptor(source)
	var area: Area3D = _volume(source)
	source["bounds_min"][0] = -900
	parsed["station"].bounds_min = Vector3(-800, -1, -2)
	var snapshot: Dictionary = area.station_snapshot()
	snapshot["bounds_min"][0] = -700
	var expected: Dictionary = _descriptor()
	expected["bounds_min"] = [-2.0, -1.0, -2.0]
	expected["bounds_max"] = [2.0, 3.0, 2.0]
	assert_eq(area.station_snapshot(), expected, "Independent snapshots retain normalized Vector3 float coordinates")


func test_closed_client_intent_contains_only_version_and_station_reference() -> void:
	var contract: Script = load("res://server/workshop_station_contract.gd")
	assert_true(contract.has_method("parse_intent"), "Closed intent must reject client authority fields at its public seam")
	if not contract.has_method("parse_intent"):
		return
	assert_eq(contract.parse_intent({"schema_version": 1, "station_id": "fixture-station-951"}), {"outcome": "ok", "station_id": "fixture-station-951"})
	for authority_field: String in ["character_id", "peer_id", "active", "bounds_min", "in_area", "permission_mask", "plot_id"]:
		var invalid: Dictionary = {"schema_version": 1, "station_id": "fixture-station-951"}
		invalid[authority_field] = true
		assert_eq(contract.parse_intent(invalid)["outcome"], "invalid_intent", authority_field)
	for invalid: Variant in [null, {}, {"schema_version": true, "station_id": "fixture-station-951"}, {"schema_version": 2, "station_id": "fixture-station-951"}, {"schema_version": 1, "station_id": " "}]:
		assert_eq(contract.parse_intent(invalid)["outcome"], "invalid_intent")


func _sensor() -> CharacterBody3D:
	var script: Script = load("res://server/workshop_character_sensor.gd")
	var sensor: CharacterBody3D = script.new()
	add_child_autofree(sensor)
	assert_eq(sensor.bind_admitted_player(_state)["outcome"], "ok")
	return sensor


func _volume(descriptor: Dictionary) -> Area3D:
	var contract: Script = load("res://server/workshop_station_contract.gd")
	var script: Script = load("res://server/workshop_station_volume.gd")
	var parsed: Dictionary = contract.parse_server_descriptor(descriptor)
	assert_eq(parsed["outcome"], "ok")
	var area: Area3D = script.new(parsed["station"])
	add_child_autofree(area)
	return area


func _settle_physics() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
