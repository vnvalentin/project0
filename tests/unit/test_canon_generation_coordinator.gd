extends GutTest
## Public-seam tests for Slice 047's provisional-to-Canon finalization.

const CoordinatorScript: Script = preload("res://server/canon_generation_coordinator.gd")


func _generation_result(blueprint: Dictionary) -> Dictionary:
	return {"request_outcome": "validated", "validation_outcome": "valid", "blueprint": blueprint}


func _blueprint() -> Dictionary:
	return {
		"schema_version": 1,
		"sector_id": "sector-2-3",
		"origin": {"x": 0, "y": 0},
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
		var persisted: Dictionary = stored.duplicate(true)
		persisted["archetype"] = blueprint.get("archetype", "")
		return {"outcome": "ok", "detail": "stored", "sector": {"blueprint": persisted}}
	)
	var result: Dictionary = coordinator.accept_generation_result("sector-2-3", SectorArchetypeAdmission.PROFILE_WILDERNESS, _generation_result(_blueprint()))
	assert_eq(result["outcome"], CoordinatorScript.OUTCOME_CANONICALIZED)
	assert_eq(result["profile"], SectorArchetypeAdmission.PROFILE_WILDERNESS)
	assert_eq(result["blueprint"]["archetype"], SectorArchetypeAdmission.PROFILE_WILDERNESS)
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
	assert_eq(coordinator.accept_generation_result("sector-2-3", SectorArchetypeAdmission.PROFILE_WILDERNESS, _generation_result(_blueprint()))["outcome"], CoordinatorScript.OUTCOME_IDEMPOTENT)
	assert_eq(emitted.size(), 1)


func test_transport_and_schema_failures_emit_nothing() -> void:
	var coordinator: CanonGenerationCoordinator = CoordinatorScript.new()
	var emitted: Array = []
	coordinator.canonical_sector_ready.connect(func(sector_id: String, blueprint: Dictionary) -> void:
		emitted.append(sector_id)
	)
	var transport: Dictionary = coordinator.accept_generation_result("sector-2-3", SectorArchetypeAdmission.PROFILE_WILDERNESS, {"request_outcome": "transport_error"})
	var schema: Dictionary = coordinator.accept_generation_result("sector-2-3", SectorArchetypeAdmission.PROFILE_WILDERNESS, {"request_outcome": "validated", "validation_outcome": "wrong_schema_version", "blueprint": null})
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
	var result: Dictionary = coordinator.accept_generation_result("sector-2-3", SectorArchetypeAdmission.PROFILE_WILDERNESS, _generation_result(_blueprint()))
	assert_eq(result["outcome"], CoordinatorScript.OUTCOME_CONFLICT)
	assert_eq(emitted.size(), 0)


func test_rejected_candidate_never_reaches_canon() -> void:
	var coordinator: CanonGenerationCoordinator = CoordinatorScript.new()
	var canon_calls: int = 0
	coordinator.set_canonicalize_callback(func(blueprint: Dictionary) -> Dictionary:
		canon_calls += 1
		return {"outcome": "ok", "sector": {"blueprint": blueprint}}
	)
	var candidate: Dictionary = _blueprint()
	candidate["archetype"] = SectorArchetypeAdmission.PROFILE_SETTLEMENT
	var result: Dictionary = coordinator.accept_generation_result(
		"sector-2-3",
		SectorArchetypeAdmission.PROFILE_WILDERNESS,
		_generation_result(candidate)
	)
	assert_eq(result["outcome"], CoordinatorScript.OUTCOME_IGNORED)
	assert_eq(result["admission_reason"], SectorArchetypeAdmission.REASON_CANDIDATE_CLASSIFICATION)
	assert_eq(result["canon_write_count"], 0)
	assert_eq(result["replication_dispatch_count"], 0)
	assert_eq(canon_calls, 0)


func test_validated_fallback_admission_preserves_generation_failure_provenance() -> void:
	for failure: Dictionary in [
		{"request_outcome": "timeout", "validation_outcome": ""},
		{"request_outcome": "transport_error", "validation_outcome": ""},
		{"request_outcome": "validated", "validation_outcome": "wrong_schema_version"},
	]:
		var coordinator: CanonGenerationCoordinator = CoordinatorScript.new()
		var writes: Array[Dictionary] = []
		var dispatched: Array[Dictionary] = []
		coordinator.set_canonicalize_callback(func(blueprint: Dictionary) -> Dictionary:
			writes.append(blueprint)
			return {"outcome": "ok", "sector": {"blueprint": blueprint}}
		)
		coordinator.canonical_sector_ready.connect(func(_sector_id: String, blueprint: Dictionary) -> void:
			dispatched.append(blueprint)
		)
		var candidate: Dictionary = failure.duplicate(true)
		candidate.merge({"source": "fallback", "fallback_selected": true, "candidate_validation_outcome": "valid", "blueprint": _blueprint(), "detail": "original model failure"})
		var original: Dictionary = candidate.duplicate(true)
		var result: Dictionary = coordinator.accept_generation_result("sector-2-3", "WILDERNESS", candidate)
		assert_eq(result["outcome"], CoordinatorScript.OUTCOME_CANONICALIZED)
		assert_eq(writes.size(), 1)
		assert_eq(dispatched.size(), 1)
		assert_eq(candidate, original, "admission must not rewrite failed generation as success")


func test_fallback_validation_markers_cannot_bypass_schema_sector_or_archetype() -> void:
	var fallback: Dictionary = {
		"request_outcome": "timeout", "validation_outcome": "", "source": "fallback",
		"fallback_selected": true, "candidate_validation_outcome": "valid", "blueprint": _blueprint(),
	}
	var cases: Array[Dictionary] = []
	for malformed: Variant in [null, {}, {"sector_id": "sector-2-3"}]:
		var candidate: Dictionary = fallback.duplicate(true)
		candidate["blueprint"] = malformed
		cases.append({"profile": "WILDERNESS", "candidate": candidate})
	var bad_tile: Dictionary = fallback.duplicate(true)
	bad_tile["blueprint"]["tiles"][0]["kind"] = "unsupported"
	cases.append({"profile": "WILDERNESS", "candidate": bad_tile})
	var wrong_sector: Dictionary = fallback.duplicate(true)
	wrong_sector["blueprint"]["sector_id"] = "sector-9-9"
	cases.append({"profile": "WILDERNESS", "candidate": wrong_sector})
	var model_classification: Dictionary = fallback.duplicate(true)
	model_classification["blueprint"]["archetype"] = "WILDERNESS"
	cases.append({"profile": "WILDERNESS", "candidate": model_classification})
	for profile: String in ["SETTLEMENT", "POI_ANCHOR", "unknown"]:
		cases.append({"profile": profile, "candidate": fallback.duplicate(true)})
	for patch: Dictionary in [
		{"source": "llm"}, {"fallback_selected": false}, {"fallback_selected": "true"},
		{"candidate_validation_outcome": ""}, {"candidate_validation_outcome": "invalid"},
	]:
		var candidate: Dictionary = fallback.duplicate(true)
		candidate.merge(patch, true)
		cases.append({"profile": "WILDERNESS", "candidate": candidate})
	for rejected: Dictionary in cases:
		var coordinator: CanonGenerationCoordinator = CoordinatorScript.new()
		var writes: Array[Dictionary] = []
		var dispatches: Array[String] = []
		coordinator.set_canonicalize_callback(func(blueprint: Dictionary) -> Dictionary:
			writes.append(blueprint)
			return {"outcome": "ok", "sector": {"blueprint": blueprint}}
		)
		coordinator.canonical_sector_ready.connect(func(sector_id: String, _blueprint: Dictionary) -> void:
			dispatches.append(sector_id)
		)
		var result: Dictionary = coordinator.accept_generation_result("sector-2-3", rejected["profile"], rejected["candidate"])
		assert_eq(result["outcome"], CoordinatorScript.OUTCOME_IGNORED)
		assert_eq(writes.size(), 0, "claimed validation cannot authorize an invalid fallback")
		assert_eq(dispatches.size(), 0)


func test_nonfallback_failures_cannot_claim_candidate_validation_to_enter_canon() -> void:
	var coordinator: CanonGenerationCoordinator = CoordinatorScript.new()
	var writes: Array[Dictionary] = []
	var dispatches: Array[String] = []
	coordinator.set_canonicalize_callback(func(blueprint: Dictionary) -> Dictionary:
		writes.append(blueprint)
		return {"outcome": "ok", "sector": {"blueprint": blueprint}}
	)
	coordinator.canonical_sector_ready.connect(func(sector_id: String, _blueprint: Dictionary) -> void:
		dispatches.append(sector_id)
	)
	for failure: Dictionary in [
		{"request_outcome": "timeout", "validation_outcome": "valid"},
		{"request_outcome": "transport_error", "validation_outcome": "valid"},
		{"request_outcome": "validated", "validation_outcome": "wrong_schema_version"},
	]:
		var candidate: Dictionary = failure.duplicate(true)
		candidate.merge({"source": "llm", "fallback_selected": false, "candidate_validation_outcome": "valid", "blueprint": _blueprint()})
		assert_eq(coordinator.accept_generation_result("sector-2-3", "WILDERNESS", candidate)["outcome"], CoordinatorScript.OUTCOME_IGNORED)
	assert_eq(writes.size(), 0)
	assert_eq(dispatches.size(), 0)