extends GutTest
## Public-seam integration test for Slice 015: runs
## client/sector_geometry_translator.gd against a fixture blueprint Dictionary
## containing one of each supported tile kind and one of each supported
## structure kind, inside a real SceneTree/Node3D, and asserts the expected
## child node count/types/positions are produced. See
## docs/slices/015-sector-geometry-translation.md.

const SectorGeometryTranslatorScript: Script = preload("res://client/sector_geometry_translator.gd")


func _fixture_blueprint() -> Dictionary:
	return {
		"schema_version": 2,
		"sector_id": "sector-geometry-fixture",
		"origin": {"x": 0, "y": 0},
		"tiles": [
			{"x": 0, "y": 0, "kind": "floor"},
			{"x": 1, "y": 0, "kind": "wall"},
			{"x": 2, "y": 0, "kind": "corridor"},
		],
		"structures": [
			{"structure_id": "house-1", "kind": "house", "x": 5.0, "y": 6.0, "facing_degrees": 0.0},
			{"structure_id": "smithy-1", "kind": "smithy", "x": -4.0, "y": 2.0, "facing_degrees": 90.0},
			{"structure_id": "armor_shop-1", "kind": "armor_shop", "x": 3.0, "y": -3.0, "facing_degrees": 180.0},
			{"structure_id": "inn-1", "kind": "inn", "x": -2.0, "y": -5.0, "facing_degrees": 270.0},
		],
	}


func test_ground_tiles_render_as_per_kind_merged_mesh_with_no_bodies() -> void:
	var parent: Node3D = add_child_autofree(Node3D.new())
	SectorGeometryTranslatorScript.translate(_fixture_blueprint(), parent)
	await wait_physics_frames(1)

	var floor_ground: MeshInstance3D = parent.get_node_or_null("Ground_floor") as MeshInstance3D
	var corridor_ground: MeshInstance3D = parent.get_node_or_null("Ground_corridor") as MeshInstance3D
	assert_not_null(floor_ground, "floor tiles render as a single Ground_floor MeshInstance3D")
	assert_not_null(corridor_ground, "corridor tiles render as a single Ground_corridor MeshInstance3D")
	assert_not_null(floor_ground.mesh, "the merged ground has a mesh")
	assert_eq(floor_ground.mesh.get_surface_count(), 1, "the merged ground is a single surface (one draw call)")

	# Ground is visual-only: the mesh node carries no collider children.
	assert_eq(floor_ground.get_child_count(), 0, "ground mesh has no collider children")

	var floor_aabb: AABB = floor_ground.mesh.get_aabb()
	assert_almost_eq(floor_aabb.size.x, 1.0, 0.001, "the one floor tile spans one unit in x")
	assert_almost_eq(floor_aabb.get_center().x, 0.0, 0.001, "floor tile is centered at its grid x")
	assert_almost_eq(floor_aabb.get_center().z, 0.0, 0.001, "floor tile is centered at its grid y (mapped to world z)")


func test_wall_tiles_render_as_merged_colliders_taller_than_ground() -> void:
	var parent: Node3D = add_child_autofree(Node3D.new())
	SectorGeometryTranslatorScript.translate(_fixture_blueprint(), parent)
	await wait_physics_frames(1)

	var walls: StaticBody3D = parent.get_node_or_null("Walls") as StaticBody3D
	assert_not_null(walls, "wall tiles render under a single Walls StaticBody3D")

	var shape: CollisionShape3D = walls.get_node_or_null("WallSegmentShape_0") as CollisionShape3D
	var mesh: MeshInstance3D = walls.get_node_or_null("WallSegmentMesh_0") as MeshInstance3D
	assert_not_null(shape, "the wall run has a collision shape")
	assert_not_null(mesh, "the wall run has a mesh")

	var wall_box: BoxMesh = mesh.mesh
	var floor_ground: MeshInstance3D = parent.get_node("Ground_floor") as MeshInstance3D
	var floor_aabb: AABB = floor_ground.mesh.get_aabb()
	assert_gt(wall_box.size.y, floor_aabb.size.y, "the wall segment reads taller than the ground")

	assert_almost_eq(shape.position.x, 1.0, 0.001, "the single wall tile's collider centers on its x")
	assert_almost_eq((shape.shape as BoxShape3D).size.x, 1.0, 0.001, "a one-tile wall run is one unit long")


func test_translate_produces_one_instance_per_structure_with_expected_position_and_rotation() -> void:
	var parent: Node3D = add_child_autofree(Node3D.new())
	SectorGeometryTranslatorScript.translate(_fixture_blueprint(), parent)
	await wait_physics_frames(1)

	var house: Node3D = parent.get_node("Structure_house-1")
	var smithy: Node3D = parent.get_node("Structure_smithy-1")
	var armor_shop: Node3D = parent.get_node("Structure_armor_shop-1")
	var inn: Node3D = parent.get_node("Structure_inn-1")

	assert_not_null(house, "the house structure entry produces a child node")
	assert_not_null(smithy, "the smithy structure entry produces a child node")
	assert_not_null(armor_shop, "the armor_shop structure entry produces a child node")
	assert_not_null(inn, "the inn structure entry produces a child node")

	assert_almost_eq(house.position.x, 5.0, 0.001, "house is positioned at its x")
	assert_almost_eq(house.position.z, 6.0, 0.001, "house is positioned at its y (mapped to world z)")

	var smithy_forward: Vector3 = -smithy.transform.basis.z
	assert_almost_eq(smithy_forward.x, -1.0, 0.01, "smithy's 90-degree facing rotates its forward vector per Basis(Vector3.UP, angle)'s convention")
	assert_almost_eq(smithy_forward.z, 0.0, 0.01, "smithy's 90-degree facing has no residual Z forward component")


func test_translate_produces_the_expected_container_children() -> void:
	var parent: Node3D = add_child_autofree(Node3D.new())
	SectorGeometryTranslatorScript.translate(_fixture_blueprint(), parent)
	await wait_physics_frames(1)

	# 2 ground MultiMesh nodes (floor, corridor) + 1 merged Walls body + 4 structures.
	assert_eq(parent.get_child_count(), 7, "floor/corridor MultiMeshes + one Walls body + 4 structures produce 7 top-level children")

	# The scale win: no per-tile bodies. The only body that is not a structure
	# prefab (whose own root is a StaticBody3D) is the single merged Walls body.
	var non_structure_bodies: int = 0
	for child in parent.get_children():
		if child is StaticBody3D and not String(child.name).begins_with("Structure_"):
			non_structure_bodies += 1
	assert_eq(non_structure_bodies, 1, "the only non-structure physics body is the single merged Walls body (no per-tile bodies)")


func test_unsupported_tile_and_structure_kinds_are_skipped_without_crashing() -> void:
	var parent: Node3D = add_child_autofree(Node3D.new())
	var blueprint: Dictionary = _fixture_blueprint()
	blueprint["tiles"].append({"x": 9, "y": 9, "kind": "lava"})
	blueprint["structures"].append({"structure_id": "castle-1", "kind": "castle", "x": 1.0, "y": 1.0, "facing_degrees": 0.0})

	SectorGeometryTranslatorScript.translate(blueprint, parent)
	await wait_physics_frames(1)

	assert_eq(parent.get_child_count(), 7, "unsupported tile/structure entries are skipped, leaving the 7 valid containers/instances")
	assert_null(parent.get_node_or_null("Ground_lava"), "an unsupported tile kind produces no ground node")
	var floor_ground: MeshInstance3D = parent.get_node("Ground_floor") as MeshInstance3D
	assert_almost_eq(floor_ground.mesh.get_aabb().size.x, 1.0, 0.001, "the unsupported lava tile is not merged into any ground mesh")


func test_floor_only_sector_produces_zero_physics_bodies() -> void:
	# The DT-008 scale fix: many walkable tiles must not create many bodies.
	var parent: Node3D = add_child_autofree(Node3D.new())
	var tiles: Array = []
	for x in range(5):
		tiles.append({"x": x, "y": 0, "kind": "floor"})
	var blueprint: Dictionary = {"schema_version": 2, "sector_id": "floors", "origin": {"x": 0, "y": 0}, "tiles": tiles, "structures": []}

	SectorGeometryTranslatorScript.translate(blueprint, parent)
	await wait_physics_frames(1)

	var floor_ground: MeshInstance3D = parent.get_node_or_null("Ground_floor") as MeshInstance3D
	assert_not_null(floor_ground, "floors render as a single MeshInstance3D")
	assert_eq(floor_ground.mesh.get_surface_count(), 1, "all 5 floor tiles merge into one surface")
	assert_almost_eq(floor_ground.mesh.get_aabb().size.x, 5.0, 0.001, "the merged floor mesh spans all 5 tiles (x=0..4 -> width 5)")

	var bodies: int = 0
	for child in parent.get_children():
		if child is StaticBody3D:
			bodies += 1
	assert_eq(bodies, 0, "a floor-only sector produces zero physics bodies (DT-008 scale fix)")


func test_contiguous_wall_run_merges_into_one_collider() -> void:
	var parent: Node3D = add_child_autofree(Node3D.new())
	var tiles: Array = []
	for x in range(5):
		tiles.append({"x": x, "y": 0, "kind": "wall"})
	var blueprint: Dictionary = {"schema_version": 2, "sector_id": "wallrun", "origin": {"x": 0, "y": 0}, "tiles": tiles, "structures": []}

	SectorGeometryTranslatorScript.translate(blueprint, parent)
	await wait_physics_frames(1)

	var walls: StaticBody3D = parent.get_node("Walls") as StaticBody3D
	var shapes: int = 0
	for child in walls.get_children():
		if child is CollisionShape3D:
			shapes += 1
	assert_eq(shapes, 1, "5 contiguous wall tiles merge into ONE collider, not 5")

	var shape: CollisionShape3D = walls.get_node("WallSegmentShape_0") as CollisionShape3D
	assert_almost_eq((shape.shape as BoxShape3D).size.x, 5.0, 0.001, "the merged collider spans all 5 tiles")
	assert_almost_eq(shape.position.x, 2.0, 0.001, "the merged collider centers on the run (x=0..4 -> center 2)")


func test_gapped_wall_tiles_in_a_row_merge_into_separate_colliders() -> void:
	var parent: Node3D = add_child_autofree(Node3D.new())
	var blueprint: Dictionary = {
		"schema_version": 2, "sector_id": "gap", "origin": {"x": 0, "y": 0}, "structures": [],
		"tiles": [
			{"x": 0, "y": 0, "kind": "wall"},
			{"x": 1, "y": 0, "kind": "wall"},
			{"x": 5, "y": 0, "kind": "wall"},
			{"x": 6, "y": 0, "kind": "wall"},
		],
	}

	SectorGeometryTranslatorScript.translate(blueprint, parent)
	await wait_physics_frames(1)

	var walls: StaticBody3D = parent.get_node("Walls") as StaticBody3D
	var shapes: int = 0
	for child in walls.get_children():
		if child is CollisionShape3D:
			shapes += 1
	assert_eq(shapes, 2, "two separated wall runs in one row produce two merged colliders")
