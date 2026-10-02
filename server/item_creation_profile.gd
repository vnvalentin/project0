extends RefCounted
class_name ItemCreationProfile
## Governing #950. Authored integer rules; no default/live tuning or item authority.

const FIELDS: PackedStringArray = [
	"schema_version", "profile_id", "profile_revision", "blueprint_id", "blueprint_revision",
	"tuning_version", "arithmetic_version", "inputs", "outputs",
]
const INPUTS: PackedStringArray = ["material_purity", "catalyst_quality", "workstation_parameter"]
const OUTPUTS: PackedStringArray = ["purity", "quality", "durability"]

var _wire: Dictionary


func _init(wire: Dictionary) -> void:
	_wire = wire.duplicate(true)


static func from_wire_dict(value: Variant) -> Dictionary:
	if not _closed(value, FIELDS):
		return {"outcome": "malformed", "profile": null}
	var wire: Dictionary = value
	if not (wire.schema_version is int) or wire.schema_version != 1 \
		or not (wire.arithmetic_version is int) or wire.arithmetic_version != 1:
		return {"outcome": "unsupported_version", "profile": null}
	if not _closed(wire.inputs, INPUTS) or not _closed(wire.outputs, OUTPUTS):
		return {"outcome": "malformed", "profile": null}
	return {"outcome": "ok", "profile": ItemCreationProfile.new(wire)}


func to_wire_dict() -> Dictionary:
	return _wire.duplicate(true)


func derive(value: Variant) -> Dictionary:
	if not _closed(value, INPUTS):
		return {"outcome": "malformed", "properties": null}
	var inputs: Dictionary = value
	var values: Dictionary = {}
	var units: Dictionary = {}
	for key: String in OUTPUTS:
		var rule: Dictionary = _wire.outputs[key]
		var numerator: int = rule.offset
		for input: String in INPUTS:
			numerator += int(inputs[input]) * int(rule.weights[input])
		var divisor: int = rule.divisor
		@warning_ignore("integer_division")
		var derived: int = numerator / divisor
		values[key] = clampi(derived, int(rule.minimum), int(rule.maximum))
		units[key] = rule.unit
	return {"outcome": "ok", "properties": {
		"schema_version": 1, "profile_id": _wire.profile_id, "profile_revision": _wire.profile_revision,
		"blueprint_id": _wire.blueprint_id, "blueprint_revision": _wire.blueprint_revision,
		"tuning_version": _wire.tuning_version, "arithmetic_version": _wire.arithmetic_version,
		"profile_sha256": JSON.stringify(_wire, "", true).sha256_text(),
		"inputs": inputs.duplicate(true), "values": values, "units": units,
	}}


static func _closed(value: Variant, fields: PackedStringArray) -> bool:
	if not (value is Dictionary):
		return false
	var data: Dictionary = value
	if data.size() != fields.size():
		return false
	for key: Variant in data:
		if not (key is String) or not fields.has(key):
			return false
	return true
