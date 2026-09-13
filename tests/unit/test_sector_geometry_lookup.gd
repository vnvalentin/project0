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


func test_wall_is_solid_and_ground_kinds_are_not() -> void:
	assert_true(SectorGeometryLookupScript.tile_is_solid("wall"), "wall tiles are solid (get merged collision)")
	assert_false(SectorGeometryLookupScript.tile_is_solid("floor"), "floor tiles are visual ground, not solid")
	assert_false(SectorGeometryLookupScript.tile_is_solid("corridor"), "corridor tiles are visual ground, not solid")
	assert_false(SectorGeometryLookupScript.tile_is_solid("lava"), "an unsupported tile kind is not solid")


func test_organic_tile_kinds_are_visual_ground_slabs() -> void:
	var floor_dimensions: Vector3 = SectorGeometryLookupScript.tile_dimensions("floor")
	for organic_kind: String in ["path", "plaza", "gate", "water", "grass"]:
		var dimensions: Vector3 = SectorGeometryLookupScript.tile_dimensions(organic_kind)
		assert_ne(dimensions, Vector3.ZERO, "organic tile kind '%s' has real dimensions" % organic_kind)
		assert_eq(dimensions, floor_dimensions, "organic ground kind '%s' shares the flat floor slab dimensions" % organic_kind)
		assert_false(SectorGeometryLookupScript.tile_is_solid(organic_kind), "organic ground kind '%s' is not solid (no collider)" % organic_kind)


func test_structure_scene_paths_resolve_to_existing_files() -> void:
	for kind: String in SectorBlueprintSchemaScript.SUPPORTED_STRUCTURE_KINDS:
		var scene_path: String = SectorGeometryLookupScript.structure_scene_path(kind)
		assert_false(scene_path.is_empty(), "structure kind '%s' resolves to a non-empty scene path" % kind)
		assert_true(ResourceLoader.exists(scene_path), "structure kind '%s' scene path '%s' exists on disk" % [kind, scene_path])


func test_structure_footprints_are_defined_for_every_kind() -> void:
	for kind: String in SectorBlueprintSchemaScript.SUPPORTED_STRUCTURE_KINDS:
		var footprint: Vector2i = SectorGeometryLookupScript.structure_footprint(kind)
		assert_true(footprint.x >= 0 and footprint.y >= 0, "structure kind '%s' has a non-negative footprint half-extent" % kind)
	assert_eq(SectorGeometryLookupScript.structure_footprint("house"), Vector2i(1, 1), "a house is a 3x3 footprint (half-extent 1)")
	assert_eq(SectorGeometryLookupScript.structure_footprint("village_hall"), Vector2i(2, 3), "the village hall is a 5x7 footprint")
	assert_eq(SectorGeometryLookupScript.structure_footprint("unknown_kind"), Vector2i.ZERO, "an unknown structure kind has no footprint")


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
