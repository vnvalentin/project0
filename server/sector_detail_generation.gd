extends RefCounted

const Placement: Script = preload("res://shared/sector_detail_placement.gd")
const Schema: Script = preload("res://shared/sector_blueprint_schema.gd")
const Collision: Script = preload("res://shared/sector_collision_map.gd")
const Coordinator: Script = preload("res://server/canon_generation_coordinator.gd")
const FALLBACK_RADIUS: int = 4


static func prepare(generation: Dictionary, context: Dictionary, town: Dictionary) -> Dictionary:
	var result: Dictionary = generation.duplicate(true)
	var eligibility: Dictionary = Coordinator.validate_generation_input(String(context["sector_id"]), String(generation.get("selected_profile", "")), generation)
	if eligibility["outcome"] != Coordinator.OUTCOME_ADMISSIBLE:
		return result
	if not result.get("blueprint") is Dictionary:
		return result
	var candidate: Dictionary = result["blueprint"].duplicate(true)
	var pinned: Dictionary = context["placement"]
	var ingress: Vector3 = context["ingress"]
	var sector_id: String = String(context["sector_id"])
	var reason: String = ""
	if String(candidate.get("sector_id", "")) != sector_id:
		reason = "sector_identity_conflict"
	if candidate.has("detail_origin"):
		if not Placement.validate_metadata(candidate).is_empty():
			reason = "invalid_placement_metadata"
		else:
			for axis: String in ["x", "y"]:
				if float(candidate["detail_origin"][axis]) != float(pinned["detail_origin"][axis]) or float(candidate["origin"][axis]) != float(pinned["origin"][axis]):
					reason = "placement_conflict"
	candidate["schema_version"] = Placement.SCHEMA_VERSION
	candidate["detail_origin"] = pinned["detail_origin"].duplicate(true)
	candidate["origin"] = pinned["origin"].duplicate(true)
	if reason.is_empty():
		reason = validate_ingress(candidate, ingress, town)
	result["placement_validation_outcome"] = "valid" if reason.is_empty() else reason
	result["generation_source"] = generation.get("source", "")
	result["generation_detail"] = generation.get("detail", "")
	if not reason.is_empty() or result.get("source") == "fallback":
		candidate = _fallback(sector_id, pinned, town)
		var fallback_error: String = validate_ingress(candidate, ingress, town)
		result["placement_fallback_outcome"] = "valid" if fallback_error.is_empty() else fallback_error
		if not fallback_error.is_empty():
			result["blueprint"] = null
			return result
		result["source"] = "fallback"
		result["fallback_selected"] = true
		result["generation_candidate_validation_outcome"] = generation.get("candidate_validation_outcome", generation.get("validation_outcome", ""))
		result["candidate_validation_outcome"] = "valid"
	result["blueprint"] = candidate
	return result


static func validate_ingress(blueprint: Dictionary, ingress: Vector3, town: Dictionary) -> String:
	if Schema.validate(blueprint)["outcome"] != "valid":
		return "invalid_placed_blueprint"
	var reserved: Dictionary = _town_cells(town)
	var collision: RefCounted = Collision.new(blueprint)
	# The offset depends only on placement metadata; per-cell recomputation cost ~300 ms (#1366).
	var offset: Vector3 = Placement.world_offset(blueprint)
	for tile: Dictionary in blueprint["tiles"]:
		if not Placement._integer(tile["x"]) or not Placement._integer(tile["y"]):
			return "fractional_detail_tile"
		var world: Vector3 = offset + Vector3(float(tile["x"]), 0, float(tile["y"]))
		if reserved.has(Vector2i(roundi(world.x), roundi(world.z))):
			return "reserved_town_overlap"
		if not Placement.clip_rectangle(blueprint, Rect2(Vector2(float(tile["x"]), float(tile["y"])) - Vector2(0.5, 0.5), Vector2.ONE)).has_area():
			return "unrepresented_tile"
	for cell: Vector2i in reserved:
		var local: Vector3 = Vector3(cell.x, 0, cell.y) - offset
		if collision.is_blocked(Vector2i(roundi(local.x), roundi(local.z))):
			return "solid_town_overlap"
	var detail: RefCounted = Placement.new(blueprint)
	var town_detail: RefCounted = Placement.new(town)
	if not detail.contains_world(ingress) or not town_detail.has_clearance(ingress):
		return "uncovered_ingress"
	var target: Vector3 = detail.navigation_target(ingress)
	if not target.is_finite() or target.distance_to(ingress) < 2.0:
		return "insufficient_connected_route"
	return ""


static func _fallback(sector_id: String, pinned: Dictionary, town: Dictionary) -> Dictionary:
	var blueprint: Dictionary = {
		"schema_version": Placement.SCHEMA_VERSION, "sector_id": sector_id,
		"detail_origin": pinned["detail_origin"].duplicate(true), "origin": pinned["origin"].duplicate(true),
		"tiles": [],
	}
	var reserved: Dictionary = _town_cells(town)
	var origin: Dictionary = pinned["origin"]
	var offset: Vector3 = Placement.world_offset(blueprint)
	for horizontal: int in range(int(origin["x"]) - FALLBACK_RADIUS, int(origin["x"]) + FALLBACK_RADIUS + 1):
		for vertical: int in range(int(origin["y"]) - FALLBACK_RADIUS, int(origin["y"]) + FALLBACK_RADIUS + 1):
			var world: Vector3 = offset + Vector3(horizontal, 0, vertical)
			if reserved.has(Vector2i(roundi(world.x), roundi(world.z))):
				continue
			if not Placement.clip_rectangle(blueprint, Rect2(Vector2(horizontal, vertical) - Vector2(0.5, 0.5), Vector2.ONE)).has_area():
				continue
			blueprint["tiles"].append({"x": horizontal, "y": vertical, "kind": "floor"})
	return blueprint


static func _town_cells(town: Dictionary) -> Dictionary:
	var cells: Dictionary = {}
	for tile: Dictionary in town.get("tiles", []):
		cells[Vector2i(int(tile["x"]), int(tile["y"]))] = true
	return cells
