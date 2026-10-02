extends RefCounted
class_name InteriorAnchorContract
## #849 pure closed values. Shared interpretation never grants entry authority.

const Guid: Script = preload("res://shared/canon_entity_guid.gd")
const SCHEMA_VERSION: int = 1
const MAX_ID_LENGTH: int = 128
const MAX_CELL_COMPONENT: int = 1048576
const MAX_WORLD_COMPONENT: float = 1073741824.0
const MAX_REVISION: int = 1073741824
const DESCRIPTOR_FIELDS: PackedStringArray = ["schema_version", "exterior_sector_id", "exterior_entity_guid", "plot_id", "entry_position", "cell_coordinate", "bounds_min", "bounds_max", "streaming_reference"]
const RECORD_FIELDS: PackedStringArray = ["interior_id", "revision", "exterior_revision"]
const INTENT_FIELDS: PackedStringArray = ["schema_version", "exterior_sector_id", "exterior_entity_guid"]


class AnchorValue extends RefCounted:
	var interior_id: String
	var exterior_sector_id: String
	var exterior_entity_guid: String
	var plot_id: String
	var entry_position: Vector3
	var cell_coordinate: Vector3i
	var bounds_min: Vector3
	var bounds_max: Vector3
	var streaming_reference: String
	var revision: int = 1
	var exterior_revision: int = 0

	func to_descriptor() -> Dictionary:
		return {
			"schema_version": 1,
			"exterior_sector_id": exterior_sector_id,
			"exterior_entity_guid": exterior_entity_guid,
			"plot_id": plot_id,
			"entry_position": [entry_position.x, entry_position.y, entry_position.z],
			"cell_coordinate": [cell_coordinate.x, cell_coordinate.y, cell_coordinate.z],
			"bounds_min": [bounds_min.x, bounds_min.y, bounds_min.z],
			"bounds_max": [bounds_max.x, bounds_max.y, bounds_max.z],
			"streaming_reference": streaming_reference,
		}

	func to_dict() -> Dictionary:
		var record: Dictionary = to_descriptor()
		record["interior_id"] = interior_id
		record["revision"] = revision
		record["exterior_revision"] = exterior_revision
		return record


static func parse_server_descriptor(input: Variant) -> Dictionary:
	if not input is Dictionary or not _closed(input, DESCRIPTOR_FIELDS):
		return _invalid("Server descriptor must contain exactly the supported fields.")
	var data: Dictionary = input
	if not _integer(data["schema_version"], 1, 1):
		return _invalid("Unsupported interior schema version.")
	for field: String in ["exterior_sector_id", "exterior_entity_guid", "plot_id", "streaming_reference"]:
		if not valid_id(data[field]):
			return _invalid("%s must be a bounded non-empty identifier." % field)
	for field: String in ["entry_position", "bounds_min", "bounds_max"]:
		if not _vector(data[field]):
			return _invalid("%s must contain three finite bounded world-yard components." % field)
	if not data["cell_coordinate"] is Array or data["cell_coordinate"].size() != 3:
		return _invalid("Cell coordinate must contain exactly three integers.")
	for component: Variant in data["cell_coordinate"]:
		if not _integer(component, -MAX_CELL_COMPONENT, MAX_CELL_COMPONENT):
			return _invalid("Cell coordinate must contain bounded integers.")
	var entry: Vector3 = _to_vector(data["entry_position"])
	var lower: Vector3 = _to_vector(data["bounds_min"])
	var upper: Vector3 = _to_vector(data["bounds_max"])
	if upper.x <= lower.x or upper.y <= lower.y or upper.z <= lower.z:
		return _invalid("Cell bounds must have positive extent on every axis.")
	if entry.x < lower.x or entry.y < lower.y or entry.z < lower.z or entry.x >= upper.x or entry.y >= upper.y or entry.z >= upper.z:
		return _invalid("Entry anchor must lie in the half-open cell bounds.")
	var anchor: AnchorValue = AnchorValue.new()
	anchor.exterior_sector_id = data["exterior_sector_id"]
	anchor.exterior_entity_guid = data["exterior_entity_guid"]
	anchor.plot_id = data["plot_id"]
	anchor.entry_position = entry
	anchor.cell_coordinate = Vector3i(int(data["cell_coordinate"][0]), int(data["cell_coordinate"][1]), int(data["cell_coordinate"][2]))
	anchor.bounds_min = lower
	anchor.bounds_max = upper
	anchor.streaming_reference = data["streaming_reference"]
	anchor.interior_id = Guid.uuid_v5(Guid.NAMESPACE_URL_UUID, "project0/interior/v1:" + JSON.stringify([anchor.exterior_sector_id, anchor.exterior_entity_guid, anchor.plot_id]))
	if anchor.interior_id.is_empty():
		return _invalid("Interior identity derivation failed.")
	return {"outcome": "ok", "detail": "", "anchor": anchor}


static func parse_record(input: Variant) -> Dictionary:
	var fields: PackedStringArray = DESCRIPTOR_FIELDS.duplicate()
	fields.append_array(RECORD_FIELDS)
	if not input is Dictionary or not _closed(input, fields):
		return _invalid("Persisted record must contain exactly the supported fields.")
	var data: Dictionary = input
	var descriptor: Dictionary = {}
	for field: String in DESCRIPTOR_FIELDS:
		descriptor[field] = data[field]
	var parsed: Dictionary = parse_server_descriptor(descriptor)
	if parsed["outcome"] != "ok":
		return parsed
	var anchor: AnchorValue = parsed["anchor"]
	if data["interior_id"] != anchor.interior_id or not _integer(data["revision"], 1, 1) or not _integer(data["exterior_revision"], 0, MAX_REVISION):
		return _invalid("Persisted identity or revision metadata is incompatible.")
	anchor.exterior_revision = int(data["exterior_revision"])
	return parsed


static func parse_entry_intent(input: Variant) -> Dictionary:
	if not input is Dictionary or not _closed(input, INTENT_FIELDS):
		return _invalid("Entry intent may contain only schema version and exterior reference.")
	var data: Dictionary = input
	if not _integer(data["schema_version"], 1, 1) or not valid_id(data["exterior_sector_id"]) or not valid_id(data["exterior_entity_guid"]):
		return _invalid("Entry intent has invalid version or exterior reference.")
	return {"outcome": "ok", "detail": "", "intent": data.duplicate(true)}


static func valid_id(value: Variant) -> bool:
	return value is String and not value.is_empty() and value.length() <= MAX_ID_LENGTH


static func _closed(data: Dictionary, fields: PackedStringArray) -> bool:
	if data.size() != fields.size():
		return false
	for field: String in fields:
		if not data.has(field):
			return false
	return true


static func _integer(value: Variant, lower: int, upper: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= lower and float(value) <= upper and float(value) == floorf(float(value))


static func _vector(value: Variant) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for component: Variant in value:
		if not (component is int or component is float) or not is_finite(float(component)) or absf(float(component)) > MAX_WORLD_COMPONENT:
			return false
	return true


static func _to_vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


static func _invalid(detail: String) -> Dictionary:
	return {"outcome": "invalid_anchor", "detail": detail}
