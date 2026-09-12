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


func test_translate_produces_one_static_body_per_tile_with_expected_position_and_shape() -> void:
	var parent: Node3D = add_child_autofree(Node3D.new())
	SectorGeometryTranslatorScript.translate(_fixture_blueprint(), parent)
	await wait_physics_frames(1)

	var floor_tile: Node = parent.get_node("Tile_floor_0_0")
	var wall_tile: Node = parent.get_node("Tile_wall_1_0")
	var corridor_tile: Node = parent.get_node("Tile_corridor_2_0")

	assert_true(floor_tile is StaticBody3D, "a floor tile becomes a StaticBody3D")
	assert_true(wall_tile is StaticBody3D, "a wall tile becomes a StaticBody3D")
	assert_true(corridor_tile is StaticBody3D, "a corridor tile becomes a StaticBody3D")

	assert_almost_eq(floor_tile.position.x, 0.0, 0.001, "floor tile is positioned at its grid x")
	assert_almost_eq(floor_tile.position.z, 0.0, 0.001, "floor tile is positioned at its grid y (mapped to world z)")
	assert_almost_eq(wall_tile.position.x, 1.0, 0.001, "wall tile is positioned at its grid x")

	var wall_mesh: MeshInstance3D = wall_tile.get_node("MeshInstance3D")
	var floor_mesh: MeshInstance3D = floor_tile.get_node("MeshInstance3D")
	var wall_box: BoxMesh = wall_mesh.mesh
	var floor_box: BoxMesh = floor_mesh.mesh
	assert_gt(wall_box.size.y, floor_box.size.y, "the wall tile's box is taller than the floor tile's box")

	assert_not_null(wall_tile.get_node("CollisionShape3D"), "each tile has a CollisionShape3D")


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


func test_translate_produces_exactly_the_expected_child_count() -> void:
	var parent: Node3D = add_child_autofree(Node3D.new())
	SectorGeometryTranslatorScript.translate(_fixture_blueprint(), parent)
	await wait_physics_frames(1)

	assert_eq(parent.get_child_count(), 7, "3 tiles + 4 structures produce exactly 7 top-level children")


func test_unsupported_tile_and_structure_kinds_are_skipped_without_crashing() -> void:
	var parent: Node3D = add_child_autofree(Node3D.new())
	var blueprint: Dictionary = _fixture_blueprint()
	blueprint["tiles"].append({"x": 9, "y": 9, "kind": "lava"})
	blueprint["structures"].append({"structure_id": "castle-1", "kind": "castle", "x": 1.0, "y": 1.0, "facing_degrees": 0.0})

	SectorGeometryTranslatorScript.translate(blueprint, parent)
	await wait_physics_frames(1)

	assert_eq(parent.get_child_count(), 7, "unsupported tile/structure entries are skipped, leaving only the 7 valid ones")
