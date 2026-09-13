extends GutTest
## Public-seam unit tests for Slice 030's server-side collision map
## (shared/sector_collision_map.gd): wall tiles and building footprints are
## solid, walkable ground stays open, and moves slide along solids. Pure and
## deterministic. See docs/slices/030-server-side-collision.md.

const SectorCollisionMapScript: Script = preload("res://shared/sector_collision_map.gd")
const StartingTownHubFixtureScript: Script = preload("res://server/starting_town_hub_fixture.gd")


func test_wall_tiles_are_blocked_and_ground_is_open() -> void:
	var blueprint: Dictionary = {
		"tiles": [
			{"x": 0, "y": 0, "kind": "floor"},
			{"x": 1, "y": 0, "kind": "wall"},
			{"x": 2, "y": 0, "kind": "path"},
			{"x": 3, "y": 0, "kind": "water"},
		],
		"structures": [],
	}
	var map: Object = SectorCollisionMapScript.new(blueprint)
	assert_true(map.is_blocked(Vector2i(1, 0)), "a wall cell is solid")
	assert_false(map.is_blocked(Vector2i(0, 0)), "a floor cell is open")
	assert_false(map.is_blocked(Vector2i(2, 0)), "a path cell is open")
	assert_false(map.is_blocked(Vector2i(3, 0)), "water is open (walkable)")


func test_structure_footprint_is_blocked() -> void:
	# A house has half-extent (1,1) -> a 3x3 block around its anchor.
	var blueprint: Dictionary = {
		"tiles": [{"x": 0, "y": 0, "kind": "floor"}],
		"structures": [{"structure_id": "h1", "kind": "house", "x": 5, "y": 5, "facing_degrees": 0.0}],
	}
	var map: Object = SectorCollisionMapScript.new(blueprint)
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			assert_true(map.is_blocked(Vector2i(5 + dx, 5 + dy)), "house footprint cell (%d,%d) is solid" % [5 + dx, 5 + dy])
	assert_false(map.is_blocked(Vector2i(5, 7)), "a cell past the house footprint is open")
	assert_false(map.is_blocked(Vector2i(7, 5)), "a cell past the house footprint is open")


func test_resolve_move_is_free_in_open_space() -> void:
	var map: Object = SectorCollisionMapScript.new({"tiles": [], "structures": []})
	var to: Vector3 = Vector3(2.5, 1.0, 0.0)
	assert_eq(map.resolve_move(Vector3(0, 1, 0), to), to, "with nothing solid, the move is unchanged")


func test_resolve_move_stops_at_a_wall_face() -> void:
	# Wall at cell (1,0); a point moving +x from open cell 0 cannot enter it.
	var map: Object = SectorCollisionMapScript.new({"tiles": [{"x": 1, "y": 0, "kind": "wall"}], "structures": []})
	var result: Vector3 = map.resolve_move(Vector3(0.4, 1, 0), Vector3(0.6, 1, 0))
	assert_almost_eq(result.x, 0.4, 0.001, "the blocked +x move keeps the player at the wall face, not inside the wall cell")


func test_resolve_move_slides_along_a_wall() -> void:
	# Wall at (1,0). A diagonal (+x,+z) move has its +x blocked but +z open, so
	# the player slides north along the wall.
	var map: Object = SectorCollisionMapScript.new({"tiles": [{"x": 1, "y": 0, "kind": "wall"}], "structures": []})
	var result: Vector3 = map.resolve_move(Vector3(0.4, 1, 0.0), Vector3(0.6, 1, 0.4))
	assert_almost_eq(result.x, 0.4, 0.001, "x is blocked by the wall")
	assert_almost_eq(result.z, 0.4, 0.001, "z slides freely along the wall")


func test_real_hub_wall_is_solid_but_gate_is_passable() -> void:
	var map: Object = SectorCollisionMapScript.new(StartingTownHubFixtureScript.blueprint())
	assert_gt(map.blocked_count(), 0, "the hub produces solid cells")
	# The southern gate opening (a 'gate' tile, not a wall) must be passable.
	assert_false(map.is_blocked(Vector2i(0, -30)), "the southern gate opening is passable")
	# The northern perimeter is wall, so it must be solid.
	assert_true(map.is_blocked(Vector2i(0, 30)), "the northern perimeter wall is solid")
