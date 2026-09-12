extends GutTest
## Public-seam integration test for Slice 017's client-side blueprint
## replication render path (NetworkClient.render_sector_blueprint). Runs the
## static re-validate-then-translate seam against the real starting town hub
## fixture inside a real SceneTree/Node3D and asserts the expected geometry is
## produced, plus that an invalid payload renders nothing (fail closed at the
## client boundary). Does not stand up a live ENet peer — the RPC entry point
## is a thin wrapper over this tested static seam. See
## docs/slices/017-blueprint-replication.md.

const NetworkClientScript: Script = preload("res://client/network_client.gd")
const StartingTownHubFixtureScript: Script = preload("res://server/starting_town_hub_fixture.gd")
const SectorBlueprintSchemaScript: Script = preload("res://shared/sector_blueprint_schema.gd")


func test_valid_hub_blueprint_renders_all_tiles_and_structures() -> void:
	var parent: Node3D = add_child_autofree(Node3D.new())
	var blueprint: Dictionary = StartingTownHubFixtureScript.blueprint()
	var expected_tiles: int = (blueprint["tiles"] as Array).size()
	var expected_structures: int = (blueprint["structures"] as Array).size()

	var result: Dictionary = NetworkClientScript.render_sector_blueprint(blueprint, parent)
	await wait_physics_frames(1)

	assert_eq(result["outcome"], SectorBlueprintSchemaScript.OUTCOME_VALID, "the real hub fixture re-validates as OUTCOME_VALID at the client boundary")
	assert_eq(result["tile_count"], expected_tiles, "reported tile count matches the fixture")
	assert_eq(result["structure_count"], expected_structures, "reported structure count matches the fixture")
	assert_eq(parent.get_child_count(), expected_tiles + expected_structures, "every tile and structure becomes one child of the SectorGeometry parent")


func test_hub_blueprint_produces_the_named_structure_nodes() -> void:
	var parent: Node3D = add_child_autofree(Node3D.new())
	NetworkClientScript.render_sector_blueprint(StartingTownHubFixtureScript.blueprint(), parent)
	await wait_physics_frames(1)

	# The translator names structure nodes "Structure_<structure_id>"; spot-check
	# one house and each shop so the fixture's identities survive translation.
	assert_not_null(parent.get_node_or_null("Structure_house_01"), "house_01 is rendered")
	assert_not_null(parent.get_node_or_null("Structure_smithy_01"), "the smithy is rendered")
	assert_not_null(parent.get_node_or_null("Structure_armor_shop_01"), "the armor shop is rendered")
	assert_not_null(parent.get_node_or_null("Structure_inn_01"), "the inn is rendered")


func test_invalid_blueprint_renders_nothing() -> void:
	var parent: Node3D = add_child_autofree(Node3D.new())
	# A structurally-broken payload (unsupported structure kind) must be
	# rejected at the client boundary and produce no geometry at all.
	var corrupted: Dictionary = StartingTownHubFixtureScript.blueprint()
	(corrupted["structures"] as Array)[0]["kind"] = "not_a_real_kind"

	var result: Dictionary = NetworkClientScript.render_sector_blueprint(corrupted, parent)
	await wait_physics_frames(1)

	assert_ne(result["outcome"], SectorBlueprintSchemaScript.OUTCOME_VALID, "a corrupted blueprint does not report OUTCOME_VALID")
	assert_eq(result["tile_count"], 0, "a rejected blueprint reports zero rendered tiles")
	assert_eq(result["structure_count"], 0, "a rejected blueprint reports zero rendered structures")
	assert_eq(parent.get_child_count(), 0, "a rejected blueprint renders no geometry (fail closed, never partial)")


func test_malformed_non_dictionary_shape_renders_nothing() -> void:
	var parent: Node3D = add_child_autofree(Node3D.new())
	# Missing required top-level fields (no schema_version/tiles) must also
	# fail closed rather than partially rendering whatever is present.
	var result: Dictionary = NetworkClientScript.render_sector_blueprint({"sector_id": "starting_town_hub"}, parent)
	await wait_physics_frames(1)

	assert_ne(result["outcome"], SectorBlueprintSchemaScript.OUTCOME_VALID, "a blueprint missing required fields is rejected")
	assert_eq(parent.get_child_count(), 0, "a malformed blueprint renders no geometry")
