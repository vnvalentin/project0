extends RefCounted
class_name ConstructionContract
## #840 first worked parse_client_request tracer. Pure detached values only.
## Remaining verb/nested-schema/actor/ack closure must pass later public cycles
## before delivery; this module does not grant action or persistence authority.

const REQUEST_FIELDS: PackedStringArray = [
	"schema_version", "client_sequence", "verb", "expected_revision", "target",
	"grid", "orientation_degrees", "blueprint", "materials",
]


const REQUEST_VERBS: PackedStringArray = [
	"PLACE", "REMOVE", "ROTATE", "ANCHOR", "CONNECT", "REPAIR",
	"UPGRADE", "CLAIM", "PERMIT", "BLUEPRINT", "MEASURE", "INSPECT",
]

const MAX_REQUEST_VALUE_NODES: int = 2048
const MAX_REQUEST_CONTAINERS: int = 256
const MAX_REQUEST_CONTAINER_DEPTH: int = 32


static func parse_client_request(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {"outcome": "invalid_request", "detail": "request must be an object", "request": null}
	var data: Dictionary = raw
	if data.size() != REQUEST_FIELDS.size() or not data.has_all(REQUEST_FIELDS):
		return {"outcome": "invalid_request", "detail": "request fields are closed and required", "request": null}
	for key: Variant in data:
		if not (key is String) or not REQUEST_FIELDS.has(key):
			return {"outcome": "invalid_request", "detail": "request keys must be strings", "request": null}
	if not (data["verb"] is String) or not REQUEST_VERBS.has(data["verb"]):
		return {"outcome": "invalid_request", "detail": "verb must belong to the closed request set", "request": null}
	if not (data["orientation_degrees"] is int or data["orientation_degrees"] is float):
		return {"outcome": "invalid_request", "detail": "orientation must be numeric", "request": null}
	if not _contains_only_wire_values(data):
		return {"outcome": "invalid_request", "detail": "request values must use bounded detached wire types", "request": null}
	var request: Dictionary = data.duplicate(true)
	request["orientation_degrees"] = float(data["orientation_degrees"])
	return {"outcome": "ok", "detail": "", "request": request}


static func _contains_only_wire_values(value: Variant) -> bool:
	var pending: Array[Dictionary] = [{"value": value, "depth": 0}]
	var inspected_containers: Array[Variant] = []
	var value_node_count: int = 0
	var container_count: int = 0
	while not pending.is_empty():
		var entry: Dictionary = pending.pop_back()
		var current: Variant = entry["value"]
		var depth: int = entry["depth"]
		value_node_count += 1
		if value_node_count > MAX_REQUEST_VALUE_NODES:
			return false
		match typeof(current):
			TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
				continue
			TYPE_ARRAY:
				if value_node_count + pending.size() + current.size() > MAX_REQUEST_VALUE_NODES:
					return false
				container_count += 1
				if container_count > MAX_REQUEST_CONTAINERS or depth + 1 > MAX_REQUEST_CONTAINER_DEPTH:
					return false
				for inspected: Variant in inspected_containers:
					if is_same(current, inspected):
						return false
				inspected_containers.append(current)
				for item: Variant in current:
					pending.append({"value": item, "depth": depth + 1})
			TYPE_DICTIONARY:
				if value_node_count + pending.size() + current.size() > MAX_REQUEST_VALUE_NODES:
					return false
				container_count += 1
				if container_count > MAX_REQUEST_CONTAINERS or depth + 1 > MAX_REQUEST_CONTAINER_DEPTH:
					return false
				for inspected: Variant in inspected_containers:
					if is_same(current, inspected):
						return false
				inspected_containers.append(current)
				var dictionary: Dictionary = current
				for key: Variant in dictionary:
					if not (key is String):
						return false
					pending.append({"value": dictionary[key], "depth": depth + 1})
			_:
				return false
	return true
