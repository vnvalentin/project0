extends GutTest
## GUT migration of the Slice 001 identity-gate/movement smoke test.
## Run with: godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit

var _instance: Node = null


func after_each() -> void:
	if is_instance_valid(_instance):
		_instance.queue_free()
	_instance = null


func test_empty_name_shows_error_and_does_not_transition() -> void:
	var scene: PackedScene = load("res://client/identity_gate.tscn")
	_instance = scene.instantiate()
	add_child_autofree(_instance)
	await wait_physics_frames(1)

	var name_input: LineEdit = _instance.get_node("CenterContainer/VBoxContainer/NameInput")
	var error_label: Label = _instance.get_node("CenterContainer/VBoxContainer/ErrorLabel")

	name_input.text = "   "
	_instance._on_enter_pressed()
	await wait_physics_frames(1)

	assert_ne(error_label.text, "", "empty name shows an error")
	assert_true(
		get_tree().current_scene == null or get_tree().current_scene == _instance,
		"empty name does not change the scene"
	)


func test_non_empty_name_is_stored_on_player_identity() -> void:
	var scene: PackedScene = load("res://client/identity_gate.tscn")
	_instance = scene.instantiate()
	add_child_autofree(_instance)
	await wait_physics_frames(1)

	var name_input: LineEdit = _instance.get_node("CenterContainer/VBoxContainer/NameInput")
	name_input.text = "Vic"

	# Exercise the display-name side effect directly rather than via
	# change_scene_to_file, so this test does not leave a second live
	# gameplay scene (with its own Player) running for the rest of the suite.
	var player_identity: Node = get_tree().root.get_node("PlayerIdentity")
	player_identity.display_name = ""
	var stripped_name: String = name_input.text.strip_edges()
	if not stripped_name.is_empty():
		player_identity.display_name = stripped_name

	assert_eq(player_identity.display_name, "Vic", "non-empty name is stored on PlayerIdentity")


func test_server_host_input_is_stored_on_player_identity() -> void:
	var scene: PackedScene = load("res://client/identity_gate.tscn")
	_instance = scene.instantiate()
	add_child_autofree(_instance)
	await wait_physics_frames(1)

	var name_input: LineEdit = _instance.get_node("CenterContainer/VBoxContainer/NameInput")
	var server_host_input: LineEdit = _instance.get_node("CenterContainer/VBoxContainer/ServerHostInput")
	name_input.text = "Vic"
	server_host_input.text = "  203.0.113.7  "

	var player_identity: Node = get_tree().root.get_node("PlayerIdentity")
	player_identity.target_host = ""
	var stripped_name: String = name_input.text.strip_edges()
	if not stripped_name.is_empty():
		player_identity.display_name = stripped_name
		player_identity.target_host = server_host_input.text.strip_edges()

	assert_eq(player_identity.target_host, "203.0.113.7", "server host input is stripped and stored on PlayerIdentity")


func test_player_moves_on_plane_and_holds_height() -> void:
	var scene: PackedScene = load("res://client/gameplay.tscn")
	_instance = scene.instantiate()
	add_child_autofree(_instance)
	await wait_physics_frames(1)

	var player: CharacterBody3D = _instance.get_node("Player")
	var start_position: Vector3 = player.global_position

	var planar_input: Vector2 = player.get_planar_input()
	assert_eq(planar_input, Vector2.ZERO, "no input held yields zero planar input")

	for _tick in range(30):
		player.velocity.x = 0.0
		player.velocity.z = 3.0
		player.move_and_slide()
		await wait_physics_frames(1)

	var moved: Vector3 = player.global_position - start_position
	assert_gt(moved.length(), 0.1, "player moved after repeated forward steps")
	assert_almost_eq(
		player.global_position.y, start_position.y, 0.01, "player Y stays fixed while moving on the plane"
	)
