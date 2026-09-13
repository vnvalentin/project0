extends GutTest
## Public-seam unit tests for Slice 016's starting town hub fixture
## (server/starting_town_hub_fixture.gd). Pure and stateless — exercises the
## static blueprint()/materialize() functions with plain Dictionaries, no live
## server process or scene tree. See
## docs/slices/016-starting-town-hub-fixture.md.

const StartingTownHubFixtureScript: Script = preload("res://server/starting_town_hub_fixture.gd")
const SectorBlueprintSchemaScript: Script = preload("res://shared/sector_blueprint_schema.gd")


func test_fixture_blueprint_passes_schema_validation() -> void:
	var result: Dictionary = SectorBlueprintSchemaScript.validate(StartingTownHubFixtureScript.blueprint())
	assert_eq(result["outcome"], SectorBlueprintSchemaScript.OUTCOME_VALID, "hub fixture must validate as OUTCOME_VALID (regression guard against future schema changes)")


func test_fixture_identity_fields() -> void:
	var blueprint: Dictionary = StartingTownHubFixtureScript.blueprint()
	assert_eq(blueprint["schema_version"], 3, "hub fixture is schema version 3 (organic vocabulary)")
	assert_eq(blueprint["sector_id"], StartingTownHubFixtureScript.SECTOR_ID, "hub fixture uses the reserved sector id")
	assert_eq(blueprint["sector_id"], "starting_town_hub", "reserved sector id literal is 'starting_town_hub'")
	assert_eq(blueprint["origin"], {"x": 0, "y": 0}, "hub fixture origin is {0, 0}")


func test_fixture_structure_kind_counts() -> void:
	var structures: Array = StartingTownHubFixtureScript.blueprint()["structures"]
	var counts: Dictionary = {"house": 0, "smithy": 0, "armor_shop": 0, "inn": 0, "church": 0, "item_shop": 0, "tavern": 0, "well": 0}
	for structure: Dictionary in structures:
		var kind: String = structure["kind"]
		counts[kind] = int(counts.get(kind, 0)) + 1
	assert_eq(counts["house"], 10, "hub fixture has exactly 10 houses (the 10-player pool)")
	assert_eq(counts["smithy"], 1, "hub fixture has exactly 1 smithy")
	assert_eq(counts["armor_shop"], 1, "hub fixture has exactly 1 armor shop")
	assert_eq(counts["inn"], 1, "hub fixture has exactly 1 inn")
	assert_eq(counts["church"], 1, "hub fixture has exactly 1 church")
	assert_eq(counts["item_shop"], 1, "hub fixture has exactly 1 item shop")
	assert_eq(counts["tavern"], 1, "hub fixture has exactly 1 tavern")
	assert_eq(counts["well"], 1, "hub fixture has exactly 1 well")
	assert_eq(structures.size(), 17, "hub fixture has exactly 17 structures total")


func test_fixture_uses_the_organic_v3_vocabulary() -> void:
	var blueprint: Dictionary = StartingTownHubFixtureScript.blueprint()
	assert_eq(blueprint["schema_version"], 3, "the enriched hub is schema v3")
	var kinds_present: Dictionary = {}
	for tile: Dictionary in (blueprint["tiles"] as Array):
		kinds_present[tile["kind"]] = true
	for organic_kind: String in ["gate", "plaza", "path", "grass", "water"]:
		assert_true(kinds_present.has(organic_kind), "the hub uses the organic tile kind '%s'" % organic_kind)
	assert_true(kinds_present.has("wall"), "the hub still has walls")
	assert_true(kinds_present.has("floor"), "the hub still has floor")
	assert_false(kinds_present.has("corridor"), "the enriched hub replaced corridors with paths/plaza")


func test_fixture_structure_ids_are_unique() -> void:
	var structures: Array = StartingTownHubFixtureScript.blueprint()["structures"]
	var seen: Dictionary = {}
	for structure: Dictionary in structures:
		var structure_id: String = structure["structure_id"]
		assert_false(seen.has(structure_id), "structure_id '%s' must be unique" % structure_id)
		seen[structure_id] = true
	assert_eq(seen.size(), structures.size(), "every structure has a distinct structure_id")


func test_fixture_structure_positions_are_unique() -> void:
	var structures: Array = StartingTownHubFixtureScript.blueprint()["structures"]
	var seen: Dictionary = {}
	for structure: Dictionary in structures:
		var key: String = "%d,%d" % [int(structure["x"]), int(structure["y"])]
		assert_false(seen.has(key), "structure position (%s) must be unique" % key)
		seen[key] = true
	assert_eq(seen.size(), structures.size(), "every structure occupies a distinct (x, y) cell")


func test_fixture_spawn_points_are_all_outside_the_town_wall() -> void:
	# Monsters must spawn outside the town boundary (the octagon outline, radius
	# 16), never inside it (user caveat).
	var blueprint: Dictionary = StartingTownHubFixtureScript.blueprint()
	assert_true(blueprint.has("spawn_points"), "the hub fixture declares monster spawn points")
	var spawn_points: Array = blueprint["spawn_points"]
	assert_gt(spawn_points.size(), 0, "there is at least one spawn point")
	for spawn_point: Dictionary in spawn_points:
		var outside: bool = absi(int(spawn_point["x"])) > 16 or absi(int(spawn_point["y"])) > 16
		assert_true(outside, "spawn point %s at (%d,%d) is outside the town outline" % [spawn_point["spawn_id"], int(spawn_point["x"]), int(spawn_point["y"])])


func test_materialize_accepts_the_real_fixture() -> void:
	var materialization: Dictionary = StartingTownHubFixtureScript.materialize(StartingTownHubFixtureScript.blueprint())
	assert_true(materialization["ok"], "materialize() reports ok for the real fixture")
	assert_false((materialization["blueprint"] as Dictionary).is_empty(), "materialize() returns a non-empty validated blueprint on success")
	assert_eq(materialization["outcome"], SectorBlueprintSchemaScript.OUTCOME_VALID, "materialize() surfaces the OUTCOME_VALID outcome")


func test_materialize_fails_closed_on_corrupted_fixture() -> void:
	# Fail-closed decision seam: a fixture that fails its own schema must yield
	# ok == false and an empty blueprint so the server refuses to start. This
	# unit-tests the branch server_main._start_server() acts on without booting
	# a live server (full live-boot quit(1) behavior is a known coverage gap,
	# noted in the slice doc).
	var corrupted: Dictionary = StartingTownHubFixtureScript.blueprint()
	(corrupted["structures"] as Array)[0]["kind"] = "not_a_real_kind"
	var materialization: Dictionary = StartingTownHubFixtureScript.materialize(corrupted)
	assert_false(materialization["ok"], "materialize() reports not-ok for a corrupted fixture")
	assert_true((materialization["blueprint"] as Dictionary).is_empty(), "materialize() returns an empty blueprint when validation fails (fail closed)")
	assert_eq(materialization["outcome"], SectorBlueprintSchemaScript.OUTCOME_UNSUPPORTED_KIND, "materialize() surfaces the specific failure outcome")
