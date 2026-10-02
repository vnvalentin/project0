extends RefCounted
class_name ItemCreationProfile
## Governing #950. Authored integer rules; no default/live tuning or item authority.

const FIELDS: PackedStringArray = [
	"schema_version", "profile_id", "profile_revision", "blueprint_id", "blueprint_revision",
	"tuning_version", "arithmetic_version", "inputs", "outputs",
]
const INPUTS: PackedStringArray = ["material_purity", "catalyst_quality", "workstation_parameter"]
const OUTPUTS: PackedStringArray = ["purity", "quality", "durability"]

const INPUT_FIELDS: PackedStringArray = ["unit", "minimum", "maximum"]
const OUTPUT_FIELDS: PackedStringArray = ["unit", "minimum", "maximum", "offset", "divisor", "weights"]
## Encoding ceiling, not balance tuning. Three products plus offset fit exactly in int64/JSON.
const MAX_COMPONENT: int = 1000000
const MAX_PIN_LENGTH: int = 128

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
	for pin: String in ["profile_id", "profile_revision", "blueprint_id", "blueprint_revision", "tuning_version"]:
		if not _valid_pin(wire[pin]):
			return {"outcome": "malformed", "profile": null}
	for key: String in INPUTS:
		if not _closed(wire.inputs[key], INPUT_FIELDS) or not _valid_bounds(wire.inputs[key]):
			return {"outcome": "malformed", "profile": null}
	for key: String in OUTPUTS:
		if not _closed(wire.outputs[key], OUTPUT_FIELDS) or not _valid_bounds(wire.outputs[key]):
			return {"outcome": "malformed", "profile": null}
		var rule: Dictionary = wire.outputs[key]
		if not _bounded_integer(rule.offset) or not _bounded_integer(rule.divisor, 1) \
			or not _closed(rule.weights, INPUTS):
			return {"outcome": "malformed", "profile": null}
		for input: String in INPUTS:
			if not _bounded_integer(rule.weights[input]):
				return {"outcome": "malformed", "profile": null}
	return {"outcome": "ok", "profile": ItemCreationProfile.new(wire)}


func to_wire_dict() -> Dictionary:
	return _wire.duplicate(true)


func derive(value: Variant) -> Dictionary:
	if not _closed(value, INPUTS):
		return {"outcome": "malformed", "properties": null}
	var inputs: Dictionary = value
	for input: String in INPUTS:
		var bounds: Dictionary = _wire.inputs[input]
		if not _bounded_integer(inputs[input]) or inputs[input] < bounds.minimum \
			or inputs[input] > bounds.maximum:
			return {"outcome": "malformed", "properties": null}
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


static func _valid_bounds(rule: Dictionary) -> bool:
	return _valid_pin(rule.unit) and _bounded_integer(rule.minimum) \
		and _bounded_integer(rule.maximum) and rule.minimum <= rule.maximum


static func _bounded_integer(value: Variant, minimum: int = 0) -> bool:
	return value is int and value >= minimum and value <= MAX_COMPONENT


static func _valid_pin(value: Variant) -> bool:
	if not (value is String):
		return false
	var pin: String = value
	if pin.is_empty() or pin.length() > MAX_PIN_LENGTH or pin != pin.strip_edges():
		return false
	for index: int in range(pin.length()):
		var codepoint: int = pin.unicode_at(index)
		if codepoint < 32 or (codepoint >= 127 and codepoint <= 159):
			return false
	return true
