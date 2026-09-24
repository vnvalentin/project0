extends GutTest
## Public-seam experiment for issue #1067.

const AdmissionScript: Script = preload("res://server/sector_archetype_admission.gd")


func _blueprint() -> Dictionary:
	return {
		"schema_version": 3,
		"sector_id": "sector-2-3",
		"origin": {"x": 0, "y": 0},
		"tiles": [{"x": 0, "y": 0, "kind": "grass"}],
	}


func _with_structures(structures: Array) -> Dictionary:
	var blueprint: Dictionary = _blueprint()
	blueprint["structures"] = structures
	return blueprint


func _structure(kind: String) -> Dictionary:
	return {"structure_id": kind, "kind": kind, "x": 0, "y": 0, "facing_degrees": 0}


func test_profiles_admit_and_reject_at_the_public_seam() -> void:
	var wilderness: Dictionary = AdmissionScript.admit(AdmissionScript.PROFILE_WILDERNESS, _blueprint())
	var missing_settlement_anchor: Dictionary = AdmissionScript.admit(AdmissionScript.PROFILE_SETTLEMENT, _blueprint())
	var missing_poi_anchor: Dictionary = AdmissionScript.admit(AdmissionScript.PROFILE_POI_ANCHOR, _blueprint())
	var forbidden_facility: Dictionary = AdmissionScript.admit(
		AdmissionScript.PROFILE_WILDERNESS,
		_with_structures([_structure("inn")])
	)
	var settlement: Dictionary = AdmissionScript.admit(
		AdmissionScript.PROFILE_SETTLEMENT,
		_with_structures([_structure("village_hall")])
	)
	var poi: Dictionary = AdmissionScript.admit(
		AdmissionScript.PROFILE_POI_ANCHOR,
		_with_structures([_structure("well")])
	)

	assert_eq(wilderness["outcome"], AdmissionScript.OUTCOME_ACCEPTED)
	assert_eq(missing_settlement_anchor["reason"], AdmissionScript.REASON_MISSING_SETTLEMENT_ANCHOR)
	assert_eq(missing_poi_anchor["reason"], AdmissionScript.REASON_MISSING_POI_ANCHOR)
	assert_eq(forbidden_facility["reason"], AdmissionScript.REASON_FORBIDDEN_FACILITY)
	assert_eq(settlement["outcome"], AdmissionScript.OUTCOME_ACCEPTED)
	assert_eq(poi["outcome"], AdmissionScript.OUTCOME_ACCEPTED)


func test_candidate_cannot_replace_the_selected_profile() -> void:
	var candidate: Dictionary = _blueprint()
	candidate["archetype"] = AdmissionScript.PROFILE_SETTLEMENT
	var result: Dictionary = AdmissionScript.admit(AdmissionScript.PROFILE_WILDERNESS, candidate)

	assert_eq(result["outcome"], AdmissionScript.OUTCOME_REJECTED)
	assert_eq(result["reason"], AdmissionScript.REASON_CANDIDATE_CLASSIFICATION)
	assert_eq(result["profile"], AdmissionScript.PROFILE_WILDERNESS)


func test_rejections_have_no_canon_or_replication_side_effects_and_replay_is_idempotent() -> void:
	var canon_writes: int = 0
	var replication_dispatches: int = 0
	var canonical_sector_ids: Dictionary = {}
	var candidates: Array[Dictionary] = [
		_blueprint(),
		_with_structures([_structure("inn")]),
	]

	for candidate: Dictionary in candidates:
		var decision: Dictionary = AdmissionScript.admit(AdmissionScript.PROFILE_WILDERNESS, candidate)
		if decision["outcome"] == AdmissionScript.OUTCOME_ACCEPTED and not canonical_sector_ids.has(candidate["sector_id"]):
			canonical_sector_ids[candidate["sector_id"]] = true
			canon_writes += 1
			replication_dispatches += 1

	assert_eq(canon_writes, 1)
	assert_eq(replication_dispatches, 1)

	var replay: Dictionary = AdmissionScript.admit(AdmissionScript.PROFILE_WILDERNESS, _blueprint())
	if replay["outcome"] == AdmissionScript.OUTCOME_ACCEPTED and not canonical_sector_ids.has(replay["blueprint"]["sector_id"]):
		canon_writes += 1
		replication_dispatches += 1

	assert_eq(replay["profile"], AdmissionScript.PROFILE_WILDERNESS)
	assert_eq(replay["reason"], "")
	assert_eq(canon_writes, 1)
	assert_eq(replication_dispatches, 1)