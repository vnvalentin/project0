extends GutTest
## Public-seam test for Slice 030: ServerPlayerState with an injected collision
## map blocks authoritative movement into solids, and moves freely without one
## (backward compatible). Drives _physics_process directly — the
## CONNECTION_CONNECTED RPC guard makes that safe in a test with no real server
## (see server/server_player_state.gd). See docs/slices/030-server-side-collision.md.

const ServerPlayerStateScript: Script = preload("res://server/server_player_state.gd")
const SectorCollisionMapScript: Script = preload("res://shared/sector_collision_map.gd")

const _DELTA: float = 1.0 / 60.0


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
