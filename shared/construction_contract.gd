extends RefCounted
class_name ConstructionContract
## #840 first worked parse_client_request tracer. Pure detached values only.
## Remaining verb/nested-schema/actor/ack closure must pass later public cycles
## before delivery; this module does not grant action or persistence authority.

const REQUEST_FIELDS: PackedStringArray = [
	"schema_version", "client_sequence", "verb", "expected_revision", "target",
	"grid", "orientation_degrees", "blueprint", "materials",
]


static func parse_client_request(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {"outcome": "invalid_request", "detail": "request must be an object", "request": null}
	var data: Dictionary = raw
	if data.size() != REQUEST_FIELDS.size() or not data.has_all(REQUEST_FIELDS):
		return {"outcome": "invalid_request", "detail": "request fields are closed and required", "request": null}
	for key: Variant in data:
		if not (key is String) or not REQUEST_FIELDS.has(key):
			return {"outcome": "invalid_request", "detail": "request keys must be strings", "request": null}
	if not (data["orientation_degrees"] is int or data["orientation_degrees"] is float):
		return {"outcome": "invalid_request", "detail": "orientation must be numeric", "request": null}
	var request: Dictionary = data.duplicate(true)
	request["orientation_degrees"] = float(data["orientation_degrees"])
	return {"outcome": "ok", "detail": "", "request": request}
