extends RefCounted
class_name SectorGeometryTranslator
## Slice 015/024: client-side translation of an already-validated sector
## blueprint Dictionary (SectorBlueprintSchema.validate() output) into 3D
## scene geometry. Purely presentational — this script never validates the
## blueprint itself, owns no gameplay/world-state authority, and performs no
## network I/O. See docs/slices/024-scalable-geometry-pass.md.
##
## Slice 024 replaces the original one-StaticBody3D-per-tile strategy (which
## did not scale to city size — see DT-008) with a scale-friendly pass:
##  - non-solid ground tiles (floor/corridor) render as one merged ArrayMesh
##    MeshInstance3D per kind (all tiles of a kind combined into a single mesh,
##    one draw call, NO physics bodies); the Gameplay FlatPlane remains the
##    walkable collision surface, so per-tile floor colliders were redundant.
##  - solid tiles (wall) are greedy-merged along each row into a small number
##    of box colliders + meshes under a single shared "Walls" StaticBody3D.
##  - structures are unchanged (one prefab instance each).
##
## Callers must only pass a Dictionary that already passed
## SectorBlueprintSchema.validate().

const SectorGeometryLookupScript: Script = preload("res://shared/sector_geometry_lookup.gd")

## Names of the container nodes the pass produces, so callers/tests can find
## the merged geometry deterministically.
const GROUND_NODE_PREFIX: String = "Ground_"
const WALLS_NODE_NAME: String = "Walls"

## Cache of loaded structure PackedScenes keyed by resource path, so a sector
## with many structures of the same kind does not reload the same scene file
## repeatedly.
static var _structure_scene_cache: Dictionary = {}

## Cache of the per-kind unit-box surface arrays (keyed by tile kind), reused
## to build each sector's merged ground mesh. Per-kind dimensions are constant,
## so the base box geometry is generated once per process.
static var _ground_base_arrays_cache: Dictionary = {}


## Translates `blueprint` into merged geometry under `parent`: per-kind ground
## MultiMeshInstance3D visuals, one shared "Walls" StaticBody3D of greedy-merged
## box colliders, and one instance per structure. Unsupported tile/structure
## kinds are logged and skipped (reaching one indicates schema/lookup drift, not
## untrusted input — the caller already passed schema validation).
static func translate(blueprint: Dictionary, parent: Node3D) -> void:
	var tiles: Array = blueprint.get("tiles", [])
	_translate_ground_tiles(tiles, parent)
	_translate_wall_tiles(tiles, parent)

	var structures: Array = blueprint.get("structures", [])
	for structure: Dictionary in structures:
		_translate_structure(structure, parent)


## Renders every non-solid tile as one merged ArrayMesh MeshInstance3D per kind
## (all tiles of a kind combined into a single mesh — one draw call, no physics
## bodies).
static func _translate_ground_tiles(tiles: Array, parent: Node3D) -> void:
	var placements_by_kind: Dictionary = {}
	for tile: Dictionary in tiles:
		var kind: String = tile.get("kind", "")
		var dimensions: Vector3 = SectorGeometryLookupScript.tile_dimensions(kind)
		if dimensions == Vector3.ZERO:
			push_warning("SectorGeometryTranslator: skipping tile with unsupported kind '%s'." % kind)
			continue
		if SectorGeometryLookupScript.tile_is_solid(kind):
			continue
		if not placements_by_kind.has(kind):
			placements_by_kind[kind] = []
		placements_by_kind[kind].append(Vector2(float(tile.get("x", 0)), float(tile.get("y", 0))))

	for kind: String in placements_by_kind:
		var dimensions: Vector3 = SectorGeometryLookupScript.tile_dimensions(kind)
		var placements: Array = placements_by_kind[kind]

		var mesh_instance: MeshInstance3D = MeshInstance3D.new()
		mesh_instance.mesh = _merged_ground_mesh(kind, dimensions, placements)
		mesh_instance.name = "%s%s" % [GROUND_NODE_PREFIX, kind]
		parent.add_child(mesh_instance)


## Builds one ArrayMesh combining a unit box at every placement of `kind`, so a
## whole kind of ground renders as a single mesh (one draw call).
static func _merged_ground_mesh(kind: String, dimensions: Vector3, placements: Array) -> ArrayMesh:
	var base: Array = _ground_base_arrays(kind, dimensions)
	var base_verts: PackedVector3Array = base[Mesh.ARRAY_VERTEX]
	var base_normals: PackedVector3Array = base[Mesh.ARRAY_NORMAL]
	var base_indices: PackedInt32Array = base[Mesh.ARRAY_INDEX]

	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var vertex_offset: int = 0
	for placement: Vector2 in placements:
		var center: Vector3 = Vector3(placement.x, dimensions.y * 0.5, placement.y)
		for v: Vector3 in base_verts:
			verts.append(v + center)
		for n: Vector3 in base_normals:
			normals.append(n)
		for index: int in base_indices:
			indices.append(index + vertex_offset)
		vertex_offset += base_verts.size()

	var surface_arrays: Array = []
	surface_arrays.resize(Mesh.ARRAY_MAX)
	surface_arrays[Mesh.ARRAY_VERTEX] = verts
	surface_arrays[Mesh.ARRAY_NORMAL] = normals
	surface_arrays[Mesh.ARRAY_INDEX] = indices

	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_arrays)
	return mesh


## Returns the cached unit-box surface arrays for a tile kind (generated once
## per process; per-kind dimensions are constant).
static func _ground_base_arrays(kind: String, dimensions: Vector3) -> Array:
	if not _ground_base_arrays_cache.has(kind):
		var box_mesh: BoxMesh = BoxMesh.new()
		box_mesh.size = dimensions
		_ground_base_arrays_cache[kind] = box_mesh.surface_get_arrays(0)
	return _ground_base_arrays_cache[kind]


## Greedy-merges contiguous horizontal runs of solid (wall) tiles into box
## colliders + meshes under a single shared "Walls" StaticBody3D, so a wall of
## N tiles becomes a handful of colliders instead of N physics bodies.
static func _translate_wall_tiles(tiles: Array, parent: Node3D) -> void:
	var rows: Dictionary = {}
	for tile: Dictionary in tiles:
		var kind: String = tile.get("kind", "")
		if not SectorGeometryLookupScript.tile_is_solid(kind):
			continue
		var y: int = int(tile.get("y", 0))
		if not rows.has(y):
			rows[y] = []
		rows[y].append(int(tile.get("x", 0)))

	if rows.is_empty():
		return

	var wall_dimensions: Vector3 = SectorGeometryLookupScript.tile_dimensions("wall")
	var walls_body: StaticBody3D = StaticBody3D.new()
	walls_body.name = WALLS_NODE_NAME

	var segment_index: int = 0
	var row_keys: Array = rows.keys()
	row_keys.sort()
	for y: int in row_keys:
		var xs: Array = rows[y]
		xs.sort()
		var run_start: int = xs[0]
		var prev: int = xs[0]
		for i in range(1, xs.size()):
			var cx: int = xs[i]
			if cx == prev + 1:
				prev = cx
				continue
			_add_wall_segment(walls_body, run_start, prev, y, wall_dimensions, segment_index)
			segment_index += 1
			run_start = cx
			prev = cx
		_add_wall_segment(walls_body, run_start, prev, y, wall_dimensions, segment_index)
		segment_index += 1

	parent.add_child(walls_body)


## Adds one merged wall run [x_start, x_end] at row `y` to `body` as a
## MeshInstance3D + CollisionShape3D pair sharing the run's box size/center.
static func _add_wall_segment(body: StaticBody3D, x_start: int, x_end: int, y: int, wall_dimensions: Vector3, index: int) -> void:
	var run_length: int = x_end - x_start + 1
	var size: Vector3 = Vector3(wall_dimensions.x * float(run_length), wall_dimensions.y, wall_dimensions.z)
	var center: Vector3 = Vector3((float(x_start) + float(x_end)) * 0.5, wall_dimensions.y * 0.5, float(y))

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var box_mesh: BoxMesh = BoxMesh.new()
	box_mesh.size = size
	mesh_instance.mesh = box_mesh
	mesh_instance.position = center
	body.add_child(mesh_instance)
	mesh_instance.name = "WallSegmentMesh_%d" % index

	var collision_shape: CollisionShape3D = CollisionShape3D.new()
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = size
	collision_shape.shape = box_shape
	collision_shape.position = center
	body.add_child(collision_shape)
	collision_shape.name = "WallSegmentShape_%d" % index


static func _translate_structure(structure: Dictionary, parent: Node3D) -> void:
	var kind: String = structure.get("kind", "")
	var scene_path: String = SectorGeometryLookupScript.structure_scene_path(kind)
	if scene_path.is_empty():
		push_warning("SectorGeometryTranslator: skipping structure with unsupported kind '%s'." % kind)
		return

	var packed_scene: PackedScene = _load_structure_scene(scene_path)
	if packed_scene == null:
		push_warning("SectorGeometryTranslator: failed to load structure scene '%s'." % scene_path)
		return

	var instance: Node3D = packed_scene.instantiate()
	instance.name = "Structure_%s" % String(structure.get("structure_id", kind))

	var x: float = float(structure.get("x", 0))
	var y: float = float(structure.get("y", 0))
	var facing_degrees: float = float(structure.get("facing_degrees", 0))
	var basis: Basis = Basis(Vector3.UP, deg_to_rad(facing_degrees))
	instance.transform = Transform3D(basis, Vector3(x, 0.0, y))

	parent.add_child(instance)


static func _load_structure_scene(scene_path: String) -> PackedScene:
	if not _structure_scene_cache.has(scene_path):
		_structure_scene_cache[scene_path] = load(scene_path)
	return _structure_scene_cache[scene_path]
