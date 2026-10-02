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
