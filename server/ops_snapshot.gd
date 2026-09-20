extends RefCounted
class_name OpsSnapshot

const ServerHealthScript: Script = preload("res://server/server_health.gd")

const SNAPSHOT_SCHEMA_VERSION: int = 1
const OUTCOME_OK: String = "ok"
const OUTCOME_INVALID: String = "invalid"
const OUTCOME_UNSUPPORTED_VERSION: String = "unsupported_version"
const MAX_SERVER_ID_LENGTH: int = 64
const MAX_SERVER_VERSION_LENGTH: int = 128
const MAX_DEGRADED_REASON_LENGTH: int = 160
const MAX_EXTENSION_KEYS: int = 32
const MAX_EXTENSION_VALUE_LENGTH: int = 256

const SERVER_TYPE_WORLD: String = "world"
const SERVER_TYPE_LOGIN: String = "login"
const VALID_SERVER_TYPES: Array[String] = [SERVER_TYPE_WORLD, SERVER_TYPE_LOGIN]

static func build(inputs: Dictionary) -> Dictionary:
	var server_id: Variant = inputs.get("server_id")
	if not _valid_text(server_id, MAX_SERVER_ID_LENGTH):
		return _reject("server_id must be a non-empty bounded string")
	var server_type: Variant = inputs.get("server_type")
	if not (server_type is String) or not VALID_SERVER_TYPES.has(server_type):
		return _reject("server_type is unsupported")
	var server_version: Variant = inputs.get("server_version")
	if not _valid_text(server_version, MAX_SERVER_VERSION_LENGTH):
		return _reject("server_version must be a non-empty bounded string")
	var degraded_reason: Variant = inputs.get("degraded_reason", "")
	if not (degraded_reason is String) or degraded_reason.length() > MAX_DEGRADED_REASON_LENGTH:
		return _reject("degraded_reason is too long")
	var extension_schema_version: Variant = inputs.get("extension_schema_version", 1)
	if not (extension_schema_version is int) or extension_schema_version <= 0:
		return _reject("extension_schema_version must be a positive int")
	var extension: Variant = inputs.get("extension", {})
	if not _valid_extension(extension):
		return _reject("extension is not bounded")

	var health_inputs: Dictionary = inputs.duplicate()
	var health_result: Dictionary = ServerHealthScript.build_snapshot(health_inputs)
	if health_result["outcome"] != ServerHealthScript.OUTCOME_OK:
		return health_result
	var snapshot: Dictionary = health_result["snapshot"].duplicate()
	snapshot["snapshot_schema_version"] = SNAPSHOT_SCHEMA_VERSION
	snapshot["server_id"] = server_id
	snapshot["server_type"] = server_type
	snapshot["server_version"] = server_version
	snapshot["degraded_reason"] = degraded_reason
	snapshot["extension_schema_version"] = extension_schema_version
	snapshot["extension"] = extension
	return {"outcome": OUTCOME_OK, "snapshot": snapshot}

static func from_wire_dict(wire: Variant) -> Dictionary:
	if not (wire is Dictionary):
		return _reject("wire is not a Dictionary")
	var data: Dictionary = wire
	if int(data.get("snapshot_schema_version", -1)) != SNAPSHOT_SCHEMA_VERSION:
		return {"outcome": OUTCOME_UNSUPPORTED_VERSION, "detail": "unsupported snapshot schema"}
	return build(data)

static func _valid_text(value: Variant, max_length: int) -> bool:
	return value is String and not String(value).strip_edges().is_empty() and String(value).length() <= max_length

static func _valid_extension(value: Variant) -> bool:
	if not (value is Dictionary) or value.size() > MAX_EXTENSION_KEYS:
		return false
	for key: Variant in value.keys():
		if not _valid_text(key, 64):
			return false
		var item: Variant = value[key]
		if item is String and String(item).length() > MAX_EXTENSION_VALUE_LENGTH:
			return false
		if item is Array or item is Dictionary:
			return false
	return true

static func _reject(detail: String) -> Dictionary:
	return {"outcome": OUTCOME_INVALID, "detail": detail}
