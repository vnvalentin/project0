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
const TRACE_PATH: String = "res://build/validation/issue-1001-geometry-assembly-trace.json"
const MATRIX_TRACE_PATH: String = "res://build/validation/issue-1001-blueprint-matrix.json"


func test_valid_hub_blueprint_renders_merged_geometry_and_all_structures() -> void:
	var parent: Node3D = add_child_autofree(Node3D.new())
	var blueprint: Dictionary = StartingTownHubFixtureScript.blueprint()
	var tiles: Array = blueprint["tiles"]
	var expected_structures: int = (blueprint["structures"] as Array).size()

	var wall_tiles: int = 0
	for tile: Dictionary in tiles:
		if tile["kind"] == "wall":
			wall_tiles += 1

	var result: Dictionary = NetworkClientScript.render_sector_blueprint(blueprint, parent)
	await wait_physics_frames(1)

	assert_eq(result["outcome"], SectorBlueprintSchemaScript.OUTCOME_VALID, "the real hub fixture re-validates as OUTCOME_VALID at the client boundary")
	assert_eq(result["tile_count"], tiles.size(), "reported tile count matches the fixture")
	assert_eq(result["structure_count"], expected_structures, "reported structure count matches the fixture")

	assert_not_null(parent.get_node_or_null("Ground_floor"), "floor tiles render as a merged ground mesh")
	assert_not_null(parent.get_node_or_null("Ground_path"), "path avenues render as a merged ground mesh")
	assert_not_null(parent.get_node_or_null("Ground_plaza"), "the central plaza renders as a merged ground mesh")
	assert_not_null(parent.get_node_or_null("Ground_gate"), "the southern gate renders as a merged ground mesh")
	assert_not_null(parent.get_node_or_null("Ground_grass"), "the grass ring renders as a merged ground mesh")
	assert_not_null(parent.get_node_or_null("Ground_water"), "the ornamental pond renders as a merged ground mesh")
	assert_not_null(parent.get_node_or_null("Walls"), "wall tiles render under one merged Walls body")

	# DT-008 scale fix: the whole town renders with ONE merged Walls body and
	# merged ground meshes, never one StaticBody3D per tile.
	var walls_bodies: int = 0
	var structure_nodes: int = 0
	for child in parent.get_children():
		var child_name: String = String(child.name)
		assert_false(child_name.begins_with("Tile_"), "no legacy per-tile StaticBody3D remains")
		if child_name == "Walls":
			walls_bodies += 1
		elif child_name.begins_with("Structure_"):
			structure_nodes += 1
	assert_eq(walls_bodies, 1, "the town renders with ONE merged Walls body, not one body per wall tile")
	assert_eq(structure_nodes, expected_structures, "every structure becomes one instance")
	assert_gt(wall_tiles, 0, "the town has walls to merge (guards the assertion above)")


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


func test_experiment_1001_assembles_safe_ingress_and_rejects_unsafe_ingress() -> void:
	var safe_parent: Node3D = add_child_autofree(Node3D.new())
	var safe_blueprint: Dictionary = {
		"schema_version": 2,
		"sector_id": "issue-1001-safe",
		"origin": {"x": 0, "y": 0},
		"tiles": [
			{"x": 0, "y": 0, "kind": "floor"},
			{"x": 1, "y": 0, "kind": "floor"},
			{"x": 2, "y": 0, "kind": "floor"},
		],
		"structures": [],
	}
	var safe_result: Dictionary = NetworkClientScript.render_sector_blueprint(
		safe_blueprint, safe_parent, Vector3(0.0, 0.0, 0.0), Vector3(2.0, 0.0, 0.0)
	)
	await wait_physics_frames(5)

	assert_eq(safe_result["outcome"], SectorBlueprintSchemaScript.OUTCOME_VALID, "safe blueprint is schema-valid")
	assert_true(safe_result["geometry_assembly_completed"], "safe blueprint completes geometry assembly")
	assert_true(safe_result["navigation_ready"], "safe blueprint synchronizes navigation")
	assert_gt((safe_result["path"] as PackedVector3Array).size(), 0, "safe ingress reaches the target")

	var unsafe_parent: Node3D = add_child_autofree(Node3D.new())
	var unsafe_result: Dictionary = NetworkClientScript.render_sector_blueprint(
		safe_blueprint, unsafe_parent, Vector3(100.0, 0.0, 100.0), Vector3(2.0, 0.0, 0.0)
	)
	await wait_physics_frames(1)
	await wait_physics_frames(5)
	assert_eq(unsafe_result["outcome"], "fallback_selected", "unsafe ingress selects the deterministic fallback")
	assert_eq(unsafe_result["fallback_sector_id"], "starting_town_hub", "unsafe ingress selects the validated starting-town fallback")
	assert_true(unsafe_result["geometry_assembly_completed"], "fallback geometry completes assembly")
	assert_true(unsafe_result["navigation_ready"], "fallback geometry synchronizes navigation")
	assert_gt((unsafe_result["path"] as PackedVector3Array).size(), 0, "fallback ingress reaches its deterministic target")
	assert_gt(unsafe_parent.get_child_count(), 0, "unsafe ingress renders the deterministic fallback")

	var safe_trace: Dictionary = safe_result.duplicate(true)
	safe_trace.erase("readiness_node")
	var unsafe_trace: Dictionary = unsafe_result.duplicate(true)
	unsafe_trace.erase("readiness_node")
	var trace: Dictionary = {
		"experiment": "1001",
		"safe": safe_trace,
		"unsafe": unsafe_trace,
	}
	var trace_file: FileAccess = FileAccess.open(TRACE_PATH, FileAccess.WRITE)
	if trace_file != null:
		trace_file.store_string(JSON.stringify(trace, "\t"))
		trace_file.close()


func test_experiment_1001_deterministic_blueprint_matrix() -> void:
	var cases: Array[Dictionary] = [
		_matrix_case("normal_a", _rect_tiles(3, 1), Vector3(0.0, 0.0, 0.0), Vector3(2.0, 0.0, 0.0)),
		_matrix_case("normal_b", _rect_tiles(2, 2), Vector3(0.0, 0.0, 0.0), Vector3(1.0, 0.0, 1.0)),
		_matrix_case("dense_a", _rect_tiles(4, 4), Vector3(0.0, 0.0, 0.0), Vector3(3.0, 0.0, 3.0)),
		_matrix_case("dense_b", _rect_tiles(5, 3), Vector3(0.0, 0.0, 0.0), Vector3(4.0, 0.0, 2.0)),
		_matrix_case("island_a", _island_tiles(0), Vector3(0.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0)),
		_matrix_case("island_b", _island_tiles(2), Vector3(2.0, 0.0, 2.0), Vector3(3.0, 0.0, 2.0)),
		_matrix_case("boundary_a", _rect_tiles(2, 1, 47, 47), Vector3(47.0, 0.0, 47.0), Vector3(48.0, 0.0, 47.0)),
		_matrix_case("boundary_b", _rect_tiles(2, 1, -48, -48), Vector3(-48.0, 0.0, -48.0), Vector3(-47.0, 0.0, -48.0)),
		_matrix_case("unsafe_a", _rect_tiles(3, 1), Vector3(100.0, 0.0, 100.0), Vector3(2.0, 0.0, 0.0)),
		_matrix_case("unsafe_b", _rect_tiles(2, 2), Vector3(-100.0, 0.0, -100.0), Vector3(1.0, 0.0, 1.0)),
	]
	var evidence: Array[Dictionary] = []
	for blueprint_case: Dictionary in cases:
		var parent: Node3D = add_child_autofree(Node3D.new())
		var blueprint: Dictionary = blueprint_case["blueprint"]
		var result: Dictionary = NetworkClientScript.render_sector_blueprint(
			blueprint, parent, blueprint_case["ingress"], blueprint_case["target"]
		)
		await wait_physics_frames(6)
		var is_unsafe: bool = String(blueprint_case["class"]) == "unsafe"
		if is_unsafe:
			assert_eq(result["outcome"], "fallback_selected", "%s selects fallback" % blueprint["sector_id"])
		else:
			assert_eq(result["outcome"], SectorBlueprintSchemaScript.OUTCOME_VALID, "%s is accepted" % blueprint["sector_id"])
		assert_true(result["geometry_assembly_completed"], "%s completes assembly" % blueprint["sector_id"])
		assert_true(result["navigation_ready"], "%s synchronizes navigation" % blueprint["sector_id"])
		assert_gt((result["path"] as PackedVector3Array).size(), 0, "%s has a navigation path" % blueprint["sector_id"])
		evidence.append({
			"sector_id": blueprint["sector_id"],
			"class": blueprint_case["class"],
			"outcome": result["outcome"],
			"geometry_assembly_completed": result["geometry_assembly_completed"],
			"navigation_ready": result["navigation_ready"],
			"path_points": (result["path"] as PackedVector3Array).size(),
		})
	var trace_file: FileAccess = FileAccess.open(MATRIX_TRACE_PATH, FileAccess.WRITE)
	if trace_file != null:
		trace_file.store_string(JSON.stringify({"experiment": "1001", "cases": evidence}, "\t"))
		trace_file.close()


func _matrix_case(sector_id: String, tiles: Array, ingress: Vector3, target: Vector3) -> Dictionary:
	return {
		"class": "unsafe" if absf(ingress.x) > 48.0 or absf(ingress.z) > 48.0 else "accepted",
		"ingress": ingress,
		"target": target,
		"blueprint": {
			"schema_version": 2,
			"sector_id": "issue-1001-%s" % sector_id,
			"origin": {"x": 0, "y": 0},
			"tiles": tiles,
			"structures": [],
		},
	}


func _rect_tiles(width: int, height: int, start_x: int = 0, start_y: int = 0) -> Array:
	var tiles: Array = []
	for y: int in range(start_y, start_y + height):
		for x: int in range(start_x, start_x + width):
			tiles.append({"x": x, "y": y, "kind": "floor"})
	return tiles


func _island_tiles(start: int) -> Array:
	return [
		{"x": start, "y": start, "kind": "floor"},
		{"x": start + 1, "y": start, "kind": "floor"},
	]
