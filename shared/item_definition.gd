extends RefCounted
class_name ItemDefinition
## Closed, pinned fixed metadata from decision #306; governing issue #1341.
## Pure structural validation only. This value grants no item/owner authority.
## Existing ItemContract owns slot/category/binding/effect semantics.

const ItemMetadata = preload("res://shared/item_contract.gd")
const SCHEMA_VERSION: int = 1
const FIELDS: PackedStringArray = [
	"schema_version", "definition_id", "definition_revision", "item_class", "slot",
	"category", "maximum_stack", "binding_policy", "base_effect",
]

var _wire: Dictionary


func _init(wire: Dictionary) -> void:
	_wire = wire.duplicate(true)


static func from_wire_dict(wire: Variant) -> Dictionary:
	if not (wire is Dictionary):
		return _fail("malformed", "definition must be a dictionary")
	var data: Dictionary = wire
	if not _has_exact_fields(data):
		return _fail("malformed", "definition fields are closed and required")
	if not (data.schema_version is int) or data.schema_version != SCHEMA_VERSION:
		return _fail("unsupported_version", "unsupported definition schema_version")
	if not _is_identifier(data.definition_id) or not _is_identifier(data.definition_revision):
		return _fail("invalid_definition", "definition identity and revision must be nonempty strings")
	if not (data.maximum_stack is int) or data.maximum_stack <= 0:
		return _fail("invalid_definition", "maximum_stack must be a positive integer")
	var metadata: Dictionary = ItemMetadata.from_wire_dict({
		"schema_version": SCHEMA_VERSION,
		"item_id": data.definition_id,
		"item_class": data.item_class,
		"slot": data.slot,
		"category": data.category,
		"binding": data.binding_policy,
		"base_effect": data.base_effect,
	})
	if metadata.outcome != ItemMetadata.OUTCOME_OK:
		return _fail("invalid_definition", "fixed metadata: " + String(metadata.detail))
	return {"outcome": "ok", "detail": "", "definition": ItemDefinition.new(data)}


func to_wire_dict() -> Dictionary:
	return _wire.duplicate(true)


static func _has_exact_fields(data: Dictionary) -> bool:
	if data.size() != FIELDS.size():
		return false
	for key: Variant in data:
		if not (key is String) or not FIELDS.has(key):
			return false
	return true


static func _is_identifier(value: Variant) -> bool:
	return value is String and not String(value).strip_edges().is_empty()


static func _fail(outcome: String, detail: String) -> Dictionary:
	return {"outcome": outcome, "detail": detail, "definition": null}
