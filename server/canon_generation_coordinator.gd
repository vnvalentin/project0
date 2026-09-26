extends RefCounted
class_name CanonGenerationCoordinator
## Slice 047: finalizes asynchronous generation before any client sees it.

signal canonical_sector_ready(sector_id: String, blueprint: Dictionary)

const OUTCOME_CANONICALIZED: String = "canonicalized"
const OUTCOME_IDEMPOTENT: String = "idempotent"
const OUTCOME_IGNORED: String = "ignored"
const OUTCOME_CONFLICT: String = "conflict"

const SectorArchetypeAdmissionScript: Script = preload("res://server/sector_archetype_admission.gd")

var _canonicalize: Callable = Callable()


func set_canonicalize_callback(callback: Callable) -> void:
	_canonicalize = callback


## Accepts only the structured result emitted by ProvisionalSectorGenerator and
## the server-selected profile carried outside the model candidate.
## Emits the blueprint returned by Canon, never the raw provisional payload.
func accept_generation_result(sector_id: String, selected_profile_or_result: Variant, result: Variant = null) -> Dictionary:
	var selected_profile: String = SectorArchetypeAdmissionScript.PROFILE_WILDERNESS
	if result == null:
		result = selected_profile_or_result
	else:
		selected_profile = String(selected_profile_or_result)
	if not (result is Dictionary):
		return _result(OUTCOME_IGNORED, "Generation result is not a Dictionary.")
	var generation: Dictionary = result
	if generation.get("source", "") == "fallback" or generation.get("fallback_selected", false) != false:
		if generation.get("source", "") != "fallback" or not (generation.get("fallback_selected") is bool) or generation["fallback_selected"] != true:
			return _result(OUTCOME_IGNORED, "Fallback provenance is inconsistent.")
		if generation.get("candidate_validation_outcome", "") != "valid":
			return _result(OUTCOME_IGNORED, "Fallback candidate failed schema validation.")
	else:
		if generation.get("request_outcome", "") != "validated":
			return _result(OUTCOME_IGNORED, "Generation did not reach validation.")
		if generation.get("validation_outcome", "") != "valid":
			return _result(OUTCOME_IGNORED, "Generation blueprint failed schema validation.")
	if not (generation.get("blueprint") is Dictionary):
		return _result(OUTCOME_IGNORED, "Validated generation result has no blueprint.")
	if String(generation["blueprint"].get("sector_id", "")) != sector_id:
		return _result(OUTCOME_IGNORED, "Generation sector_id does not match the requested sector.")
	var admission: Dictionary = SectorArchetypeAdmissionScript.admit(selected_profile, generation["blueprint"])
	if admission["outcome"] != SectorArchetypeAdmissionScript.OUTCOME_ACCEPTED:
		return {
			"outcome": OUTCOME_IGNORED,
			"detail": admission["detail"],
			"admission_reason": admission["reason"],
			"profile": selected_profile,
			"canon_write_count": 0,
			"replication_dispatch_count": 0,
		}
	if not _canonicalize.is_valid():
		return _result(OUTCOME_IGNORED, "Canon callback is not configured.")

	var canon_result: Variant = _canonicalize.call(admission["blueprint"])
	if not (canon_result is Dictionary):
		return _result(OUTCOME_IGNORED, "Canon callback returned an invalid result.")
	var canon: Dictionary = canon_result
	var canon_outcome: String = canon.get("outcome", "")
	if canon_outcome == "conflict":
		return {"outcome": OUTCOME_CONFLICT, "detail": canon.get("detail", "")}
	if canon_outcome != "ok" and canon_outcome != "idempotent":
		return _result(OUTCOME_IGNORED, canon.get("detail", "Canon rejected the blueprint."))
	if not (canon.get("sector") is Dictionary) or not (canon["sector"].get("blueprint") is Dictionary):
		return _result(OUTCOME_IGNORED, "Canon result did not include a blueprint.")

	var stored_blueprint: Dictionary = canon["sector"]["blueprint"]
	var outcome: String = OUTCOME_CANONICALIZED if canon_outcome == "ok" else OUTCOME_IDEMPOTENT
	canonical_sector_ready.emit(sector_id, stored_blueprint)
	return {
		"outcome": outcome,
		"detail": canon.get("detail", ""),
		"blueprint": stored_blueprint,
		"profile": selected_profile,
		"canon_write_count": 1 if canon_outcome == "ok" else 0,
		"replication_dispatch_count": 1,
	}


func _result(outcome: String, detail: String) -> Dictionary:
	return {"outcome": outcome, "detail": detail}