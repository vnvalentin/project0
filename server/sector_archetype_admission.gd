extends RefCounted
class_name SectorArchetypeAdmission
## Server-owned profile rules applied after generic blueprint validation.

const SectorBlueprintSchemaScript: Script = preload("res://shared/sector_blueprint_schema.gd")

const PROFILE_WILDERNESS: String = "WILDERNESS"
const PROFILE_SETTLEMENT: String = "SETTLEMENT"
const PROFILE_POI_ANCHOR: String = "POI_ANCHOR"

const OUTCOME_ACCEPTED: String = "accepted"
const OUTCOME_REJECTED: String = "rejected"

const REASON_UNSUPPORTED_PROFILE: String = "unsupported_profile"
const REASON_INVALID_BLUEPRINT: String = "invalid_blueprint"
const REASON_CANDIDATE_CLASSIFICATION: String = "candidate_classification"
const REASON_FORBIDDEN_FACILITY: String = "forbidden_facility"
const REASON_MISSING_SETTLEMENT_ANCHOR: String = "missing_settlement_anchor"
const REASON_MISSING_POI_ANCHOR: String = "missing_poi_anchor"

const _CANDIDATE_CLASSIFICATION_FIELDS: PackedStringArray = [
	"archetype",
	"classification",
	"sector_archetype",
	"profile",
]


## The selected profile is trusted server state; it is never read from the candidate.
static func admit(selected_profile: String, candidate: Variant) -> Dictionary:
	if not _supported_profiles().has(selected_profile):
		return _rejection(selected_profile, REASON_UNSUPPORTED_PROFILE, "Selected profile is not supported.")
	if not (candidate is Dictionary):
		return _rejection(selected_profile, REASON_INVALID_BLUEPRINT, "Candidate blueprint is not a Dictionary.")

	var blueprint: Dictionary = candidate
	for field: String in _CANDIDATE_CLASSIFICATION_FIELDS:
		if blueprint.has(field):
			return _rejection(selected_profile, REASON_CANDIDATE_CLASSIFICATION, "Candidate cannot supply '%s'." % field)

	var schema_result: Dictionary = SectorBlueprintSchemaScript.validate(blueprint)
	if schema_result["outcome"] != SectorBlueprintSchemaScript.OUTCOME_VALID:
		return _rejection(selected_profile, REASON_INVALID_BLUEPRINT, schema_result["detail"])

	var structures: Array = blueprint.get("structures", [])
	match selected_profile:
		PROFILE_WILDERNESS:
			if not structures.is_empty():
				return _rejection(selected_profile, REASON_FORBIDDEN_FACILITY, "WILDERNESS cannot contain structures.")
		PROFILE_SETTLEMENT:
			if not _contains_structure_kind(structures, "village_hall"):
				return _rejection(selected_profile, REASON_MISSING_SETTLEMENT_ANCHOR, "SETTLEMENT requires a village_hall anchor.")
		PROFILE_POI_ANCHOR:
			if structures.is_empty():
				return _rejection(selected_profile, REASON_MISSING_POI_ANCHOR, "POI_ANCHOR requires an anchor structure.")

	return {
		"outcome": OUTCOME_ACCEPTED,
		"reason": "",
		"detail": "",
		"profile": selected_profile,
		"blueprint": blueprint,
	}


static func _supported_profiles() -> PackedStringArray:
	return PackedStringArray([PROFILE_WILDERNESS, PROFILE_SETTLEMENT, PROFILE_POI_ANCHOR])


static func _contains_structure_kind(structures: Array, expected_kind: String) -> bool:
	for structure: Variant in structures:
		if structure is Dictionary and structure.get("kind", "") == expected_kind:
			return true
	return false


static func _rejection(profile: String, reason: String, detail: String) -> Dictionary:
	return {
		"outcome": OUTCOME_REJECTED,
		"reason": reason,
		"detail": detail,
		"profile": profile,
		"blueprint": null,
	}