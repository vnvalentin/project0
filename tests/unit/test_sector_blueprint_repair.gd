extends GutTest

const Repair: Script = preload("res://server/sector_blueprint_repair.gd")
const Schema: Script = preload("res://shared/sector_blueprint_schema.gd")
const Archetype: Script = preload("res://server/sector_archetype_admission.gd")
const Detail: Script = preload("res://server/sector_detail_generation.gd")
const Placement: Script = preload("res://shared/sector_detail_placement.gd")
const Hub: Script = preload("res://server/starting_town_hub_fixture.gd")
const SECTOR_ID: String = "sector-0--2"
const INGRESS: Vector3 = Vector3(4.4, 1.0, -440.1)


func _block(offset: Vector2i) -> Array:
	var tiles: Array = []
	for x: int in range(-2, 3):
		for y: int in range(-2, 3):
			tiles.append({"x": x + offset.x, "y": y + offset.y, "kind": "floor"})
	return tiles


func _assert_admissible(repaired: Dictionary) -> void:
	assert_eq(Schema.validate_generated(repaired)["outcome"], Schema.OUTCOME_VALID, "repair passes the unchanged generated-schema gate")
	assert_eq(Archetype.admit(Archetype.PROFILE_WILDERNESS, repaired)["outcome"], Archetype.OUTCOME_ACCEPTED, "repair passes WILDERNESS admission")


func test_each_repairable_class_yields_an_admissible_candidate() -> void:
	var cases: Dictionary = {
		"unsupported_kind": {"schema_version": 3, "sector_id": SECTOR_ID, "origin": {"x": 0, "y": 0},
			"tiles": _block(Vector2i.ZERO) + [{"x": 3, "y": 0, "kind": "lava_pit"}]},
		"out_of_bounds_and_fractional": {"schema_version": 3, "sector_id": SECTOR_ID, "origin": {"x": 0, "y": 0},
			"tiles": _block(Vector2i.ZERO) + [{"x": 99, "y": 0.4, "kind": "grass"}, {"x": 1.6, "y": -0.2, "kind": "path"}]},
		"wrong_identity_version_and_facilities": {"schema_version": 99, "sector_id": "sector-9-9", "archetype": "SETTLEMENT",
			"structures": [{"kind": "lava_tower"}], "tiles": _block(Vector2i.ZERO)},
		"duplicates_and_garbage": {"tiles": _block(Vector2i.ZERO) + _block(Vector2i.ZERO) + ["x", null, {"x": "1", "y": 0, "kind": "floor"}]},
		"missing_origin_tile": {"schema_version": 3, "sector_id": SECTOR_ID, "origin": {"x": 0, "y": 0}, "tiles": _block(Vector2i(10, -7))},
	}
	for name: String in cases:
		var repaired: Dictionary = Repair.repair(cases[name], SECTOR_ID)
		assert_false(repaired.is_empty(), "%s is repairable" % name)
		if repaired.is_empty():
			continue
		assert_eq(repaired["sector_id"], SECTOR_ID, name)
		assert_false(repaired.has("structures") or repaired.has("archetype"), "%s: repair never keeps facilities or classification" % name)
		var cells: Dictionary = {}
		for tile: Dictionary in repaired["tiles"]:
			cells[Vector2i(tile["x"], tile["y"])] = true
		assert_true(cells.has(Vector2i.ZERO), "%s: re-anchored onto the origin" % name)
		assert_eq(cells.size(), repaired["tiles"].size(), "%s: unique cells" % name)
		_assert_admissible(repaired)


func test_unrepairable_candidates_go_to_pass_2() -> void:
	for candidate: Variant in [null, "text", {}, {"tiles": "none"}, {"tiles": []}, {"tiles": [{"x": 0, "y": 0, "kind": "lava_pit"}, {"x": INF, "y": 0, "kind": "floor"}]}]:
		assert_eq(Repair.repair(candidate, SECTOR_ID), {}, "unrepairable: %s" % str(candidate))
	assert_eq(Repair.repair({"tiles": _block(Vector2i.ZERO)}, ""), {}, "a sector identity is required")


func _pass_1_result(repaired: Dictionary) -> Dictionary:
	return {"request_outcome": "validated", "validation_outcome": "unsupported_kind", "candidate_validation_outcome": "valid",
		"source": "fallback", "fallback_selected": true, "fallback_pass": "pass_1", "selected_profile": "WILDERNESS", "blueprint": repaired}


func test_pass_1_survives_placement_or_cascades_to_pass_2() -> void:
	var context: Dictionary = {"sector_id": SECTOR_ID, "placement": Placement.select(SECTOR_ID, INGRESS), "ingress": INGRESS}
	var town: Dictionary = Hub.blueprint()
	var connected: Dictionary = Repair.repair({"tiles": _block(Vector2i.ZERO)}, SECTOR_ID)
	var kept: Dictionary = Detail.prepare(_pass_1_result(connected), context, town)
	assert_eq(kept.get("placement_validation_outcome"), "valid", "a connected repair passes the unchanged ingress gate")
	assert_eq(kept.get("fallback_pass"), "pass_1")
	assert_eq(kept["blueprint"]["tiles"].size(), 25, "the repaired geometry is kept, not the template")
	var lone: Dictionary = Repair.repair({"tiles": [{"x": 0, "y": 0, "kind": "floor"}]}, SECTOR_ID)
	var replaced: Dictionary = Detail.prepare(_pass_1_result(lone), context, town)
	assert_eq(replaced.get("placement_validation_outcome"), "insufficient_connected_route")
	assert_eq(replaced.get("fallback_pass"), "pass_2", "an unplaceable repair falls through to the static template")
	assert_eq(replaced.get("placement_fallback_outcome"), "valid")


func test_worst_case_pass_1_and_pass_2_fit_the_200_ms_budget() -> void:
	var tiles: Array = []
	for x: int in range(-60, 60):
		for y: int in range(-60, 60):
			tiles.append({"x": x + 0.25, "y": y, "kind": "floor" if (x + y) % 7 else "lava_pit"})
	var context: Dictionary = {"sector_id": SECTOR_ID, "placement": Placement.select(SECTOR_ID, INGRESS), "ingress": INGRESS}
	var started: int = Time.get_ticks_usec()
	var repaired: Dictionary = Repair.repair({"tiles": tiles}, SECTOR_ID)
	var validated: Dictionary = Schema.validate_generated(repaired)
	var prepared: Dictionary = Detail.prepare(_pass_1_result(validated["blueprint"]), context, Hub.blueprint())
	var elapsed_ms: float = float(Time.get_ticks_usec() - started) / 1000.0
	assert_eq(validated["outcome"], Schema.OUTCOME_VALID)
	assert_true(prepared.get("blueprint") is Dictionary, "the cascade always yields a placed candidate")
	assert_lt(elapsed_ms, 200.0, "#551 fallback/validation budget for a %d-tile candidate (%.1f ms)" % [tiles.size(), elapsed_ms])
