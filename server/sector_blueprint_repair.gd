extends RefCounted
## #551 fallback Pass 1: bounded, deterministic repair of an invalid model
## candidate. Keeps only well-formed supported tiles, rounds and clamps them into
## bounds, de-duplicates cells and re-anchors the set so a tile sits on the
## origin. Structures, spawn points and classification fields are dropped, so a
## repair can only remove model content, never invent facilities. The caller must
## still pass the result through the unchanged schema, placement and Canon gates.

const Schema: Script = preload("res://shared/sector_blueprint_schema.gd")
const REPAIRED_SCHEMA_VERSION: int = 3


## Returns the repaired candidate, or {} when nothing admissible remains.
static func repair(candidate: Variant, sector_id: String) -> Dictionary:
	if not candidate is Dictionary or sector_id.is_empty():
		return {}
	var raw_tiles: Variant = (candidate as Dictionary).get("tiles")
	if not raw_tiles is Array:
		return {}
	var bound: int = Schema.MAX_COORDINATE_ABS
	var cells: Dictionary = {}
	for raw: Variant in raw_tiles:
		if cells.size() >= Schema.MAX_TILE_COUNT:
			break
		if not raw is Dictionary:
			continue
		var kind: Variant = raw.get("kind")
		var x: Variant = raw.get("x")
		var y: Variant = raw.get("y")
		if not kind is String or not Schema.SUPPORTED_TILE_KINDS.has(kind):
			continue
		if not (x is int or x is float) or not (y is int or y is float) or not is_finite(float(x)) or not is_finite(float(y)):
			continue
		var cell: Vector2i = Vector2i(clampi(roundi(float(x)), -bound, bound), clampi(roundi(float(y)), -bound, bound))
		if not cells.has(cell):
			cells[cell] = kind
	if cells.is_empty():
		return {}
	var shift: Vector2i = Vector2i.ZERO
	if not cells.has(Vector2i.ZERO):
		var nearest: Vector2i = cells.keys()[0]
		for cell: Vector2i in cells:
			if cell.length_squared() < nearest.length_squared():
				nearest = cell
		shift = -nearest
	var tiles: Array = []
	for cell: Vector2i in cells:
		var placed: Vector2i = cell + shift
		if absi(placed.x) <= bound and absi(placed.y) <= bound:
			tiles.append({"x": placed.x, "y": placed.y, "kind": cells[cell]})
	return {"schema_version": REPAIRED_SCHEMA_VERSION, "sector_id": sector_id, "origin": {"x": 0, "y": 0}, "tiles": tiles}
