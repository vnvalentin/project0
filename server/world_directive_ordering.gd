extends RefCounted
class_name WorldDirectiveOrdering
## Slice 192: deterministic ordering and replay identity for accepted semantic
## directives. This seam owns no persistence, clock, LLM, builder, or runtime.

const OUTCOME_OK: String = "ok"
const OUTCOME_INVALID: String = "invalid"
const REQUIRED_FIELDS: Array[String] = [
	"directive_id", "canonical_event_sequence", "policy_priority", "source_scope",
	"target_sector_x", "target_sector_z", "base_revision", "input_snapshot_hash",
	"schema_version", "builder_version", "tuning_version", "resource_set_version",
]

static func order(directives: Array) -> Dictionary:
	var normalized: Array[Dictionary] = []
	for item: Variant in directives:
		var checked: Dictionary = _validate(item)
		if checked["outcome"] != OUTCOME_OK:
			return checked
		normalized.append(checked["directive"])
	normalized.sort_custom(Callable(WorldDirectiveOrdering, "_comes_before"))
	return {"outcome": OUTCOME_OK, "directives": normalized}

static func replay_identity(directive: Dictionary, world_seed: String) -> Dictionary:
	var checked: Dictionary = _validate(directive)
	if checked["outcome"] != OUTCOME_OK:
		return checked
	if world_seed.strip_edges().is_empty():
		return {"outcome": OUTCOME_INVALID, "reason": "missing_world_seed"}
	var item: Dictionary = checked["directive"]
	var seed_input: String = "%s|%d|%d|%d|%s|%d|%d|%d|%s|%s|%s|%s|%s" % [
		world_seed, item["target_sector_x"], item["target_sector_z"], item["base_revision"],
		item["directive_id"], item["canonical_event_sequence"], item["policy_priority"],
		item["source_scope"].hash(), item["input_snapshot_hash"], item["schema_version"],
		item["builder_version"], item["tuning_version"], item["resource_set_version"],
	]
	return {"outcome": OUTCOME_OK, "replay_key": seed_input, "seed_input": seed_input}

static func _validate(value: Variant) -> Dictionary:
	if not (value is Dictionary):
		return {"outcome": OUTCOME_INVALID, "reason": "directive_not_object"}
	var directive: Dictionary = value
	for field: String in REQUIRED_FIELDS:
		if not directive.has(field):
			return {"outcome": OUTCOME_INVALID, "reason": "missing_%s" % field}
	if not directive["directive_id"] is String or String(directive["directive_id"]).strip_edges().is_empty():
		return {"outcome": OUTCOME_INVALID, "reason": "invalid_directive_id"}
	for field: String in ["canonical_event_sequence", "policy_priority", "target_sector_x", "target_sector_z", "base_revision", "schema_version"]:
		if not directive[field] is int:
			return {"outcome": OUTCOME_INVALID, "reason": "invalid_%s" % field}
	for field: String in ["builder_version", "tuning_version", "resource_set_version", "source_scope", "input_snapshot_hash"]:
		if not directive[field] is String or String(directive[field]).strip_edges().is_empty():
			return {"outcome": OUTCOME_INVALID, "reason": "invalid_%s" % field}
	return {"outcome": OUTCOME_OK, "directive": directive.duplicate(true)}

static func _comes_before(left: Dictionary, right: Dictionary) -> bool:
	for field: String in ["canonical_event_sequence", "policy_priority"]:
		if left[field] != right[field]:
			return left[field] < right[field]
	for field: String in ["source_scope", "directive_id"]:
		if left[field] != right[field]:
			return String(left[field]) < String(right[field])
	return false