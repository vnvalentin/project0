extends RefCounted
class_name ItemInstance
## Closed instance identity from decision #306; governing issue #1341.
## Parsing validates structure against a pinned definition, never actor authority,
## real acquisition facts, global GUID uniqueness, or a committed ledger revision.

const Definition = preload("res://shared/item_definition.gd")
const SCHEMA_VERSION: int = 1
const FIELDS: PackedStringArray = [
	"schema_version", "instance_id", "definition_id", "definition_revision", "quantity",
	"owner", "location", "bound_character_id", "acquisition", "instance_revision", "terminal",
]
const OWNER_FIELDS: PackedStringArray = ["kind", "id"]
const EQUIPPED_FIELDS: PackedStringArray = ["kind", "slot"]
const CARRIED_FIELDS: PackedStringArray = ["kind", "container_instance_id", "index"]
const LOOT_FIELDS: PackedStringArray = ["kind", "source_id", "index"]
const TERMINAL_FIELDS: PackedStringArray = ["reason", "server_tick", "operation_id"]
const TERMINAL_REASONS: PackedStringArray = ["consumed", "destroyed", "merged"]
const ACQUISITION_FIELDS: PackedStringArray = ["source_id", "operation_id", "server_tick"]

var _wire: Dictionary


func _init(wire: Dictionary) -> void:
	_wire = wire.duplicate(true)


static func from_wire_dict(wire: Variant, definition: ItemDefinition) -> Dictionary:
	if not _has_exact_fields(wire, FIELDS):
		return _fail("malformed", "instance fields are closed and required")
	var data: Dictionary = wire
	if not (data.schema_version is int) or data.schema_version != SCHEMA_VERSION:
		return _fail("unsupported_version", "unsupported instance schema_version")
	if definition == null:
		return _fail("unpinned_definition", "a validated pinned definition is required")
	var fixed: Dictionary = definition.to_wire_dict()
	if Definition.from_wire_dict(fixed).definition == null:
		return _fail("unpinned_definition", "definition is invalid")
	if not _is_identifier(data.instance_id):
		return _fail("invalid_instance", "instance_id must be a nonempty string")
	if not _is_identifier(data.definition_id) or not _is_identifier(data.definition_revision):
		return _fail("unpinned_definition", "definition identity and revision must be nonempty strings")
	if data.definition_id != fixed.definition_id or data.definition_revision != fixed.definition_revision:
		return _fail("unpinned_definition", "instance must match the pinned definition and revision")
	if not (data.quantity is int) or data.quantity <= 0 or data.quantity > fixed.maximum_stack:
		return _fail("invalid_instance", "quantity must be a positive integer within maximum_stack")
	if not _is_nonnegative_integer(data.instance_revision):
		return _fail("invalid_instance", "instance_revision must be a nonnegative integer")
	if not (data.bound_character_id is String):
		return _fail("invalid_instance", "bound_character_id must be a string")
	if data.bound_character_id != "" and (not _is_identifier(data.bound_character_id) or fixed.binding_policy == "none"):
		return _fail("invalid_instance", "bound character requires a binding policy and a nonempty identifier")
	if not _valid_acquisition(data.acquisition):
		return _fail("invalid_instance", "acquisition provenance is invalid")
	if data.terminal == null:
		if not _valid_owner_location(data, fixed):
			return _fail("invalid_location", "owner and typed location are incompatible")
	elif data.owner != null or data.location != null or not _valid_terminal(data.terminal):
		return _fail("invalid_terminal", "retired records require terminal metadata and no live owner or location")
	return {"outcome": "ok", "detail": "", "instance": ItemInstance.new(data)}


func to_wire_dict() -> Dictionary:
	return _wire.duplicate(true)


static func _valid_acquisition(value: Variant) -> bool:
	if not _has_exact_fields(value, ACQUISITION_FIELDS):
		return false
	var acquisition: Dictionary = value
	return _is_identifier(acquisition.source_id) and _is_identifier(acquisition.operation_id) \
		and _is_nonnegative_integer(acquisition.server_tick)


static func _has_exact_fields(value: Variant, fields: PackedStringArray) -> bool:
	if not (value is Dictionary):
		return false
	var data: Dictionary = value
	if data.size() != fields.size():
		return false
	for key: Variant in data:
		if not (key is String) or not fields.has(key):
			return false
	return true


static func _is_identifier(value: Variant) -> bool:
	return value is String and not String(value).strip_edges().is_empty()


static func _is_nonnegative_integer(value: Variant) -> bool:
	return value is int and value >= 0


static func _fail(outcome: String, detail: String) -> Dictionary:
	return {"outcome": outcome, "detail": detail, "instance": null}


static func _valid_owner_location(data: Dictionary, fixed: Dictionary) -> bool:
	if not _has_exact_fields(data.owner, OWNER_FIELDS) or not (data.location is Dictionary):
		return false
	var owner: Dictionary = data.owner
	var location: Dictionary = data.location
	if not _is_identifier(owner.id) or not (owner.kind is String) or not (location.get("kind") is String):
		return false
	match location.kind:
		"equipped":
			return owner.kind == "character" and _has_exact_fields(location, EQUIPPED_FIELDS) \
				and location.slot is String and location.slot == fixed.slot
		"carried":
			return owner.kind == "character" and _has_exact_fields(location, CARRIED_FIELDS) \
				and fixed.slot != "bags" and _is_identifier(location.container_instance_id) \
				and location.container_instance_id != data.instance_id and _is_nonnegative_integer(location.index)
		"loot_position":
			return owner.kind == "world_container" and _has_exact_fields(location, LOOT_FIELDS) \
				and _is_identifier(location.source_id) and location.source_id == owner.id \
				and _is_nonnegative_integer(location.index)
	return false


static func _valid_terminal(value: Variant) -> bool:
	if not _has_exact_fields(value, TERMINAL_FIELDS):
		return false
	var terminal: Dictionary = value
	return terminal.reason is String and TERMINAL_REASONS.has(terminal.reason) \
		and _is_nonnegative_integer(terminal.server_tick) and _is_identifier(terminal.operation_id)
