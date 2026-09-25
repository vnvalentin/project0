extends GutTest
## Public-seam test for Slice 030: ServerPlayerState with an injected collision
## map blocks authoritative movement into solids, and moves freely without one
## (backward compatible). Drives _physics_process directly — the
## CONNECTION_CONNECTED RPC guard makes that safe in a test with no real server
## (see server/server_player_state.gd). See docs/slices/030-server-side-collision.md.

const ServerPlayerStateScript: Script = preload("res://server/server_player_state.gd")
const SectorCollisionMapScript: Script = preload("res://shared/sector_collision_map.gd")

const _DELTA: float = 1.0 / 60.0
var _network_client: Node


func before_all() -> void:
	_network_client = get_tree().root.get_node_or_null("NetworkClient")
	if _network_client != null:
		_network_client.name = "CollisionTestNetworkClient"


func after_all() -> void:
	if _network_client != null:
		_network_client.name = "NetworkClient"


class DiagonalOnlyCollision extends RefCounted:
	func resolve_move(current: Vector3, desired: Vector3) -> Vector3:
		return current if desired.x > current.x and is_equal_approx(desired.z, current.z) else desired


func _new_state(start: Vector3) -> Node:
	var state: Node = ServerPlayerStateScript.new()
	add_child_autofree(state)
	state.start_for_peer(1, start)
	return state


func _advance(state: Node, ticks: int) -> void:
	for i in ticks:
		state._physics_process(_DELTA)


func test_player_moves_freely_without_a_collision_map() -> void:
	var state: Node = _new_state(Vector3(0, 1, 0))
	state.apply_input_intent(1, Vector2(1, 0), 0)  # move +x
	_advance(state, 60)  # ~1s at 5 u/s
	assert_gt(state.position.x, 4.5, "with no collision map, ~1s of +x input moves the player freely (~5 units)")


func test_player_is_blocked_by_a_wall() -> void:
	var state: Node = _new_state(Vector3(0, 1, 0))
	var map: Object = SectorCollisionMapScript.new({"tiles": [{"x": 2, "y": 0, "kind": "wall"}], "structures": []})
	state.set_collision_map(map)
	state.apply_input_intent(1, Vector2(1, 0), 0)
	_advance(state, 120)
	assert_lt(state.position.x, 1.5, "the player never enters the solid wall cell (stops at its face)")
	assert_gt(state.position.x, 1.0, "the player advanced right up to the wall face")


func test_player_is_blocked_by_a_building_footprint() -> void:
	var state: Node = _new_state(Vector3(0, 1, 0))
	# House at (3,0) with footprint (1,1) blocks cells x in [2,4] on the y=0 row.
	var map: Object = SectorCollisionMapScript.new({"tiles": [], "structures": [{"structure_id": "h1", "kind": "house", "x": 3, "y": 0, "facing_degrees": 0.0}]})
	state.set_collision_map(map)
	state.apply_input_intent(1, Vector2(1, 0), 0)
	_advance(state, 120)
	assert_lt(state.position.x, 1.5, "the player is stopped at the face of the building footprint")


func test_player_slides_along_a_wall_diagonally() -> void:
	var state: Node = _new_state(Vector3(0, 1, 0))
	# A tall wall column at x=2 so the player stays beside it while sliding
	# (a short column would let the player slide past its top and move on).
	var tiles: Array = []
	for y in range(0, 21):
		tiles.append({"x": 2, "y": y, "kind": "wall"})
	var map: Object = SectorCollisionMapScript.new({"tiles": tiles, "structures": []})
	state.set_collision_map(map)
	state.apply_input_intent(1, Vector2(1, 1), 0)  # +x and +z
	_advance(state, 60)
	assert_lt(state.position.x, 1.5, "x stays out of the wall column")
	assert_gt(state.position.z, 2.0, "z keeps sliding north along the wall")


func test_frontier_hold_keeps_ticks_sequences_and_adjacent_movement_advancing() -> void:
	var state: Node = _new_state(Vector3(439.99, 1, 10))
	var admission: Callable = func(_peer_id: int, current: Vector3, candidate: Vector3) -> Vector3:
		return Vector3(current.x, candidate.y, candidate.z) if candidate.x >= 440.0 else candidate
	if state.has_method("set_movement_admission"):
		state.set_movement_admission(admission)
	watch_signals(state)
	state.apply_input_intent(1, Vector2(1, 1), 10)
	_advance(state, 20)
	assert_lt(state.position.x, 440.0, "unready frontier must hold the authoritative position")
	assert_gt(state.position.z, 10.5, "parallel movement continues while the crossing is held")
	assert_signal_emit_count(state, "position_updated", 20, "held input still produces every simulation update")
	state.apply_input_intent(1, Vector2(-1, 0), 11)
	state.apply_input_intent(1, Vector2(1, 0), 10)
	var before_retreat: float = state.position.x
	_advance(state, 1)
	assert_lt(state.position.x, before_retreat, "new sequence retreats; stale held intent cannot replace it")


func test_frontier_slide_is_collision_checked_without_repeating_admission() -> void:
	var state: Node = _new_state(Vector3(0, 1, 0))
	state.set_collision_map(DiagonalOnlyCollision.new())
	var candidates: Array[Vector3] = []
	state.set_movement_admission(func(_peer_id: int, current: Vector3, candidate: Vector3) -> Vector3:
		candidates.append(candidate)
		return Vector3(candidate.x, candidate.y, current.z)
	)
	state.apply_input_intent(1, Vector2(1, 1), 1)
	_advance(state, 1)
	assert_eq(candidates.size(), 1, "admission side effects occur exactly once per tick")
	assert_gt(candidates[0].z, 0.0, "admission received the collision-resolved diagonal candidate")
	assert_eq(state.position, Vector3(0, 1, 0), "frontier clipping must not slide into a collision")
