extends GutTest
## Public-seam unit tests for the Imperial world-scale measurement contract
## (shared/world_scale.gd). Pure and stateless — constants + conversion math
## only, no scene tree/Node instancing. See
## docs/slices/036-world-scale-measurement-contract.md and
## docs/adr/0003-imperial-world-scale.md.

const WorldScaleScript: Script = preload("res://shared/world_scale.gd")


func test_scale_version_is_present_and_positive() -> void:
	assert_gt(WorldScaleScript.SCALE_VERSION, 0, "SCALE_VERSION is a positive integer so scale-derived data can be stamped")


func test_unit_label_is_yard() -> void:
	assert_eq(WorldScaleScript.UNIT_LABEL, "yard", "the Imperial world unit is the yard (ADR 0003)")


func test_one_world_unit_is_one_yard_is_three_feet() -> void:
	assert_eq(WorldScaleScript.FEET_PER_YARD, 3.0, "there are 3 feet per yard")
	assert_eq(WorldScaleScript.units_to_feet(1.0), 3.0, "one world unit (1 yard) is 3 feet")


func test_units_to_miles() -> void:
	assert_eq(WorldScaleScript.YARDS_PER_MILE, 1760.0, "there are 1760 yards in a mile")
	assert_eq(WorldScaleScript.units_to_miles(1760.0), 1.0, "1760 units (yards) is one mile")
	assert_eq(WorldScaleScript.units_to_miles(440.0), 0.25, "a 440-unit Sector edge is a quarter mile")


func test_miles_to_units() -> void:
	assert_eq(WorldScaleScript.miles_to_units(1.0), 1760.0, "one mile is 1760 units")
	assert_eq(WorldScaleScript.miles_to_units(0.25), 440.0, "a quarter mile is 440 units")


func test_miles_units_round_trip_is_identity() -> void:
	var round_tripped: float = WorldScaleScript.units_to_miles(WorldScaleScript.miles_to_units(0.3))
	assert_almost_eq(round_tripped, 0.3, 0.0001, "miles -> units -> miles round-trips within tolerance")


func test_tile_and_sector_edges_match_adr() -> void:
	assert_eq(WorldScaleScript.TILE_EDGE_UNITS, 1.0, "the fine Tile is one world unit (1 yard)")
	assert_eq(WorldScaleScript.SECTOR_EDGE_UNITS, 440.0, "the default Sector edge is 440 units")
	assert_eq(WorldScaleScript.units_to_miles(WorldScaleScript.SECTOR_EDGE_UNITS), 0.25, "the default Sector edge is a quarter mile")


func test_zero_distance_converts_to_zero() -> void:
	assert_eq(WorldScaleScript.units_to_feet(0.0), 0.0, "zero units is zero feet")
	assert_eq(WorldScaleScript.units_to_miles(0.0), 0.0, "zero units is zero miles")
