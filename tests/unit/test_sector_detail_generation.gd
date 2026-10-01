extends GutTest

const Detail: Script = preload("res://server/sector_detail_generation.gd")
const Placement: Script = preload("res://shared/sector_detail_placement.gd")
const Hub: Script = preload("res://server/starting_town_hub_fixture.gd")
const FALLBACK_VALIDATION_BUDGET_MS: float = 200.0


func _timeout_generation(sector_id: String) -> Dictionary:
	return {
		"request_outcome": "timeout", "source": "fallback", "fallback_selected": true,
		"selected_profile": "WILDERNESS", "candidate_validation_outcome": "valid", "validation_outcome": "",
		"blueprint": {"schema_version": 1, "sector_id": sector_id, "origin": {"x": 0, "y": 0},
			"tiles": [{"x": 0, "y": 0, "kind": "floor"}]},
	}


func test_forced_timeout_fallback_prepares_within_budget_against_real_hub() -> void:
	var town: Dictionary = Hub.blueprint()
	var ingress := Vector3(4.4, 1.0, -440.1)
	var context: Dictionary = {"sector_id": "sector-0--2", "placement": Placement.select("sector-0--2", ingress), "ingress": ingress}
	for attempt: int in 3:
		var started: int = Time.get_ticks_usec()
		var prepared: Dictionary = Detail.prepare(_timeout_generation("sector-0--2"), context, town)
		var elapsed_ms: float = float(Time.get_ticks_usec() - started) / 1000.0
		assert_eq(prepared.get("source"), "fallback")
		assert_eq(prepared.get("placement_fallback_outcome"), "valid", "fallback reaches the unchanged ingress gate")
		assert_true(prepared.get("blueprint") is Dictionary)
		assert_lt(elapsed_ms, FALLBACK_VALIDATION_BUDGET_MS, "#551 fallback/validation budget (attempt %d: %.1f ms)" % [attempt, elapsed_ms])


func test_tile_on_reserved_town_cell_is_still_rejected() -> void:
	var town: Dictionary = Hub.blueprint()
	var anchor: Dictionary = {}
	for tile: Dictionary in town["tiles"]:
		if int(tile["x"]) >= 0 and int(tile["y"]) >= 0:
			anchor = tile
			break
	assert_false(anchor.is_empty(), "the hub has a non-negative tile")
	var candidate: Dictionary = {
		"schema_version": Placement.SCHEMA_VERSION, "sector_id": "sector-0-0",
		"detail_origin": {"x": int(anchor["x"]), "y": int(anchor["y"])}, "origin": {"x": 0, "y": 0},
		"tiles": [{"x": 0, "y": 0, "kind": "floor"}],
	}
	assert_eq(Detail.validate_ingress(candidate, Vector3(int(anchor["x"]), 1, int(anchor["y"])), town), "reserved_town_overlap")
