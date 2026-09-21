extends GutTest
## Public-seam unit tests for Slice 014's version-2-capable sector blueprint
## validator (shared/sector_blueprint_schema.gd). Pure and stateless — builds
## Dictionary/Array fixtures directly and calls SectorBlueprintSchema.validate()
## with no HTTP/service/JSON-string layer involved. See
## docs/slices/014-sector-blueprint-schema-v2-structures.md.

const SectorBlueprintSchemaScript: Script = preload("res://shared/sector_blueprint_schema.gd")


func _base_v1(schema_version: int = 1) -> Dictionary:
	return {
		"schema_version": schema_version,
		"sector_id": "sector-0-0",
		"origin": {"x": 0, "y": 0},
		"tiles": [
			{"x": 0, "y": 0, "kind": "floor"},
		],
	}


func _valid_structure(structure_id: String = "house-1") -> Dictionary:
	return {
		"structure_id": structure_id,
		"kind": "house",
		"x": 3,
		"y": 4,
		"facing_degrees": 90.0,
	}


func _valid_spawn_point(spawn_id: String = "spawn-1") -> Dictionary:
	return {"spawn_id": spawn_id, "x": 5, "y": 5}


func test_valid_v2_payload_with_structures_and_spawn_points() -> void:
	var data: Dictionary = _base_v1(2)
	data["structures"] = [
		_valid_structure("house-1"),
		{"structure_id": "smithy-1", "kind": "smithy", "x": -10, "y": 10, "facing_degrees": 0.0},
	]
	data["spawn_points"] = [_valid_spawn_point("spawn-1"), _valid_spawn_point("spawn-2")]

	var result: Dictionary = SectorBlueprintSchemaScript.validate(data)
	assert_eq(result["outcome"], SectorBlueprintSchemaScript.OUTCOME_VALID, "valid v2 payload with structures and spawn_points validates")
	assert_not_null(result["blueprint"], "valid v2 payload returns a non-null blueprint")
	assert_eq((result["blueprint"]["structures"] as Array).size(), 2, "validated blueprint retains both structures")
	assert_eq((result["blueprint"]["spawn_points"] as Array).size(), 2, "validated blueprint retains both spawn points")


func test_valid_v1_payload_without_structures_or_spawn_points_stays_valid() -> void:
	var data: Dictionary = _base_v1(1)
	var result: Dictionary = SectorBlueprintSchemaScript.validate(data)
	assert_eq(result["outcome"], SectorBlueprintSchemaScript.OUTCOME_VALID, "v1 payload with no structures/spawn_points keys still validates (backward compatibility)")


func test_v2_payload_with_empty_structures_and_spawn_points_is_valid() -> void:
	var data: Dictionary = _base_v1(2)
	data["structures"] = []
	data["spawn_points"] = []
	var result: Dictionary = SectorBlueprintSchemaScript.validate(data)
	assert_eq(result["outcome"], SectorBlueprintSchemaScript.OUTCOME_VALID, "v2 payload with empty structures/spawn_points arrays is valid")


## Feature #710 / Epic #713 / Experiment #717: schema v4 requires parametric
## footprint/roof_style fields on `house`-kind structures only.
func _house_structure_v4(structure_id: String, footprint_width: float, footprint_depth: float, roof_style: String) -> Dictionary:
	return {
		"structure_id": structure_id,
		"kind": "house",
		"x": 3,
		"y": 4,
		"facing_degrees": 90.0,
		"footprint_width": footprint_width,
		"footprint_depth": footprint_depth,
		"roof_style": roof_style,
	}


func test_v4_house_accepts_three_distinct_footprint_style_combinations() -> void:
	var data: Dictionary = _base_v1(4)
	data["structures"] = [
		_house_structure_v4("house-1", 3.0, 3.0, "flat_roof"),
		_house_structure_v4("house-2", 6.0, 8.0, "gable_roof"),
		_house_structure_v4("house-3", 12.0, 12.0, "hip_roof"),
	]
	var result: Dictionary = SectorBlueprintSchemaScript.validate(data)
	assert_eq(result["outcome"], SectorBlueprintSchemaScript.OUTCOME_VALID, "3 distinct valid (footprint, roof_style) combinations validate")
	assert_eq((result["blueprint"]["structures"] as Array).size(), 3, "all 3 house entries are retained")
	assert_eq(result["blueprint"]["structures"][1]["roof_style"], "gable_roof", "roof_style is preserved unchanged")


func test_v4_house_footprint_below_minimum_is_out_of_bounds() -> void:
	var data: Dictionary = _base_v1(4)
	data["structures"] = [_house_structure_v4("house-1", 0.0, 6.0, "gable_roof")]
	var result: Dictionary = SectorBlueprintSchemaScript.validate(data)
	assert_eq(result["outcome"], SectorBlueprintSchemaScript.OUTCOME_OUT_OF_BOUNDS, "footprint_width below the minimum is OUTCOME_OUT_OF_BOUNDS")


func test_v4_house_unsupported_roof_style_is_unsupported_kind() -> void:
	var data: Dictionary = _base_v1(4)
	data["structures"] = [_house_structure_v4("house-1", 6.0, 6.0, "dome")]
	var result: Dictionary = SectorBlueprintSchemaScript.validate(data)
	assert_eq(result["outcome"], SectorBlueprintSchemaScript.OUTCOME_UNSUPPORTED_KIND, "an unsupported roof_style is OUTCOME_UNSUPPORTED_KIND")


func test_v4_house_missing_footprint_fields_is_incomplete() -> void:
	var data: Dictionary = _base_v1(4)
	data["structures"] = [_valid_structure("house-1")]
	var result: Dictionary = SectorBlueprintSchemaScript.validate(data)
	assert_eq(result["outcome"], SectorBlueprintSchemaScript.OUTCOME_INCOMPLETE, "a v4 house entry missing footprint/roof_style fields is OUTCOME_INCOMPLETE")


func test_v3_house_without_footprint_fields_stays_valid_backward_compatible() -> void:
	var data: Dictionary = _base_v1(3)
	data["structures"] = [_valid_structure("house-1")]
	var result: Dictionary = SectorBlueprintSchemaScript.validate(data)
	assert_eq(result["outcome"], SectorBlueprintSchemaScript.OUTCOME_VALID, "a v3 house entry without footprint/roof_style fields stays valid (backward compatibility)")


func test_v4_non_house_structure_does_not_require_footprint_fields() -> void:
	var data: Dictionary = _base_v1(4)
	data["structures"] = [{"structure_id": "smithy-1", "kind": "smithy", "x": -10, "y": 10, "facing_degrees": 0.0}]
	var result: Dictionary = SectorBlueprintSchemaScript.validate(data)
	assert_eq(result["outcome"], SectorBlueprintSchemaScript.OUTCOME_VALID, "a v4 non-house structure does not require footprint/roof_style fields")


func test_structure_missing_required_field_is_incomplete() -> void:
	var data: Dictionary = _base_v1(2)
	var bad_structure: Dictionary = _valid_structure()
	bad_structure.erase("kind")
	data["structures"] = [bad_structure]
	var result: Dictionary = SectorBlueprintSchemaScript.validate(data)
	assert_eq(result["outcome"], SectorBlueprintSchemaScript.OUTCOME_INCOMPLETE, "structure missing kind is OUTCOME_INCOMPLETE")


func test_structure_wrong_type_field_is_incomplete() -> void:
	var data: Dictionary = _base_v1(2)
	var bad_structure: Dictionary = _valid_structure()
	bad_structure["x"] = "not a number"
	data["structures"] = [bad_structure]
	var result: Dictionary = SectorBlueprintSchemaScript.validate(data)
	assert_eq(result["outcome"], SectorBlueprintSchemaScript.OUTCOME_INCOMPLETE, "structure with wrong-typed x is OUTCOME_INCOMPLETE")


func test_structure_unsupported_kind_is_rejected() -> void:
	var data: Dictionary = _base_v1(2)
	var bad_structure: Dictionary = _valid_structure()
	bad_structure["kind"] = "castle"
	data["structures"] = [bad_structure]
	var result: Dictionary = SectorBlueprintSchemaScript.validate(data)
	assert_eq(result["outcome"], SectorBlueprintSchemaScript.OUTCOME_UNSUPPORTED_KIND, "structure kind 'castle' is OUTCOME_UNSUPPORTED_KIND")


func test_structure_out_of_bounds_coordinate_is_rejected() -> void:
	var data: Dictionary = _base_v1(2)
	var bad_structure: Dictionary = _valid_structure()
	bad_structure["x"] = 999
	data["structures"] = [bad_structure]
	var result: Dictionary = SectorBlueprintSchemaScript.validate(data)
	assert_eq(result["outcome"], SectorBlueprintSchemaScript.OUTCOME_OUT_OF_BOUNDS, "structure x beyond MAX_COORDINATE_ABS is OUTCOME_OUT_OF_BOUNDS")


func test_structure_out_of_bounds_facing_degrees_is_rejected() -> void:
	var data: Dictionary = _base_v1(2)
	var bad_structure: Dictionary = _valid_structure()
	bad_structure["facing_degrees"] = 360.0
	data["structures"] = [bad_structure]
	var result: Dictionary = SectorBlueprintSchemaScript.validate(data)
	assert_eq(result["outcome"], SectorBlueprintSchemaScript.OUTCOME_OUT_OF_BOUNDS, "facing_degrees == 360 is out of the [0, 360) bound")

	var negative_structure: Dictionary = _valid_structure()
	negative_structure["facing_degrees"] = -1.0
	data["structures"] = [negative_structure]
	var negative_result: Dictionary = SectorBlueprintSchemaScript.validate(data)
	assert_eq(negative_result["outcome"], SectorBlueprintSchemaScript.OUTCOME_OUT_OF_BOUNDS, "negative facing_degrees is out of the [0, 360) bound")


func test_duplicate_structure_id_is_rejected() -> void:
	var data: Dictionary = _base_v1(2)
	data["structures"] = [_valid_structure("house-1"), _valid_structure("house-1")]
	var result: Dictionary = SectorBlueprintSchemaScript.validate(data)
	assert_eq(result["outcome"], SectorBlueprintSchemaScript.OUTCOME_INCOMPLETE, "duplicate structure_id within one blueprint is OUTCOME_INCOMPLETE")


func test_spawn_point_missing_or_invalid_field_is_incomplete() -> void:
	var data: Dictionary = _base_v1(2)
	var bad_spawn: Dictionary = _valid_spawn_point()
	bad_spawn.erase("spawn_id")
	data["spawn_points"] = [bad_spawn]
	var result: Dictionary = SectorBlueprintSchemaScript.validate(data)
	assert_eq(result["outcome"], SectorBlueprintSchemaScript.OUTCOME_INCOMPLETE, "spawn point missing spawn_id is OUTCOME_INCOMPLETE")


func test_spawn_point_out_of_bounds_coordinate_is_rejected() -> void:
	var data: Dictionary = _base_v1(2)
	var bad_spawn: Dictionary = _valid_spawn_point()
	bad_spawn["y"] = -999
	data["spawn_points"] = [bad_spawn]
	var result: Dictionary = SectorBlueprintSchemaScript.validate(data)
	assert_eq(result["outcome"], SectorBlueprintSchemaScript.OUTCOME_OUT_OF_BOUNDS, "spawn point y beyond MAX_COORDINATE_ABS is OUTCOME_OUT_OF_BOUNDS")


func test_spawn_points_exceeding_max_count_is_rejected() -> void:
	var data: Dictionary = _base_v1(2)
	var spawn_points: Array = []
	for i in SectorBlueprintSchemaScript.MAX_SPAWN_POINT_COUNT + 1:
		spawn_points.append(_valid_spawn_point("spawn-%d" % i))
	data["spawn_points"] = spawn_points
	var result: Dictionary = SectorBlueprintSchemaScript.validate(data)
	assert_eq(result["outcome"], SectorBlueprintSchemaScript.OUTCOME_INCOMPLETE, "spawn_points beyond MAX_SPAWN_POINT_COUNT is OUTCOME_INCOMPLETE")


func test_spawn_points_at_exact_max_count_is_valid() -> void:
	var data: Dictionary = _base_v1(2)
	var spawn_points: Array = []
	for i in SectorBlueprintSchemaScript.MAX_SPAWN_POINT_COUNT:
		spawn_points.append(_valid_spawn_point("spawn-%d" % i))
	data["spawn_points"] = spawn_points
	var result: Dictionary = SectorBlueprintSchemaScript.validate(data)
	assert_eq(result["outcome"], SectorBlueprintSchemaScript.OUTCOME_VALID, "spawn_points exactly at MAX_SPAWN_POINT_COUNT is valid")


func test_wrong_schema_version_still_rejected() -> void:
	var data: Dictionary = _base_v1(99)
	var result: Dictionary = SectorBlueprintSchemaScript.validate(data)
	assert_eq(result["outcome"], SectorBlueprintSchemaScript.OUTCOME_WRONG_SCHEMA_VERSION, "schema_version 99 remains OUTCOME_WRONG_SCHEMA_VERSION")


func test_structures_wrong_top_level_type_is_incomplete() -> void:
	var data: Dictionary = _base_v1(2)
	data["structures"] = "not an array"
	var result: Dictionary = SectorBlueprintSchemaScript.validate(data)
	assert_eq(result["outcome"], SectorBlueprintSchemaScript.OUTCOME_INCOMPLETE, "non-array structures field is OUTCOME_INCOMPLETE")


func test_spawn_points_wrong_top_level_type_is_incomplete() -> void:
	var data: Dictionary = _base_v1(2)
	data["spawn_points"] = "not an array"
	var result: Dictionary = SectorBlueprintSchemaScript.validate(data)
	assert_eq(result["outcome"], SectorBlueprintSchemaScript.OUTCOME_INCOMPLETE, "non-array spawn_points field is OUTCOME_INCOMPLETE")
