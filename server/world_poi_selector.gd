extends RefCounted
class_name WorldPoiSelector
## Slice 193: evaluates registered semantic POI predicates against bounded,
## server-owned candidate metadata. It never accepts model coordinates or
## mutates geometry, Canon, persistence, or runtime state.

const OUTCOME_OK: String = "ok"
const OUTCOME_NO_FEASIBLE_CANDIDATE: String = "no_feasible_candidate"
const OUTCOME_INVALID: String = "invalid"
const PREDICATE_HIGHEST_PEAK: String = "HIGHEST_PEAK"
const PREDICATE_VALLEY: String = "VALLEY"
const PREDICATE_FLAT_AREA: String = "FLAT_AREA"
const MAX_CANDIDATES: int = 128
const MAX_SLOPE_FOR_FLAT_AREA: float = 0.25
const MIN_FLATNESS_FOR_FLAT_AREA: float = 0.75

static func select(predicate: String, candidates: Array) -> Dictionary:
	if not [PREDICATE_HIGHEST_PEAK, PREDICATE_VALLEY, PREDICATE_FLAT_AREA].has(predicate):
		return {"outcome": OUTCOME_INVALID, "reason": "unsupported_predicate"}
	if candidates.size() > MAX_CANDIDATES:
		return {"outcome": OUTCOME_INVALID, "reason": "too_many_candidates"}
	var valid: Array[Dictionary] = []
	for candidate: Variant in candidates:
		var checked: Dictionary = _validate_candidate(candidate)
		if checked["outcome"] != OUTCOME_OK:
			return checked
		valid.append(checked["candidate"])
	var feasible: Array[Dictionary] = valid.filter(func(item: Dictionary) -> bool: return _is_feasible(predicate, item))
	if feasible.is_empty():
		return {"outcome": OUTCOME_NO_FEASIBLE_CANDIDATE, "predicate": predicate}
	feasible.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return _comes_before(predicate, left, right)
	)
	return {"outcome": OUTCOME_OK, "predicate": predicate, "candidate": feasible[0].duplicate(true)}

static func _validate_candidate(value: Variant) -> Dictionary:
	if not (value is Dictionary):
		return {"outcome": OUTCOME_INVALID, "reason": "candidate_not_object"}
	var candidate: Dictionary = value
	if not candidate.get("candidate_id") is String or String(candidate["candidate_id"]).strip_edges().is_empty():
		return {"outcome": OUTCOME_INVALID, "reason": "invalid_candidate_id"}
	for field: String in ["elevation", "slope", "flatness"]:
		if not (candidate.get(field) is float or candidate.get(field) is int) or not is_finite(float(candidate[field])):
			return {"outcome": OUTCOME_INVALID, "reason": "invalid_%s" % field}
	if float(candidate["slope"]) < 0.0 or float(candidate["flatness"]) < 0.0 or float(candidate["flatness"]) > 1.0:
		return {"outcome": OUTCOME_INVALID, "reason": "candidate_metric_out_of_range"}
	return {"outcome": OUTCOME_OK, "candidate": candidate.duplicate(true)}

static func _is_feasible(predicate: String, candidate: Dictionary) -> bool:
	if predicate == PREDICATE_FLAT_AREA:
		return float(candidate["slope"]) <= MAX_SLOPE_FOR_FLAT_AREA and float(candidate["flatness"]) >= MIN_FLATNESS_FOR_FLAT_AREA
	return true

static func _comes_before_highest_peak(left: Dictionary, right: Dictionary) -> bool:
	return _descending_metric_then_id(left, right, "elevation")

static func _comes_before(predicate: String, left: Dictionary, right: Dictionary) -> bool:
	if predicate == PREDICATE_HIGHEST_PEAK:
		return _comes_before_highest_peak(left, right)
	if predicate == PREDICATE_VALLEY:
		return _comes_before_valley(left, right)
	return _comes_before_flat_area(left, right)

static func _comes_before_valley(left: Dictionary, right: Dictionary) -> bool:
	if left["elevation"] != right["elevation"]:
		return left["elevation"] < right["elevation"]
	return String(left["candidate_id"]) < String(right["candidate_id"])

static func _comes_before_flat_area(left: Dictionary, right: Dictionary) -> bool:
	if left["flatness"] != right["flatness"]:
		return left["flatness"] > right["flatness"]
	if left["slope"] != right["slope"]:
		return left["slope"] < right["slope"]
	return String(left["candidate_id"]) < String(right["candidate_id"])

static func _descending_metric_then_id(left: Dictionary, right: Dictionary, metric: String) -> bool:
	if left[metric] != right[metric]:
		return left[metric] > right[metric]
	return String(left["candidate_id"]) < String(right["candidate_id"])