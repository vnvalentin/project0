extends GutTest
## Public-seam tests for Slice 047's provisional-to-Canon finalization.

const CoordinatorScript: Script = preload("res://server/canon_generation_coordinator.gd")


func _generation_result(blueprint: Dictionary) -> Dictionary:
	return {"request_outcome": "validated", "validation_outcome": "valid", "blueprint": blueprint}


func _blueprint() -> Dictionary:
	return {
		"schema_version": 1,
		"sector_id": "sector-2-3",
		"origin": {"x": 880, "y": 1320},
		"tiles": [{"x": 0, "y": 0, "kind": "floor"}],
	}


func test_success_emits_only_the_canonical_blueprint() -> void:
	var coordinator: CanonGenerationCoordinator = CoordinatorScript.new()
	var stored: Dictionary = _blueprint()
	stored["tiles"] = [{"x": 4, "y": 5, "kind": "floor"}]
	var emitted: Array = []
	coordinator.canonical_sector_ready.connect(func(sector_id: String, blueprint: Dictionary) -> void:
		emitted.append(blueprint)
	)
	coordinator.set_canonicalize_callback(func(blueprint: Dictionary) -> Dictionary:
		return {"outcome": "ok", "detail": "stored", "sector": {"blueprint": stored}}
	)
	var result: Dictionary = coordinator.accept_generation_result("sector-2-3", _generation_result(_blueprint()))
	assert_eq(result["outcome"], CoordinatorScript.OUTCOME_CANONICALIZED)
	assert_eq(emitted.size(), 1)
	assert_eq(emitted[0]["tiles"][0]["x"], 4)


func test_idempotent_replay_emits_existing_canon() -> void:
	var coordinator: CanonGenerationCoordinator = CoordinatorScript.new()
	var emitted: Array = []
	coordinator.canonical_sector_ready.connect(func(sector_id: String, blueprint: Dictionary) -> void:
		emitted.append(sector_id)
	)
	coordinator.set_canonicalize_callback(func(blueprint: Dictionary) -> Dictionary:
		return {"outcome": "idempotent", "sector": {"blueprint": blueprint}}
	)
	assert_eq(coordinator.accept_generation_result("sector-2-3", _generation_result(_blueprint()))["outcome"], CoordinatorScript.OUTCOME_IDEMPOTENT)
	assert_eq(emitted.size(), 1)


func test_transport_and_schema_failures_emit_nothing() -> void:
	var coordinator: CanonGenerationCoordinator = CoordinatorScript.new()
	var emitted: Array = []
	coordinator.canonical_sector_ready.connect(func(sector_id: String, blueprint: Dictionary) -> void:
		emitted.append(sector_id)
	)
	var transport: Dictionary = coordinator.accept_generation_result("sector-2-3", {"request_outcome": "transport_error"})
	var schema: Dictionary = coordinator.accept_generation_result("sector-2-3", {"request_outcome": "validated", "validation_outcome": "wrong_schema_version", "blueprint": null})
	assert_eq(transport["outcome"], CoordinatorScript.OUTCOME_IGNORED)
	assert_eq(schema["outcome"], CoordinatorScript.OUTCOME_IGNORED)
	assert_eq(emitted.size(), 0)


func test_conflict_emits_nothing() -> void:
	var coordinator: CanonGenerationCoordinator = CoordinatorScript.new()
	var emitted: Array = []
	coordinator.canonical_sector_ready.connect(func(sector_id: String, blueprint: Dictionary) -> void:
		emitted.append(sector_id)
	)
	coordinator.set_canonicalize_callback(func(blueprint: Dictionary) -> Dictionary:
		return {"outcome": "conflict", "detail": "immutable"}
	)
	var result: Dictionary = coordinator.accept_generation_result("sector-2-3", _generation_result(_blueprint()))
	assert_eq(result["outcome"], CoordinatorScript.OUTCOME_CONFLICT)
	assert_eq(emitted.size(), 0)