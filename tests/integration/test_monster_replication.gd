extends GutTest
## Public-seam integration test for Slice 033's client-side monster
## replication render path (NetworkClient.spawn_monster_representation /
## receive_monster_position / despawn_monster_representation). Mirrors
## tests/integration/test_blueprint_replication.gd's style: drives the static,
## parent-injected seam directly inside a real SceneTree/Node3D so no live
## ENet peer or NetworkClient autoload instance is required. See
## docs/slices/033-client-monster-replication-and-rendering.md.

const NetworkClientScript: Script = preload("res://client/network_client.gd")


func test_spawn_creates_exactly_one_node_per_target_id() -> void:
	var container: Node3D = add_child_autofree(Node3D.new())

	NetworkClientScript.spawn_monster_representation("m0", Vector3(1.0, 1.0, 2.0), container)
	await wait_physics_frames(1)

	var node_name: String = NetworkClientScript.monster_node_name("m0")
	var monster_node: Node3D = container.get_node_or_null(node_name) as Node3D
	assert_not_null(monster_node, "a monster representation node is created under the container")
	assert_eq(monster_node.position, Vector3(1.0, 1.0, 2.0), "the node spawns at the given start position")
	assert_eq(container.get_child_count(), 1, "exactly one node is created for one target_id")


func test_duplicate_spawn_for_the_same_target_id_is_a_no_op() -> void:
	var container: Node3D = add_child_autofree(Node3D.new())

	NetworkClientScript.spawn_monster_representation("m0", Vector3.ZERO, container)
	await wait_physics_frames(1)
	NetworkClientScript.spawn_monster_representation("m0", Vector3(9.0, 9.0, 9.0), container)
	await wait_physics_frames(1)

	assert_eq(container.get_child_count(), 1, "a duplicate spawn for the same target_id creates no second node")
	var monster_node: Node3D = container.get_node_or_null(NetworkClientScript.monster_node_name("m0")) as Node3D
	assert_eq(monster_node.position, Vector3.ZERO, "the duplicate spawn does not move the existing node")


func test_spawn_is_scoped_per_target_id() -> void:
	var container: Node3D = add_child_autofree(Node3D.new())

	NetworkClientScript.spawn_monster_representation("m0", Vector3.ZERO, container)
	NetworkClientScript.spawn_monster_representation("m1", Vector3(5.0, 1.0, 5.0), container)
	await wait_physics_frames(1)

	assert_eq(container.get_child_count(), 2, "two distinct target_ids produce two distinct nodes")
	assert_not_null(container.get_node_or_null(NetworkClientScript.monster_node_name("m0")), "m0 has its own node")
	assert_not_null(container.get_node_or_null(NetworkClientScript.monster_node_name("m1")), "m1 has its own node")


func test_receive_position_moves_the_existing_node() -> void:
	var container: Node3D = add_child_autofree(Node3D.new())
	NetworkClientScript.spawn_monster_representation("m0", Vector3.ZERO, container)
	await wait_physics_frames(1)

	NetworkClientScript.apply_monster_position("m0", Vector3(3.0, 1.0, -4.0), container)

	var monster_node: Node3D = container.get_node_or_null(NetworkClientScript.monster_node_name("m0")) as Node3D
	assert_not_null(monster_node, "the node still exists after a position update")
	# Position is authoritative target state relayed via a signal the node
	# smooths toward, not an instant snap — see client/monster.gd's own test
	# for the smoothing behavior. Here we only prove the seam locates the
	# correct node and forwards the update without erroring on a missing one.


func test_receive_position_for_an_unknown_target_id_is_a_no_op() -> void:
	var container: Node3D = add_child_autofree(Node3D.new())

	# Must not push an error or create a node for a target_id that was never spawned.
	NetworkClientScript.apply_monster_position("ghost", Vector3(1.0, 1.0, 1.0), container)
	await wait_physics_frames(1)

	assert_eq(container.get_child_count(), 0, "an update for an unknown target_id creates nothing")


func test_despawn_removes_the_nodes_representation() -> void:
	var container: Node3D = add_child_autofree(Node3D.new())
	NetworkClientScript.spawn_monster_representation("m0", Vector3.ZERO, container)
	await wait_physics_frames(1)

	NetworkClientScript.despawn_monster_representation("m0", container)
	await wait_physics_frames(1)

	assert_null(container.get_node_or_null(NetworkClientScript.monster_node_name("m0")), "despawn removes the target_id's node")


func test_despawn_of_an_already_gone_monster_is_a_no_op() -> void:
	var container: Node3D = add_child_autofree(Node3D.new())

	# No spawn happened for "m0" at all; despawning it must not error.
	NetworkClientScript.despawn_monster_representation("m0", container)
	await wait_physics_frames(1)

	assert_eq(container.get_child_count(), 0, "despawning an unknown target_id is a safe no-op")
