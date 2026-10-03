extends RefCounted
class_name ItemCapacityProfile
## Governing #1440 / decision #310. Pure authored bounds, not carrying authority.

const SCHEMA_VERSION: int = 1
const MAX_PIN_LENGTH: int = 128
const MAX_SLOT_COUNT: int = 1024
const FIELDS: PackedStringArray = [
	"schema_version", "profile_id", "profile_revision", "definition_id",
	"definition_revision", "slot_count",
]
const PINS: PackedStringArray = [
	"profile_id", "profile_revision", "definition_id", "definition_revision",
]

var _wire: Dictionary


## Consumers use the validating factory; retained and returned wire values are copies.
func _init(wire: Dictionary) -> void:
	_wire = wire.duplicate(true)


static func from_wire_dict(value: Variant) -> Dictionary:
	if not (value is Dictionary):
		return _fail("malformed", "capacity profile must be a dictionary")
	var wire: Dictionary = value
	if wire.size() != FIELDS.size():
		return _fail("malformed", "capacity fields are closed and required")
	for key: Variant in wire:
		if not (key is String) or not FIELDS.has(key):
			return _fail("malformed", "capacity fields are closed and required")
	if not (wire.schema_version is int) or wire.schema_version != SCHEMA_VERSION:
		return _fail("unsupported_version", "unsupported capacity schema_version")
	for pin: String in PINS:
		if not _valid_pin(wire[pin]):
			return _fail("malformed", "capacity pins must be bounded nonblank strings")
	if not (wire.slot_count is int):
		return _fail("malformed", "slot_count must be an integer")
	if wire.slot_count < 1 or wire.slot_count > MAX_SLOT_COUNT:
		return _fail("out_of_bounds", "slot_count is outside encoding bounds")
	return {"outcome": "ok", "detail": "", "profile": ItemCapacityProfile.new(wire)}


func to_wire_dict() -> Dictionary:
	return _wire.duplicate(true)


static func _valid_pin(value: Variant) -> bool:
	if not (value is String):
		return false
	var pin: String = value
	return not pin.strip_edges().is_empty() and pin.length() <= MAX_PIN_LENGTH


static func _fail(outcome: String, detail: String) -> Dictionary:
	return {"outcome": outcome, "detail": detail, "profile": null}
