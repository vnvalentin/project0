extends GutTest
## Public-seam integration tests for Slice 018's facade proximity trigger
## (client/facade_proximity.gd). Covers the local-player filter and
## presenter wiring at the signal-handler level (deterministic, no physics),
## plus one real Area3D physics-overlap test against the actual smithy prefab
## to confirm its collision configuration fires body_entered for the local
## player. See docs/slices/018-facade-enter-exit.md.

const FacadeProximityScript: Script = preload("res://client/facade_proximity.gd")
const FacadePresenterScript: Script = preload("res://client/facade_presenter.gd")
const SMITHY_SCENE_PATH: String = "res://client/structures/smithy.tscn"


func _presenter_in_group() -> Label:
	var label: Label = Label.new()
	label.set_script(FacadePresenterScript)
	return add_child_autofree(label)


func _facade(display_name: String) -> Area3D:
	var area: Area3D = Area3D.new()
	area.set_script(FacadeProximityScript)
	area.building_display_name = display_name
	return add_child_autofree(area)


func _named_body(node_name: String) -> Node3D:
	var body: Node3D = Node3D.new()
	body.name = node_name
	return add_child_autofree(body)


func test_local_player_entry_shows_the_facade_name() -> void:
	var presenter: Label = _presenter_in_group()
	var facade: Area3D = _facade("Smithy")
	await wait_physics_frames(1)

	facade._on_body_entered(_named_body("Player"))
	assert_true(presenter.visible, "the local player entering a facade shows the label")
	assert_eq(presenter.text, "You are at the Smithy", "the facade's building name is shown")


func test_local_player_exit_clears_the_facade_name() -> void:
	var presenter: Label = _presenter_in_group()
	var facade: Area3D = _facade("Smithy")
	await wait_physics_frames(1)
	var player: Node3D = _named_body("Player")

	facade._on_body_entered(player)
	facade._on_body_exited(player)
	assert_false(presenter.visible, "the local player leaving a facade clears the label")
	assert_eq(presenter.text, "", "the facade line is emptied on exit")


func test_non_local_bodies_are_ignored() -> void:
	var presenter: Label = _presenter_in_group()
	var facade: Area3D = _facade("Smithy")
	await wait_physics_frames(1)

	# A remote peer's Player, the structure body, and the flat plane must never
	# drive the local label.
	facade._on_body_entered(_named_body("RemotePlayer_2"))
	facade._on_body_entered(_named_body("Smithy"))
	facade._on_body_entered(_named_body("FlatPlane"))
	assert_false(presenter.visible, "non-local bodies do not show the label")
	assert_eq(presenter.text, "", "non-local bodies leave the label empty")


func test_is_local_player_filter() -> void:
	var facade: Area3D = _facade("Smithy")
	assert_true(facade.is_local_player(_named_body("Player")), "the node named 'Player' is the local player")
	assert_false(facade.is_local_player(_named_body("RemotePlayer_3")), "a remote peer is not the local player")
	assert_false(facade.is_local_player(null), "a null body is not the local player")


func test_real_smithy_prefab_area_fires_for_the_local_player() -> void:
	# End-to-end physics check that the smithy prefab's FacadeProximity area and
	# collision config actually detect the local player body overlapping it.
	var presenter: Label = _presenter_in_group()
	var smithy: Node3D = add_child_autofree((load(SMITHY_SCENE_PATH) as PackedScene).instantiate())
	smithy.position = Vector3.ZERO

	var player: CharacterBody3D = CharacterBody3D.new()
	player.name = "Player"
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(1, 1.8, 1)
	shape.shape = box
	player.add_child(shape)
	player.position = Vector3(0, 1, 0)
	add_child_autofree(player)

	await wait_physics_frames(4)

	assert_true(presenter.visible, "the real smithy prefab area detects the overlapping local player")
	assert_eq(presenter.text, "You are at the Smithy", "the real smithy prefab reports its building name")
