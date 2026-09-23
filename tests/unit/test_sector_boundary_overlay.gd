extends GutTest

const OverlayScript: Script = preload("res://client/sector_boundary_overlay.gd")
const GameplayScene: PackedScene = preload("res://client/gameplay.tscn")


func test_gameplay_overlay_is_hidden_by_default_and_f3_toggles_it() -> void:
	var gameplay: Node3D = add_child_autofree(GameplayScene.instantiate())
	var overlay: Node3D = gameplay.get_node("SectorBoundaryOverlay")
	var label: Label = gameplay.get_node("UI/SectorBoundaryLabel")
	assert_false(overlay.visible)
	assert_false(label.visible)

	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_F3
	event.pressed = true
	overlay._unhandled_input(event)
	assert_true(overlay.visible)
	assert_true(label.visible)

	overlay._unhandled_input(event)
	assert_false(overlay.visible)
	assert_false(label.visible)


func test_overlay_tracks_negative_sector_bounds_and_lifecycle_signals() -> void:
	var root: Node3D = add_child_autofree(Node3D.new())
	var player: Node3D = Node3D.new()
	player.name = "Player"
	root.add_child(player)
	var label: Label = Label.new()
	label.name = "SectorLabel"
	root.add_child(label)
	var overlay: Node3D = OverlayScript.new()
	overlay.player_path = NodePath("../Player")
	overlay.label_path = NodePath("../SectorLabel")
	root.add_child(overlay)

	overlay.show_overlay()
	player.position = Vector3(-0.1, 0.0, -440.0)
	overlay.refresh_position()
	assert_eq(overlay.current_sector_id, "sector--1--1")
	assert_eq(overlay.position, Vector3(-220.0, 0.15, -220.0))
	assert_eq(overlay.get_child_count(), 4, "one stable mesh segment renders each sector edge")
	_assert_edge(overlay, "North", Vector3(0.0, 0.0, -220.0), Vector3(440.0, 0.12, 0.6))
	_assert_edge(overlay, "South", Vector3(0.0, 0.0, 220.0), Vector3(440.0, 0.12, 0.6))
	_assert_edge(overlay, "West", Vector3(-220.0, 0.0, 0.0), Vector3(0.6, 0.12, 440.0))
	_assert_edge(overlay, "East", Vector3(220.0, 0.0, 0.0), Vector3(0.6, 0.12, 440.0))
	assert_string_contains(label.text, "sector--1--1")
	assert_string_contains(label.text, OverlayScript.STATE_UNEXPLORED)

	NetworkClient.authoritative_position_received.emit(player.position, 1)
	assert_string_contains(label.text, OverlayScript.STATE_GENERATING)

	NetworkClient.sector_blueprint_received.emit("sector--1--1", "invalid", 0, 0)
	NetworkClient.sector_blueprint_received.emit("sector-0-0", "valid", 1, 0)
	assert_string_contains(label.text, OverlayScript.STATE_GENERATING)

	NetworkClient.sector_blueprint_received.emit("sector--1--1", "valid", 1, 0)
	assert_string_contains(label.text, OverlayScript.STATE_CANON)


func _assert_edge(overlay: Node3D, edge_name: String, expected_position: Vector3, expected_size: Vector3) -> void:
	var edge: MeshInstance3D = overlay.get_node(edge_name)
	assert_eq(edge.position, expected_position)
	assert_eq((edge.mesh as BoxMesh).size, expected_size)
