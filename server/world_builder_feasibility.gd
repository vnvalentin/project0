extends RefCounted
class_name WorldBuilderFeasibility
## Slice 194: checks selected semantic POIs against bounded server-owned
## feasibility metadata. It does not generate geometry or mutate Canon.

const OUTCOME_OK: String = "ok"
const OUTCOME_REJECTED: String = "rejected"
const OUTCOME_FALLBACK: String = "fallback"
const MAX_POIS: int = 8
const MAX_CLEARANCE_RADIUS: float = 32.0

static func evaluate(directive: Dictionary, selected_pois: Array, fallback: Dictionary) -> Dictionary:
	if not _valid_directive(directive):
		return _fallback("invalid_directive", fallback)
	if selected_pois.size() > MAX_POIS:
		return _fallback("too_many_pois", fallback)
	for poi: Variant in selected_pois:
		var checked: Dictionary = _check_poi(poi)
		if checked["outcome"] != OUTCOME_OK:
			return _fallback(String(checked["reason"]), fallback)
	return {
		"outcome": OUTCOME_OK,
		"directive_id": directive["directive_id"],
		"placements": selected_pois.duplicate(true),
	}

static func _valid_directive(value: Dictionary) -> bool:
	return value.get("directive_id") is String and not String(value["directive_id"]).strip_edges().is_empty() and value.get("schema_version") is int

static func _check_poi(value: Variant) -> Dictionary:
	if not (value is Dictionary):
		return {"outcome": OUTCOME_REJECTED, "reason": "poi_not_object"}
	var poi: Dictionary = value
	for field: String in ["poi_id", "candidate_id"]:
		if not poi.get(field) is String or String(poi[field]).strip_edges().is_empty():
			return {"outcome": OUTCOME_REJECTED, "reason": "invalid_%s" % field}
	for field: String in ["slope", "clearance_radius"]:
		if not (poi.get(field) is float or poi.get(field) is int) or not is_finite(float(poi[field])):
			return {"outcome": OUTCOME_REJECTED, "reason": "invalid_%s" % field}
	if float(poi["slope"]) < 0.0 or float(poi["slope"]) > 1.0:
		return {"outcome": OUTCOME_REJECTED, "reason": "slope_out_of_range"}
	if float(poi["clearance_radius"]) < 0.0 or float(poi["clearance_radius"]) > MAX_CLEARANCE_RADIUS:
		return {"outcome": OUTCOME_REJECTED, "reason": "clearance_radius_out_of_range"}
	if float(poi["slope"]) > float(poi.get("max_slope", 0.25)):
		return {"outcome": OUTCOME_REJECTED, "reason": "slope_infeasible"}
	if float(poi["clearance_radius"]) < float(poi.get("required_clearance_radius", 1.0)):
		return {"outcome": OUTCOME_REJECTED, "reason": "clearance_infeasible"}
	return {"outcome": OUTCOME_OK}

static func _fallback(reason: String, fallback: Dictionary) -> Dictionary:
	return {"outcome": OUTCOME_FALLBACK, "reason": reason, "directive": fallback.duplicate(true)}