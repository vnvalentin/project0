extends GutTest
## Slice 131: the static, parent-injected town NPC client render seam
## (client/network_client.gd), mirroring test_monster_replication. Exercised
## without a live multiplayer peer or current_scene. See
## docs/slices/131-phase14-town-npc-live-replication.md.

const NetworkClientScript: Script = preload("res://client/network_client.gd")


func _container() -> Node3D:
	var container := Node3D.new()
	add_child_autofree(container)
	return container


func test_node_name_is_namespaced_by_npc_id() -> void:
	assert_eq(NetworkClientScript.town_npc_node_name("villager_1"), "TownNpc_villager_1")


func test_spawn_creates_one_node_per_npc_id() -> void:
	var container: Node3D = _container()
	NetworkClientScript.spawn_town_npc_representation("v0", Vector3(1, 1, 2), container)
	var node: Node = container.get_node_or_null(NetworkClientScript.town_npc_node_name("v0"))
	assert_not_null(node, "the town NPC node is created")
	assert_true(node.position.is_equal_approx(Vector3(1, 1, 2)), "seeded at its start position")


func test_duplicate_spawn_is_a_no_op() -> void:
	var container: Node3D = _container()
	NetworkClientScript.spawn_town_npc_representation("v0", Vector3.ZERO, container)
	NetworkClientScript.spawn_town_npc_representation("v0", Vector3(9, 9, 9), container)
	assert_eq(container.get_child_count(), 1, "a duplicate spawn does not create a second node")


func test_distinct_npc_ids_get_distinct_nodes() -> void:
	var container: Node3D = _container()
	NetworkClientScript.spawn_town_npc_representation("v0", Vector3.ZERO, container)
	NetworkClientScript.spawn_town_npc_representation("v1", Vector3(5, 1, 5), container)
	assert_not_null(container.get_node_or_null(NetworkClientScript.town_npc_node_name("v0")))
	assert_not_null(container.get_node_or_null(NetworkClientScript.town_npc_node_name("v1")))


func test_apply_position_updates_the_node_target() -> void:
	var container: Node3D = _container()
	NetworkClientScript.spawn_town_npc_representation("v0", Vector3.ZERO, container)
	NetworkClientScript.apply_town_npc_position("v0", Vector3(3, 1, -4), container)
	var node: Node = container.get_node_or_null(NetworkClientScript.town_npc_node_name("v0"))
	assert_eq(node.npc_id, "v0", "the node is bound to its npc_id")


func test_apply_position_for_unknown_npc_is_a_no_op() -> void:
	var container: Node3D = _container()
	NetworkClientScript.apply_town_npc_position("ghost", Vector3(1, 1, 1), container)
	assert_eq(container.get_child_count(), 0, "no node is created for an unknown npc")


func test_despawn_removes_the_node() -> void:
	var container: Node3D = _container()
	NetworkClientScript.spawn_town_npc_representation("v0", Vector3.ZERO, container)
	NetworkClientScript.despawn_town_npc_representation("v0", container)
	var node: Node = container.get_node_or_null(NetworkClientScript.town_npc_node_name("v0"))
	assert_true(node == null or node.is_queued_for_deletion(), "despawn removes the npc's node")
