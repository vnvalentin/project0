extends RefCounted
class_name SectorCollisionMap
## Slice 030: server-side solid-cell collision for a validated sector blueprint.
## Wall tiles and structure footprints become blocked grid cells; the server's
## authoritative movement integration slides the player against them so walls
## and buildings are physically solid. Pure and deterministic (no SceneTree),
## built once from the blueprint. Walkable ground kinds (floor/corridor/path/
## plaza/gate/grass/water) stay open. See docs/slices/030-server-side-collision.md.
##
## The player is treated as a point at grid-cell resolution: a cell (x, y) is
## the unit square centred on the integer coordinate, so a move is blocked when
## its rounded destination cell is solid. Because roundi(0.5) == 1, the player
## stops with its centre on the solid cell's face. Sub-cell/radius precision is
## a future refinement.

const SectorGeometryLookupScript: Script = preload("res://shared/sector_geometry_lookup.gd")

## Set of blocked grid cells: Vector2i -> true.
var _blocked: Dictionary = {}


## Builds the blocked-cell set from `blueprint`: every wall tile, plus every
## structure's footprint (its anchor cell expanded by the per-kind half-extent
## from SectorGeometryLookup). An empty/absent blueprint yields an empty map
## (nothing solid), so a caller with no town simply has free movement.
func _init(blueprint: Dictionary = {}) -> void:
	for tile: Dictionary in blueprint.get("tiles", []):
		if String(tile.get("kind", "")) == "wall":
			_blocked[Vector2i(int(tile.get("x", 0)), int(tile.get("y", 0)))] = true

	for structure: Dictionary in blueprint.get("structures", []):
		var footprint: Vector2i = SectorGeometryLookupScript.structure_footprint(String(structure.get("kind", "")))
		var sx: int = int(structure.get("x", 0))
		var sy: int = int(structure.get("y", 0))
		for dx in range(-footprint.x, footprint.x + 1):
			for dy in range(-footprint.y, footprint.y + 1):
				_blocked[Vector2i(sx + dx, sy + dy)] = true


## True when the grid cell is solid (a wall tile or inside a structure footprint).
func is_blocked(cell: Vector2i) -> bool:
	return _blocked.has(cell)


func blocked_count() -> int:
	return _blocked.size()


## Resolves a desired move from `from` to `to`, sliding along solids: if `to`
## enters a blocked cell, try moving on only one axis so the player slides along
## the wall; if both single-axis moves are also blocked, stay put. The y
## component is always taken from `to` (movement is planar; y is not collided).
func resolve_move(from: Vector3, to: Vector3) -> Vector3:
	if not is_blocked(_cell(to)):
		return to
	var x_only: Vector3 = Vector3(to.x, to.y, from.z)
	if not is_blocked(_cell(x_only)):
		return x_only
	var z_only: Vector3 = Vector3(from.x, to.y, to.z)
	if not is_blocked(_cell(z_only)):
		return z_only
	return Vector3(from.x, to.y, from.z)


static func _cell(v: Vector3) -> Vector2i:
	return Vector2i(roundi(v.x), roundi(v.z))
