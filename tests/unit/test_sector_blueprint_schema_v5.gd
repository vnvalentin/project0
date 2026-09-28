extends GutTest

const Schema: Script = preload("res://shared/sector_blueprint_schema.gd")
const Placement: Script = preload("res://shared/sector_detail_placement.gd")


func test_version_five_accepts_bounded_detail_at_negative_sector_ingress() -> void:
	var blueprint: Dictionary = {
		"schema_version": 5,
		"sector_id": "sector--1--1",
		"detail_origin": {"x": 439, "y": 409},
		"origin": {"x": 1, "y": 0},
		"tiles": [{"x": 0, "y": 0, "kind": "floor"}, {"x": 1, "y": 0, "kind": "floor"}],
	}
	assert_eq(Schema.validate_generated(blueprint)["outcome"], "valid")


func test_placement_rejects_missing_nonfinite_fractional_and_out_of_sector_metadata() -> void:
	for invalid: Variant in [null, true, {}, {"x": -1, "y": 0}, {"x": 440, "y": 0}, {"x": 0, "y": 440}, {"x": 0.5, "y": 0}, {"x": INF, "y": 0}, {"x": NAN, "y": 0}, {"x": 0, "y": 0, "z": 0}]:
		var blueprint: Dictionary = _blueprint()
		blueprint["detail_origin"] = invalid
		assert_ne(Schema.validate(blueprint)["outcome"], "valid")
	var missing: Dictionary = _blueprint()
	missing.erase("detail_origin")
	assert_ne(Schema.validate(missing)["outcome"], "valid")


func test_gate_placement_is_pinned_to_actual_signed_sector() -> void:
	assert_eq(Placement.select("sector--1--1", Vector3(-0.2, 1, -30.56667)), {
		"detail_origin": {"x": 439, "y": 409}, "origin": {"x": 1, "y": 0},
	})
	assert_eq(Placement.select("sector-0--1", Vector3(0.2, 1, -30.56667)), {
		"detail_origin": {"x": 0, "y": 409}, "origin": {"x": 0, "y": 0},
	})
	assert_eq(Placement.select("sector--1-1", Vector3(-440, 7, 440)), {
		"detail_origin": {"x": 0, "y": 0}, "origin": {"x": 0, "y": 0},
	})
	assert_eq(Placement.select("sector-0-0", Vector3(-0.2, 1, -30.56667)), {})
	assert_eq(Placement.select("sector-0-0", Vector3(NAN, 0, 0)), {})
	assert_eq(Placement.select("starting_town_hub", Vector3.ZERO), {})


func test_shared_round_trip_preserves_world_height_and_does_not_mutate_blueprint() -> void:
	var blueprint: Dictionary = _blueprint()
	var before: String = JSON.stringify(blueprint)
	assert_eq(Placement.world_offset(blueprint), Vector3(-1, 0, -31))
	var world: Vector3 = Vector3(-0.2, 7.25, -30.56667)
	var detail: Vector3 = Placement.to_detail(blueprint, world)
	assert_almost_eq(detail.x, 0.8, 0.0001)
	assert_almost_eq(detail.z, 0.43333, 0.0001)
	assert_eq(detail.y, 7.25)
	assert_lt(Placement.to_world(blueprint, detail).distance_to(world), 0.0001)
	assert_eq(JSON.stringify(blueprint), before)


func test_legacy_versions_keep_grid_offset_and_ignore_legacy_origin_for_placement() -> void:
	for version: int in [1, 2, 3, 4]:
		var blueprint: Dictionary = _blueprint()
		blueprint["schema_version"] = version
		blueprint.erase("detail_origin")
		blueprint["origin"] = {"x": 12, "y": -12}
		assert_eq(Schema.validate_generated(blueprint)["outcome"], "valid")
		assert_eq(Placement.world_offset(blueprint), Vector3(-440, 0, -440))
		blueprint["detail_origin"] = {"x": 0, "y": 0}
		assert_ne(Schema.validate(blueprint)["outcome"], "valid")
	var town: Dictionary = {"schema_version": 3, "sector_id": "starting_town_hub"}
	assert_eq(Placement.world_offset(town), Vector3.ZERO)


func test_v5_rejects_reserved_or_noncanonical_sector_and_fractional_entry() -> void:
	for identity: String in ["starting_town_hub", "sector-01-0", "sector-2147483648-0", "invalid"]:
		var blueprint: Dictionary = _blueprint()
		blueprint["sector_id"] = identity
		assert_ne(Schema.validate(blueprint)["outcome"], "valid")
	var fractional: Dictionary = _blueprint()
	fractional["origin"]["x"] = 0.5
	assert_ne(Schema.validate(fractional)["outcome"], "valid")


func test_v5_does_not_expand_fine_tile_bounds() -> void:
	var blueprint: Dictionary = _blueprint()
	blueprint["tiles"][0]["x"] = 49
	assert_eq(Schema.validate(blueprint)["outcome"], "out_of_bounds")


func test_detail_contains_only_connected_cells_in_its_own_sector() -> void:
	var blueprint: Dictionary = _blueprint()
	blueprint["tiles"].append({"x": -3, "y": 0, "kind": "floor"})
	var detail: RefCounted = Placement.new(blueprint)
	assert_true(detail.contains_world(Vector3(-0.2, 1, -30.56667)))
	assert_false(detail.contains_world(Vector3(0.2, 1, -30.56667)))
	assert_false(detail.contains_world(Vector3(-4, 1, -31)))
	assert_false(detail.contains_world(Vector3(-200, 1, -200)))
	assert_false(detail.contains_world(Vector3(INF, 1, -31)))
	assert_true(detail.contains_world(detail.navigation_target(Vector3(-0.2, 1, -30.56667))))


func test_sector_edge_clips_ground_without_granting_neighbor() -> void:
	assert_eq(Placement.clip_rectangle(_blueprint(), Rect2(0.5, -0.5, 1, 1)), Rect2(0.5, -0.5, 0.5, 1))
	assert_false(Placement.clip_rectangle(_blueprint(), Rect2(1.5, -0.5, 1, 1)).has_area())
	var legacy: Dictionary = _blueprint()
	legacy["schema_version"] = 1
	legacy.erase("detail_origin")
	assert_eq(Placement.clip_rectangle(legacy, Rect2(0.5, -0.5, 1, 1)), Rect2(0.5, -0.5, 1, 1))


func test_actor_clearance_rejects_neighboring_solid_and_blocked_entry() -> void:
	var blueprint: Dictionary = _blueprint()
	blueprint["tiles"].append({"x": 0, "y": -1, "kind": "wall"})
	var detail: RefCounted = Placement.new(blueprint)
	assert_true(detail.contains_world(Vector3(-1, 1, -31)))
	assert_false(detail.contains_world(Vector3(-1, 1, -31.2)))
	blueprint["tiles"][1]["kind"] = "wall"
	var blocked: RefCounted = Placement.new(blueprint)
	assert_false(blocked.contains_world(Vector3(-0.2, 1, -30.56667)))


func test_v5_rejects_fractional_nonfinite_and_duplicate_tile_cells() -> void:
	for coordinate: Variant in [0.25, NAN, INF]:
		var blueprint: Dictionary = _blueprint()
		blueprint["tiles"][0]["x"] = coordinate
		assert_ne(Schema.validate(blueprint)["outcome"], "valid")
	var repeated: Dictionary = _blueprint()
	repeated["tiles"].append(repeated["tiles"][0].duplicate())
	assert_ne(Schema.validate(repeated)["outcome"], "valid")


func _blueprint() -> Dictionary:
	return {
		"schema_version": 5, "sector_id": "sector--1--1",
		"detail_origin": {"x": 439, "y": 409}, "origin": {"x": 1, "y": 0},
		"tiles": [{"x": 0, "y": 0, "kind": "floor"}, {"x": 1, "y": 0, "kind": "floor"}],
	}
