extends RefCounted
class_name CanonGenerationCoordinator
## Slice 047: finalizes asynchronous generation before any client sees it.

signal canonical_sector_ready(sector_id: String, blueprint: Dictionary)

const OUTCOME_CANONICALIZED: String = "canonicalized"
const OUTCOME_IDEMPOTENT: String = "idempotent"
const OUTCOME_IGNORED: String = "ignored"
const OUTCOME_CONFLICT: String = "conflict"

var _canonicalize: Callable = Callable()


func set_canonicalize_callback(callback: Callable) -> void:
	_canonicalize = callback


## Accepts only the structured result emitted by ProvisionalSectorGenerator.
## Emits the blueprint returned by Canon, never the raw provisional payload.
func accept_generation_result(sector_id: String, result: Variant) -> Dictionary:
	if not (result is Dictionary):
		return _result(OUTCOME_IGNORED, "Generation result is not a Dictionary.")
	var generation: Dictionary = result
	if generation.get("request_outcome", "") != "validated":
		return _result(OUTCOME_IGNORED, "Generation did not reach validation.")
	if generation.get("validation_outcome", "") != "valid":
		return _result(OUTCOME_IGNORED, "Generation blueprint failed schema validation.")
	if not (generation.get("blueprint") is Dictionary):
		return _result(OUTCOME_IGNORED, "Validated generation result has no blueprint.")
	if String(generation["blueprint"].get("sector_id", "")) != sector_id:
		return _result(OUTCOME_IGNORED, "Generation sector_id does not match the requested sector.")
	if not _canonicalize.is_valid():
		return _result(OUTCOME_IGNORED, "Canon callback is not configured.")

	var canon_result: Variant = _canonicalize.call(generation["blueprint"])
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
	return {"outcome": outcome, "detail": canon.get("detail", ""), "blueprint": stored_blueprint}


func _result(outcome: String, detail: String) -> Dictionary:
	return {"outcome": outcome, "detail": detail}