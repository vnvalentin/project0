extends GutTest
## Public-seam unit tests for Slice 015's pure sector geometry lookup helper
## (shared/sector_geometry_lookup.gd). Pure and stateless — plain
## Dictionary/String fixtures only, no scene tree/Node instancing. See
## docs/slices/015-sector-geometry-translation.md.

const SectorGeometryLookupScript: Script = preload("res://shared/sector_geometry_lookup.gd")
const SectorBlueprintSchemaScript: Script = preload("res://shared/sector_blueprint_schema.gd")


func test_floor_and_corridor_dimensions_are_thin_slabs() -> void:
	var floor_dimensions: Vector3 = SectorGeometryLookupScript.tile_dimensions("floor")
	var corridor_dimensions: Vector3 = SectorGeometryLookupScript.tile_dimensions("corridor")

	assert_gt(floor_dimensions.x, 0.0, "floor has a positive footprint")
	assert_eq(floor_dimensions, corridor_dimensions, "floor and corridor share the same placeholder dimensions")


func test_wall_dimensions_are_taller_than_floor_and_corridor() -> void:
	var wall_dimensions: Vector3 = SectorGeometryLookupScript.tile_dimensions("wall")
	var floor_dimensions: Vector3 = SectorGeometryLookupScript.tile_dimensions("floor")

	assert_gt(wall_dimensions.y, floor_dimensions.y, "wall tiles must read as taller than floor tiles per ticket 02")


func test_unsupported_tile_kind_returns_zero_vector() -> void:
	var dimensions: Vector3 = SectorGeometryLookupScript.tile_dimensions("lava")
	assert_eq(dimensions, Vector3.ZERO, "an unsupported tile kind returns Vector3.ZERO as an explicit failure marker")


func test_structure_scene_paths_resolve_to_existing_files() -> void:
	for kind: String in ["house", "smithy", "armor_shop", "inn"]:
		var scene_path: String = SectorGeometryLookupScript.structure_scene_path(kind)
		assert_false(scene_path.is_empty(), "structure kind '%s' resolves to a non-empty scene path" % kind)
		assert_true(ResourceLoader.exists(scene_path), "structure kind '%s' scene path '%s' exists on disk" % [kind, scene_path])


func test_unsupported_structure_kind_returns_empty_string() -> void:
	var scene_path: String = SectorGeometryLookupScript.structure_scene_path("castle")
	assert_eq(scene_path, "", "an unsupported structure kind returns an empty string as an explicit failure marker")


func test_supported_tile_kinds_match_schema_exactly() -> void:
	var lookup_kinds: PackedStringArray = SectorGeometryLookupScript.supported_tile_kinds()
	var schema_kinds: PackedStringArray = SectorBlueprintSchemaScript.SUPPORTED_TILE_KINDS

	assert_eq(lookup_kinds.size(), schema_kinds.size(), "lookup and schema agree on the number of supported tile kinds")
	for kind: String in schema_kinds:
		assert_true(lookup_kinds.has(kind), "lookup supports schema tile kind '%s'" % kind)


func test_supported_structure_kinds_match_schema_exactly() -> void:
	var lookup_kinds: PackedStringArray = SectorGeometryLookupScript.supported_structure_kinds()
	var schema_kinds: PackedStringArray = SectorBlueprintSchemaScript.SUPPORTED_STRUCTURE_KINDS

	assert_eq(lookup_kinds.size(), schema_kinds.size(), "lookup and schema agree on the number of supported structure kinds")
	for kind: String in schema_kinds:
		assert_true(lookup_kinds.has(kind), "lookup supports schema structure kind '%s'" % kind)
