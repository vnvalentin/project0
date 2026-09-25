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
const WorldScaleScript: Script = preload("res://shared/world_scale.gd")
const TRACE_PATH: String = "res://build/validation/issue-1001-geometry-assembly-trace.json"
const MATRIX_TRACE_PATH: String = "res://build/validation/issue-1001-blueprint-matrix.json"
const PLACEMENT_TRACE_PATH: String = "res://build/validation/issue-1077-sector-placement.json"


func test_experiment_1077_places_signed_sector_roots_idempotently() -> void:
	var registry: Node3D = add_child_autofree(Node3D.new())
	var cases: Array[Dictionary] = [
		{"sector_id": "sector-1-0", "coordinate": Vector2i(1, 0)},
		{"sector_id": "sector--1-0", "coordinate": Vector2i(-1, 0)},
		{"sector_id": "sector-1--1", "coordinate": Vector2i(1, -1)},
	]
	var evidence: Array[Dictionary] = []
	var floor_vertices_per_tile: int = 0
	for placement_case: Dictionary in cases:
		var sector_id: String = placement_case["sector_id"]
		var coordinate: Vector2i = placement_case["coordinate"]
		var blueprint: Dictionary = _placement_blueprint(sector_id)
		var result: Dictionary = NetworkClientScript.present_sector_blueprint(
			blueprint,
			registry,
			Vector3(
				coordinate.x * WorldScaleScript.SECTOR_EDGE_UNITS,
				0.0,
				coordinate.y * WorldScaleScript.SECTOR_EDGE_UNITS
			)
		)
		var root: Node3D = registry.get_node_or_null(sector_id) as Node3D
		var expected_offset: Vector3 = Vector3(
			coordinate.x * WorldScaleScript.SECTOR_EDGE_UNITS,
			0.0,
			coordinate.y * WorldScaleScript.SECTOR_EDGE_UNITS
		)
		assert_eq(result["outcome"], SectorBlueprintSchemaScript.OUTCOME_VALID, "%s is accepted" % sector_id)
		assert_true(result.has("sector_coordinate"), "%s returns its parsed coordinate" % sector_id)
		assert_not_null(root, "%s owns a keyed root" % sector_id)
		if root == null or not result.has("sector_coordinate"):
			return
		var parsed_coordinate: Vector2i = result["sector_coordinate"]
		assert_eq(parsed_coordinate, coordinate, "%s reports its parsed coordinate" % sector_id)
		assert_eq(result["tile_count"], (blueprint["tiles"] as Array).size(), "%s reports its realized tile count" % sector_id)
		assert_eq(root.position, expected_offset, "%s uses its signed global offset" % sector_id)
		assert_ne(root.position, Vector3(7.0, 0.0, -4.0), "blueprint origin remains sector-local")
		var floor_vertices: int = _assert_tile_geometry_under_root(root, expected_offset, sector_id)
		assert_gt(floor_vertices, 0, "%s realizes floor vertices" % sector_id)
		assert_eq(floor_vertices % int(result["tile_count"]), 0, "%s floor mesh holds one box per tile" % sector_id)
		floor_vertices_per_tile = floor_vertices / int(result["tile_count"])
		evidence.append({
			"sector_id": sector_id,
			"parsed_coordinate": {"x": parsed_coordinate.x, "z": parsed_coordinate.y},
			"expected_offset": _vector_evidence(expected_offset),
			"actual_offset": _vector_evidence(root.position),
			"tile_count": result["tile_count"],
		})

	assert_eq(registry.get_child_count(), 3, "all three sectors coexist with one root each")
	var untouched_root: Node3D = registry.get_node("sector--1-0") as Node3D
	var untouched_transform: Transform3D = untouched_root.transform
	var replaced_root: Node3D = registry.get_node("sector-1-0") as Node3D
	var identities_before_replay: Dictionary = _root_identities(registry)
	var replay_blueprint: Dictionary = _placement_blueprint("sector-1-0")
	(replay_blueprint["tiles"] as Array).append({"x": 2, "y": 0, "kind": "floor"})
	var replay: Dictionary = NetworkClientScript.present_sector_blueprint(
		replay_blueprint, registry, Vector3(WorldScaleScript.SECTOR_EDGE_UNITS, 0.0, 0.0)
	)
	var replayed_root: Node3D = registry.get_node("sector-1-0") as Node3D
	var identities_after_replay: Dictionary = _root_identities(registry)
	var replay_replacement_count: int = 0
	for root_name: String in identities_before_replay:
		if identities_after_replay.get(root_name, 0) != identities_before_replay[root_name]:
			replay_replacement_count += 1
	assert_eq(replay["outcome"], SectorBlueprintSchemaScript.OUTCOME_VALID, "replay is accepted")
	assert_eq(replay["tile_count"], (replay_blueprint["tiles"] as Array).size(), "replay realizes the changed sector-local detail")
	assert_eq(registry.get_child_count(), 3, "replay does not duplicate a sector root")
	assert_eq(identities_after_replay.keys().size(), identities_before_replay.keys().size(), "replay keeps the same keyed roots")
	assert_ne(replayed_root, replaced_root, "replay replaces the matching sector root")
	assert_eq(replay_replacement_count, 1, "replay replaces exactly one observed root identity")
	var replay_floor_vertices: int = _assert_tile_geometry_under_root(
		replayed_root,
		Vector3(WorldScaleScript.SECTOR_EDGE_UNITS, 0.0, 0.0),
		"sector-1-0 replay"
	)
	assert_eq(
		replay_floor_vertices,
		floor_vertices_per_tile * int(replay["tile_count"]),
		"replayed floor geometry reflects the returned tile count"
	)
	assert_eq(untouched_root.transform, untouched_transform, "replay does not move another sector")

	var invalid: Dictionary = NetworkClientScript.present_sector_blueprint(
		_placement_blueprint("sector-east-0"), registry, Vector3.ZERO
	)
	assert_eq(invalid["outcome"], "invalid_sector_id", "malformed sector identity fails closed")
	assert_eq(registry.get_child_count(), 3, "malformed identity creates no root")
	await get_tree().process_frame
	assert_false(is_instance_valid(replaced_root), "the replayed sector root is retired after the active signal frame")

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PLACEMENT_TRACE_PATH.get_base_dir()))
	var trace_file: FileAccess = FileAccess.open(PLACEMENT_TRACE_PATH, FileAccess.WRITE)
	assert_not_null(trace_file, "placement evidence artifact is writable (open error %d)" % FileAccess.get_open_error())
	if trace_file == null:
		return
	trace_file.store_string(JSON.stringify({
		"experiment": "1077",
		"sectors": evidence,
		"root_count": registry.get_child_count(),
		"replay_replacement_count": replay_replacement_count,
		"replay_tile_count": replay["tile_count"],
	}, "\t"))
	trace_file.close()


func test_rejected_sector_does_not_return_freed_readiness() -> void:
	var registry: Node3D = add_child_autofree(Node3D.new())
	var result: Dictionary = NetworkClientScript.present_sector_blueprint(
		_placement_blueprint("sector-0-0"), registry, Vector3(100.0, 0.0, 100.0)
	)
	assert_eq(result["outcome"], "fallback_selected")
	assert_eq(registry.get_child_count(), 0, "rejected pending geometry is removed")
	assert_false(result.has("readiness_node"), "rejection must not expose a freed readiness node")


func test_starting_town_hub_keeps_its_world_origin_root() -> void:
	var registry: Node3D = add_child_autofree(Node3D.new())
	var result: Dictionary = NetworkClientScript.present_sector_blueprint(
		StartingTownHubFixtureScript.blueprint(), registry, Vector3.ZERO
	)
	var root: Node3D = registry.get_node_or_null("starting_town_hub") as Node3D
	assert_eq(result["outcome"], SectorBlueprintSchemaScript.OUTCOME_VALID)
	assert_not_null(root, "the shipped starting town retains a keyed presentation root")
	assert_eq(root.position, Vector3.ZERO, "the starting town remains at world origin")


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


func _placement_blueprint(sector_id: String) -> Dictionary:
	return {
		"schema_version": 2,
		"sector_id": sector_id,
		"origin": {"x": 7, "y": -4},
		"tiles": [
			{"x": 0, "y": 0, "kind": "floor"},
			{"x": 1, "y": 0, "kind": "floor"},
		],
		"structures": [],
	}


## Asserts the realized floor mesh is owned below `root`, inherits the root's
## transformed offset, and spans sector-local tile space. Returns the floor
## mesh vertex count so callers can compare it against reported tile counts.
func _assert_tile_geometry_under_root(root: Node3D, expected_offset: Vector3, label: String) -> int:
	var ground: MeshInstance3D = root.get_node_or_null("Ground_floor") as MeshInstance3D
	assert_not_null(ground, "%s realizes floor geometry below its root" % label)
	if ground == null or ground.mesh == null:
		return 0
	assert_eq(ground.get_parent(), root, "%s floor geometry is owned by its sector root" % label)
	assert_eq(ground.global_position, expected_offset, "%s floor geometry inherits the sector offset" % label)
	var local_bounds: AABB = ground.mesh.get_aabb()
	assert_true(local_bounds.has_point(Vector3(0.0, local_bounds.get_center().y, 0.0)), "%s floor mesh stays in sector-local tile space" % label)
	var vertices: PackedVector3Array = ground.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	return vertices.size()


func _root_identities(registry: Node3D) -> Dictionary:
	var identities: Dictionary = {}
	for child: Node in registry.get_children():
		identities[String(child.name)] = child.get_instance_id()
	return identities


func _vector_evidence(value: Vector3) -> Dictionary:
	return {"x": value.x, "y": value.y, "z": value.z}
