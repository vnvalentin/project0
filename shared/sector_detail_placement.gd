extends RefCounted
class_name SectorDetailPlacement

const Identity: Script = preload("res://shared/sector_identity.gd")
const Scale: Script = preload("res://shared/world_scale.gd")
const Collision: Script = preload("res://shared/sector_collision_map.gd")
const SCHEMA_VERSION: int = 5
const ACTOR_RADIUS: float = 0.4

var _blueprint: Dictionary
var _offset: Vector3
var _collision: RefCounted
var _connected: Dictionary = {}


func _init(blueprint: Dictionary = {}) -> void:
	_blueprint = blueprint.duplicate(true)
	_offset = world_offset(blueprint)
	_collision = Collision.new(blueprint)
	var walkable: Dictionary = {}
	for tile: Dictionary in blueprint.get("tiles", []):
		var coordinate: Vector2i = Vector2i(int(tile["x"]), int(tile["y"]))
		if not _collision.is_blocked(coordinate) and clip_rectangle(blueprint, Rect2(Vector2(coordinate) - Vector2(0.5, 0.5), Vector2.ONE)).has_area():
			walkable[coordinate] = true
	var entry: Dictionary = blueprint.get("origin", {"x": 0, "y": 0})
	var origin: Vector2i = Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0)))
	if not walkable.has(origin):
		return
	var pending: Array[Vector2i] = [origin]
	_connected[origin] = true
	var index: int = 0
	while index < pending.size():
		var current: Vector2i = pending[index]
		index += 1
		for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var neighbor: Vector2i = current + direction
			if walkable.has(neighbor) and not _connected.has(neighbor):
				_connected[neighbor] = true
				pending.append(neighbor)


func contains_world(position: Vector3) -> bool:
	if not position.is_finite() or not _offset.is_finite():
		return false
	if int(_blueprint.get("schema_version", 0)) == SCHEMA_VERSION:
		var coordinate: Vector2i = Identity.parse(String(_blueprint["sector_id"]))["coordinate"]
		if coordinate != Vector2i(floori(position.x / Scale.SECTOR_EDGE_UNITS), floori(position.z / Scale.SECTOR_EDGE_UNITS)):
			return false
	var local: Vector3 = position - _offset
	return _connected.has(Vector2i(floori(local.x + 0.5), floori(local.z + 0.5))) and has_clearance(position)


func has_clearance(position: Vector3) -> bool:
	if not position.is_finite() or not _offset.is_finite():
		return false
	var local: Vector3 = position - _offset
	var point: Vector2 = Vector2(local.x, local.z)
	var center: Vector2i = Vector2i(floori(local.x + 0.5), floori(local.z + 0.5))
	for horizontal: int in range(center.x - 1, center.x + 2):
		for vertical: int in range(center.y - 1, center.y + 2):
			var cell: Vector2i = Vector2i(horizontal, vertical)
			if _collision.is_blocked(cell):
				var lower: Vector2 = Vector2(cell) - Vector2(0.5, 0.5)
				var closest: Vector2 = point.clamp(lower, lower + Vector2.ONE)
				if point.distance_squared_to(closest) < ACTOR_RADIUS * ACTOR_RADIUS - 0.000001:
					return false
	return true


func connected_tiles() -> Dictionary:
	var result: Dictionary = {}
	for coordinate: Vector2i in _connected:
		result[Vector2(coordinate)] = true
	return result


func navigation_polygons() -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for coordinate: Vector2i in _connected:
		var bounds: Rect2 = clip_rectangle(_blueprint, Rect2(Vector2(coordinate) - Vector2(0.5, 0.5), Vector2.ONE))
		var pieces: Array[PackedVector2Array] = [_rectangle_polygon(bounds)]
		for horizontal: int in range(coordinate.x - 1, coordinate.x + 2):
			for vertical: int in range(coordinate.y - 1, coordinate.y + 2):
				if not _collision.is_blocked(Vector2i(horizontal, vertical)):
					continue
				var obstacle: PackedVector2Array = _rectangle_polygon(Rect2(Vector2(horizontal, vertical) - Vector2(0.5, 0.5), Vector2.ONE).grow(ACTOR_RADIUS))
				var remaining: Array[PackedVector2Array] = []
				for piece: PackedVector2Array in pieces:
					remaining.append_array(Geometry2D.clip_polygons(piece, obstacle))
				pieces = remaining
		result.append_array(pieces)
	return result


static func _rectangle_polygon(bounds: Rect2) -> PackedVector2Array:
	return PackedVector2Array([bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)])


func navigation_target(world_ingress: Vector3) -> Vector3:
	var target: Vector3 = Vector3(INF, INF, INF)
	var distance: float = -1.0
	for coordinate: Vector2i in _connected:
		var rectangle: Rect2 = clip_rectangle(_blueprint, Rect2(Vector2(coordinate) - Vector2(0.5, 0.5), Vector2.ONE))
		var center: Vector2 = rectangle.get_center()
		var candidate: Vector3 = _offset + Vector3(center.x, world_ingress.y, center.y)
		if contains_world(candidate) and candidate.distance_squared_to(world_ingress) > distance:
			target = candidate
			distance = candidate.distance_squared_to(world_ingress)
	return target


static func clip_rectangle(blueprint: Dictionary, rectangle: Rect2) -> Rect2:
	if int(blueprint.get("schema_version", 0)) != SCHEMA_VERSION:
		return rectangle
	if not validate_metadata(blueprint).is_empty():
		return Rect2()
	var detail: Dictionary = blueprint["detail_origin"]
	return rectangle.intersection(Rect2(Vector2(-float(detail["x"]), -float(detail["y"])), Vector2(Scale.SECTOR_EDGE_UNITS, Scale.SECTOR_EDGE_UNITS)))


static func validate_metadata(blueprint: Dictionary) -> String:
	if int(blueprint.get("schema_version", 0)) != SCHEMA_VERSION:
		return "detail_origin requires schema version 5." if blueprint.has("detail_origin") else ""
	var sector_id: String = String(blueprint.get("sector_id", ""))
	var parsed: Dictionary = Identity.parse(sector_id)
	if parsed["outcome"] != "valid" or sector_id == Identity.LEGACY_STARTING_TOWN_ID:
		return "Placed detail requires an ordinary sector identity."
	var coordinate: Vector2i = parsed["coordinate"]
	if sector_id != "sector-%d-%d" % [coordinate.x, coordinate.y]:
		return "Placed detail requires a canonical sector identity."
	var detail: Variant = blueprint.get("detail_origin")
	if not detail is Dictionary or detail.size() != 2:
		return "detail_origin must contain exactly x and y."
	for axis: String in ["x", "y"]:
		if not _integer(detail.get(axis)) or float(detail[axis]) < 0 or float(detail[axis]) >= Scale.SECTOR_EDGE_UNITS:
			return "detail_origin components must be finite integers within the sector."
		var entry: Variant = blueprint.get("origin", {})
		if not entry is Dictionary or not _integer(entry.get(axis)):
			return "Version 5 origin must identify an integer entry tile."
	return ""


static func select(sector_id: String, world_ingress: Vector3) -> Dictionary:
	if not world_ingress.is_finite():
		return {}
	var parsed: Dictionary = Identity.parse(sector_id)
	if parsed["outcome"] != "valid" or sector_id == Identity.LEGACY_STARTING_TOWN_ID:
		return {}
	var coordinate: Vector2i = parsed["coordinate"]
	if coordinate != Vector2i(floori(world_ingress.x / Scale.SECTOR_EDGE_UNITS), floori(world_ingress.z / Scale.SECTOR_EDGE_UNITS)):
		return {}
	var local: Vector3 = world_ingress - grid_offset(sector_id)
	var translation: Vector2i = Vector2i(clampi(floori(local.x), 0, int(Scale.SECTOR_EDGE_UNITS) - 1), clampi(floori(local.z), 0, int(Scale.SECTOR_EDGE_UNITS) - 1))
	return {
		"detail_origin": {"x": translation.x, "y": translation.y},
		"origin": {"x": floori(local.x - translation.x + 0.5), "y": floori(local.z - translation.y + 0.5)},
	}


static func grid_offset(sector_id: String) -> Vector3:
	var parsed: Dictionary = Identity.parse(sector_id)
	if parsed["outcome"] != "valid":
		return Vector3(INF, INF, INF)
	var coordinate: Vector2i = parsed["coordinate"]
	return Vector3(coordinate.x * Scale.SECTOR_EDGE_UNITS, 0, coordinate.y * Scale.SECTOR_EDGE_UNITS)


static func world_offset(blueprint: Dictionary) -> Vector3:
	var offset: Vector3 = grid_offset(String(blueprint.get("sector_id", "")))
	if int(blueprint.get("schema_version", 0)) == SCHEMA_VERSION:
		if not validate_metadata(blueprint).is_empty():
			return Vector3(INF, INF, INF)
		var detail: Dictionary = blueprint["detail_origin"]
		offset += Vector3(float(detail["x"]), 0, float(detail["y"]))
	return offset


static func to_world(blueprint: Dictionary, detail_position: Vector3) -> Vector3:
	return world_offset(blueprint) + detail_position


static func to_detail(blueprint: Dictionary, world_position: Vector3) -> Vector3:
	return world_position - world_offset(blueprint)


static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value))
