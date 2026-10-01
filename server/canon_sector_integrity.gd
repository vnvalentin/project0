extends RefCounted
## Slice 1343: fail-closed integrity inspection of a known Canon sector before it
## is presented. Pure reads over repository results; it never repairs,
## regenerates, substitutes or writes Canon.

const SectorBlueprintSchemaScript: Script = preload("res://shared/sector_blueprint_schema.gd")
const CanonEntityGuidScript: Script = preload("res://shared/canon_entity_guid.gd")
const CanonRepositoryScript: Script = preload("res://server/canon_repository.gd")
const CanonMutationRepositoryScript: Script = preload("res://server/canon_mutation_repository.gd")

const OUTCOME_OK: String = "ok"
const OUTCOME_ABSENT: String = "absent"
const OUTCOME_DAMAGED: String = "damaged"

const FAILURE_BASE_MISSING: String = "base_missing"
const FAILURE_BASE_UNREADABLE: String = "base_unreadable"
const FAILURE_BLUEPRINT_CORRUPT: String = "blueprint_corrupt"
const FAILURE_MUTATION_CORRUPT: String = "mutation_corrupt"
const FAILURE_REPLAY_INCONSISTENT: String = "replay_inconsistent"

## Telemetry rejects string values of 200+ characters as free text.
const MAX_DETAIL_LENGTH: int = 180


## Classifies a stored base record. `history` (the sector's list_mutations
## result) is consulted only when the base is absent, to tell a missing known
## sector from one that was never generated.
static func inspect_base(sector_id: String, canon_result: Dictionary, history: Dictionary) -> Dictionary:
	var outcome: String = String(canon_result.get("outcome", ""))
	if outcome == CanonRepositoryScript.OUTCOME_NOT_FOUND:
		if history.get("outcome") != CanonMutationRepositoryScript.OUTCOME_OK:
			return _damaged(FAILURE_BASE_UNREADABLE, "base absent and history unreadable (%s): %s" % [history.get("outcome"), history.get("detail", "")])
		var rows: Array = history.get("mutations", [])
		if rows.is_empty():
			return {"outcome": OUTCOME_ABSENT}
		return _damaged(FAILURE_BASE_MISSING, "%d mutation rows exist without a base record" % rows.size())
	if outcome != CanonRepositoryScript.OUTCOME_OK:
		return _damaged(FAILURE_BASE_UNREADABLE, "base read failed (%s): %s" % [outcome, canon_result.get("detail", "")])
	var sector: Variant = canon_result.get("sector")
	var blueprint: Variant = (sector as Dictionary).get("blueprint") if sector is Dictionary else null
	var validation: Dictionary = SectorBlueprintSchemaScript.validate(blueprint)
	if validation["outcome"] != SectorBlueprintSchemaScript.OUTCOME_VALID:
		return _damaged(FAILURE_BLUEPRINT_CORRUPT, "%s: %s" % [validation["outcome"], validation["detail"]])
	if String((blueprint as Dictionary).get("sector_id", "")) != sector_id:
		return _damaged(FAILURE_BLUEPRINT_CORRUPT, "stored blueprint names sector '%s'" % (blueprint as Dictionary).get("sector_id"))
	return {"outcome": OUTCOME_OK, "blueprint": blueprint}


## Validates the ordered mutation history against its base blueprint: every
## row must be well-formed, contiguous from revision 1, belong to the sector
## and address an entity that exists in the base.
static func inspect_history(sector_id: String, blueprint: Dictionary, history: Dictionary) -> Dictionary:
	if history.get("outcome") != CanonMutationRepositoryScript.OUTCOME_OK:
		return _damaged(FAILURE_BASE_UNREADABLE, "history read failed (%s): %s" % [history.get("outcome"), history.get("detail", "")])
	var mutations: Array = history.get("mutations", [])
	for index: int in mutations.size():
		if not (mutations[index] is Dictionary):
			return _damaged(FAILURE_MUTATION_CORRUPT, "row %d is not an object" % index)
		var row: Dictionary = mutations[index]
		var label: String = "row %d (%s)" % [index, String(row.get("event_id", "?"))]
		if not (row.get("payload") is Dictionary):
			return _damaged(FAILURE_MUTATION_CORRUPT, "%s payload is not an object" % label)
		if not CanonMutationRepositoryScript.SUPPORTED_MUTATION_KINDS.has(String(row.get("mutation_kind", ""))):
			return _damaged(FAILURE_MUTATION_CORRUPT, "%s has unsupported kind '%s'" % [label, row.get("mutation_kind")])
		if not CanonMutationRepositoryScript.SUPPORTED_SCHEMA_VERSIONS.has(_int_or(row.get("schema_version"), -1)):
			return _damaged(FAILURE_MUTATION_CORRUPT, "%s has unsupported schema_version %s" % [label, row.get("schema_version")])
		if String(row.get("sector_id", "")) != sector_id:
			return _damaged(FAILURE_REPLAY_INCONSISTENT, "%s belongs to sector '%s'" % [label, row.get("sector_id")])
		var applied: int = _int_or(row.get("applied_revision"), -1)
		if applied != index + 1:
			return _damaged(FAILURE_REPLAY_INCONSISTENT, "%s applied_revision %d breaks contiguity (expected %d)" % [label, applied, index + 1])
		if _int_or(row.get("expected_revision"), -1) != applied - 1:
			return _damaged(FAILURE_REPLAY_INCONSISTENT, "%s expected_revision %s does not precede %d" % [label, row.get("expected_revision"), applied])
		if not CanonEntityGuidScript.contains_guid(blueprint, row.get("target_guid")):
			return _damaged(FAILURE_REPLAY_INCONSISTENT, "%s target is not addressable in the base" % label)
	return {"outcome": OUTCOME_OK, "mutations": mutations, "revision": mutations.size()}


static func _int_or(value: Variant, fallback: int) -> int:
	return int(value) if value is int else fallback


static func _damaged(failure_class: String, detail: String) -> Dictionary:
	return {"outcome": OUTCOME_DAMAGED, "failure_class": failure_class, "detail": detail.left(MAX_DETAIL_LENGTH)}
