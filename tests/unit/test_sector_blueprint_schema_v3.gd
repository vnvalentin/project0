extends GutTest
## Public-seam unit tests for Slice 025's schema v3 organic vocabulary
## (shared/sector_blueprint_schema.gd): the new tile kinds
## (path/plaza/gate/water/grass) and structure kinds
## (church/item_shop/tavern/well), version-gated to schema v3 while v1/v2 keep
## their original vocabulary. Pure and stateless. See
## docs/slices/025-organic-vocabulary.md.

const SectorBlueprintSchemaScript: Script = preload("res://shared/sector_blueprint_schema.gd")


func _base(schema_version: int, tile_kind: String = "floor") -> Dictionary:
	return {
		"schema_version": schema_version,
		"sector_id": "sector-organic",
		"origin": {"x": 0, "y": 0},
		"tiles": [{"x": 0, "y": 0, "kind": tile_kind}],
	}


func test_v3_is_a_supported_schema_version() -> void:
	var result: Dictionary = SectorBlueprintSchemaScript.validate(_base(3))
	assert_eq(result["outcome"], SectorBlueprintSchemaScript.OUTCOME_VALID, "a plain v3 payload validates")


func test_each_organic_tile_kind_is_valid_in_v3() -> void:
	for kind: String in ["path", "plaza", "gate", "water", "grass"]:
		var result: Dictionary = SectorBlueprintSchemaScript.validate(_base(3, kind))
		assert_eq(result["outcome"], SectorBlueprintSchemaScript.OUTCOME_VALID, "organic tile kind '%s' validates under v3" % kind)


func test_each_organic_structure_kind_is_valid_in_v3() -> void:
	for kind: String in ["church", "item_shop", "tavern", "well", "npc_house", "village_hall"]:
		var data: Dictionary = _base(3)
		data["structures"] = [{"structure_id": "s1", "kind": kind, "x": 1, "y": 1, "facing_degrees": 0.0}]
		var result: Dictionary = SectorBlueprintSchemaScript.validate(data)
		assert_eq(result["outcome"], SectorBlueprintSchemaScript.OUTCOME_VALID, "organic structure kind '%s' validates under v3" % kind)


func test_organic_tile_kind_rejected_below_v3() -> void:
	var result: Dictionary = SectorBlueprintSchemaScript.validate(_base(2, "water"))
	assert_eq(result["outcome"], SectorBlueprintSchemaScript.OUTCOME_UNSUPPORTED_KIND, "an organic tile kind in a v2 blueprint is rejected (version gate)")


func test_organic_structure_kind_rejected_below_v3() -> void:
	var data: Dictionary = _base(2)
	data["structures"] = [{"structure_id": "s1", "kind": "church", "x": 1, "y": 1, "facing_degrees": 0.0}]
	var result: Dictionary = SectorBlueprintSchemaScript.validate(data)
	assert_eq(result["outcome"], SectorBlueprintSchemaScript.OUTCOME_UNSUPPORTED_KIND, "an organic structure kind in a v2 blueprint is rejected (version gate)")


func test_base_vocabulary_still_valid_in_v1_and_v2() -> void:
	# Backward compatibility: the original tile/structure kinds keep validating.
	assert_eq(SectorBlueprintSchemaScript.validate(_base(1, "floor"))["outcome"], SectorBlueprintSchemaScript.OUTCOME_VALID, "v1 floor still valid")
	assert_eq(SectorBlueprintSchemaScript.validate(_base(2, "corridor"))["outcome"], SectorBlueprintSchemaScript.OUTCOME_VALID, "v2 corridor still valid")
	var v2_struct: Dictionary = _base(2)
	v2_struct["structures"] = [{"structure_id": "h1", "kind": "house", "x": 1, "y": 1, "facing_degrees": 0.0}]
	assert_eq(SectorBlueprintSchemaScript.validate(v2_struct)["outcome"], SectorBlueprintSchemaScript.OUTCOME_VALID, "v2 house structure still valid")


func test_unknown_tile_kind_still_rejected_in_v3() -> void:
	var result: Dictionary = SectorBlueprintSchemaScript.validate(_base(3, "lava"))
	assert_eq(result["outcome"], SectorBlueprintSchemaScript.OUTCOME_UNSUPPORTED_KIND, "a genuinely unknown tile kind is still rejected under v3")


func test_organic_tiles_and_structures_together_in_v3() -> void:
	var data: Dictionary = _base(3, "plaza")
	(data["tiles"] as Array).append({"x": 1, "y": 0, "kind": "water"})
	(data["tiles"] as Array).append({"x": 0, "y": 1, "kind": "grass"})
	data["structures"] = [
		{"structure_id": "church_01", "kind": "church", "x": 2, "y": 2, "facing_degrees": 90.0},
		{"structure_id": "well_01", "kind": "well", "x": -2, "y": -2, "facing_degrees": 0.0},
	]
	var result: Dictionary = SectorBlueprintSchemaScript.validate(data)
	assert_eq(result["outcome"], SectorBlueprintSchemaScript.OUTCOME_VALID, "a mixed v3 payload with organic tiles and structures validates")
