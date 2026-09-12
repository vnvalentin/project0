extends RefCounted
class_name SectorGeometryTranslator
## Slice 015: client-side translation of an already-validated sector
## blueprint Dictionary (SectorBlueprintSchema.validate() output, schema v1
## or v2) into 3D scene geometry. Purely presentational — this script never
## validates the blueprint itself, owns no gameplay/world-state authority,
## and performs no network I/O. See docs/slices/015-sector-geometry-translation.md.
##
## Callers must only pass a Dictionary that already passed
## SectorBlueprintSchema.validate(); this slice explicitly assumes the
## caller already has that Dictionary in hand (e.g. a test fixture or a
## future replication seam) and does not implement how it gets there.

const SectorGeometryLookupScript: Script = preload("res://shared/sector_geometry_lookup.gd")

## Cache of loaded structure PackedScenes keyed by resource path, so a sector
## with many structures of the same kind does not reload the same scene file
## repeatedly.
static var _structure_scene_cache: Dictionary = {}


## Instantiates every tile and structure entry in `blueprint` as children of
## `parent`. Unsupported tile/structure kinds are logged and skipped rather
## than failing the whole pass — reaching one here indicates a schema/lookup
## drift bug (the input already passed schema validation), not untrusted
## input requiring a hard fail-closed abort.
static func translate(blueprint: Dictionary, parent: Node3D) -> void:
	var tiles: Array = blueprint.get("tiles", [])
	for tile: Dictionary in tiles:
		_translate_tile(tile, parent)

	var structures: Array = blueprint.get("structures", [])
	for structure: Dictionary in structures:
		_translate_structure(structure, parent)


static func _translate_tile(tile: Dictionary, parent: Node3D) -> void:
	var kind: String = tile.get("kind", "")
	var dimensions: Vector3 = SectorGeometryLookupScript.tile_dimensions(kind)
	if dimensions == Vector3.ZERO:
		push_warning("SectorGeometryTranslator: skipping tile with unsupported kind '%s'." % kind)
		return

	var x: float = float(tile.get("x", 0))
	var y: float = float(tile.get("y", 0))

	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Tile_%s_%d_%d" % [kind, int(x), int(y)]
	body.position = Vector3(x, dimensions.y * 0.5, y)

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var box_mesh: BoxMesh = BoxMesh.new()
	box_mesh.size = dimensions
	mesh_instance.mesh = box_mesh
	body.add_child(mesh_instance)
	mesh_instance.name = "MeshInstance3D"

	var collision_shape: CollisionShape3D = CollisionShape3D.new()
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = dimensions
	collision_shape.shape = box_shape
	body.add_child(collision_shape)
	collision_shape.name = "CollisionShape3D"

	parent.add_child(body)


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
