extends RefCounted
class_name WorkshopStationContract
## Closed server provisioning values; parsing does not establish authority.

const MAX_ID_LENGTH: int = 128
const MAX_WORLD_COMPONENT: float = 1073741824.0
const FIELDS: PackedStringArray = ["schema_version", "station_id", "interior_id", "anchor_revision", "bounds_min", "bounds_max", "active", "revision"]


class StationValue extends RefCounted:
	var station_id: String
	var interior_id: String
	var bounds_min: Vector3
	var bounds_max: Vector3
	var active: bool

	func to_dict() -> Dictionary:
		return {
			"schema_version": 1, "station_id": station_id, "interior_id": interior_id,
			"anchor_revision": 1, "bounds_min": [bounds_min.x, bounds_min.y, bounds_min.z],
			"bounds_max": [bounds_max.x, bounds_max.y, bounds_max.z], "active": active, "revision": 1,
		}

	func contains_center(center: Vector3) -> bool:
		return is_finite(center.x) and is_finite(center.y) and is_finite(center.z) \
			and center.x >= bounds_min.x and center.y >= bounds_min.y and center.z >= bounds_min.z \
			and center.x < bounds_max.x and center.y < bounds_max.y and center.z < bounds_max.z


static func parse_server_descriptor(input: Variant) -> Dictionary:
	if not input is Dictionary or input.size() != FIELDS.size():
		return _invalid()
	for field: String in FIELDS:
		if not input.has(field):
			return _invalid()
	for field: String in ["schema_version", "anchor_revision", "revision"]:
		if not (input[field] is int or input[field] is float) or input[field] != 1:
			return _invalid()
	for field: String in ["station_id", "interior_id"]:
		if not valid_id(input[field]):
			return _invalid()
	if not input["active"] is bool or not _vector(input["bounds_min"]) or not _vector(input["bounds_max"]):
		return _invalid()
	var lower: Vector3 = _to_vector(input["bounds_min"])
	var upper: Vector3 = _to_vector(input["bounds_max"])
	if upper.x <= lower.x or upper.y <= lower.y or upper.z <= lower.z:
		return _invalid()
	var station: StationValue = StationValue.new()
	station.station_id = input["station_id"]
	station.interior_id = input["interior_id"]
	station.bounds_min = lower
	station.bounds_max = upper
	station.active = input["active"]
	return {"outcome": "ok", "station": station}


static func parse_intent(input: Variant) -> Dictionary:
	if not input is Dictionary or input.size() != 2 or not input.has("schema_version") or not input.has("station_id"):
		return {"outcome": "invalid_intent"}
	if not (input["schema_version"] is int or input["schema_version"] is float) or input["schema_version"] != 1 or not valid_id(input["station_id"]):
		return {"outcome": "invalid_intent"}
	return {"outcome": "ok", "station_id": input["station_id"]}


static func valid_id(value: Variant) -> bool:
	return value is String and not value.is_empty() and value.length() <= MAX_ID_LENGTH and value.strip_edges() == value


static func _vector(value: Variant) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for component: Variant in value:
		if not (component is int or component is float) or not is_finite(float(component)) or absf(float(component)) > MAX_WORLD_COMPONENT:
			return false
	return true


static func _to_vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


static func _invalid() -> Dictionary:
	return {"outcome": "invalid_station"}
