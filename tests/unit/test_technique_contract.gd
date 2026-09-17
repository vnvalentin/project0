extends GutTest
## Slice 119 (Phase 14): public-seam tests for the technique contract.
## Multidimensional readiness (a technique needs a COMBINATION of stats),
## proficiency-driven reliability/mastery, teaching gated on mastery, and
## fail-closed parsing.

const TechniqueContractScript: Script = preload("res://shared/technique_contract.gd")


func _jump_slash_wire() -> Dictionary:
	# Jump Slash: STR to leave the ground, DEX to swing airborne, WIS to read the
	# blade, INT to concentrate on the whole sequence.
	return {
		"schema_version": 1,
		"technique_id": "jump_slash",
		"primary_node": "STR",
		"requirements": {"STR": 12.0, "DEX": 10.0, "WIS": 8.0, "INT": 8.0},
	}


func _effective(str_v: float, dex_v: float, con_v: float, int_v: float, wis_v: float, cha_v: float) -> Dictionary:
	return {"STR": str_v, "DEX": dex_v, "CON": con_v, "INT": int_v, "WIS": wis_v, "CHA": cha_v}


func test_is_ready_requires_the_whole_stat_combination() -> void:
	var t: Object = TechniqueContractScript.from_wire_dict(_jump_slash_wire())["technique"]
	# All requirements met.
	assert_true(t.is_ready(_effective(12, 10, 5, 8, 8, 5)))
	# One node short (INT) => not ready, even though the others exceed.
	assert_false(t.is_ready(_effective(20, 20, 20, 5, 20, 20)))


func test_readiness_shortfalls_report_each_missing_node() -> void:
	var t: Object = TechniqueContractScript.from_wire_dict(_jump_slash_wire())["technique"]
	var short: Dictionary = t.readiness_shortfalls(_effective(10, 10, 5, 8, 8, 5))
	assert_true(short.has("STR"), "STR is short")
	assert_almost_eq(float(short["STR"]), 2.0, 0.0001)
	assert_false(short.has("DEX"), "DEX is met")
	# Fully ready => no shortfalls.
	assert_eq(t.readiness_shortfalls(_effective(12, 10, 5, 8, 8, 5)).size(), 0)


func test_reliability_tracks_proficiency_and_clamps() -> void:
	assert_almost_eq(TechniqueContractScript.reliability(0.0), 0.0, 0.0001)
	assert_almost_eq(TechniqueContractScript.reliability(0.5), 0.5, 0.0001)
	assert_almost_eq(TechniqueContractScript.reliability(1.0), 1.0, 0.0001)
	assert_almost_eq(TechniqueContractScript.reliability(2.0), 1.0, 0.0001)
	assert_almost_eq(TechniqueContractScript.reliability(-1.0), 0.0, 0.0001)


func test_mastery_and_teaching_require_full_proficiency() -> void:
	assert_false(TechniqueContractScript.is_mastered(0.99))
	assert_true(TechniqueContractScript.is_mastered(1.0))
	assert_false(TechniqueContractScript.can_teach(0.99), "cannot teach below mastery")
	assert_true(TechniqueContractScript.can_teach(1.0), "mastered can teach")


func test_from_wire_dict_rejects_unsupported_version() -> void:
	var wire: Dictionary = _jump_slash_wire()
	wire["schema_version"] = 999
	var result: Dictionary = TechniqueContractScript.from_wire_dict(wire)
	assert_eq(result["outcome"], "unsupported_version")
	assert_null(result["technique"])


func test_from_wire_dict_rejects_unknown_required_node() -> void:
	var wire: Dictionary = _jump_slash_wire()
	wire["requirements"] = {"STR": 12.0, "LUCK": 5.0}
	var result: Dictionary = TechniqueContractScript.from_wire_dict(wire)
	assert_eq(result["outcome"], "unsupported_node")


func test_from_wire_dict_rejects_empty_requirements() -> void:
	var wire: Dictionary = _jump_slash_wire()
	wire["requirements"] = {}
	var result: Dictionary = TechniqueContractScript.from_wire_dict(wire)
	assert_eq(result["outcome"], "empty_requirements")


func test_from_wire_dict_rejects_negative_threshold() -> void:
	var wire: Dictionary = _jump_slash_wire()
	wire["requirements"] = {"STR": -3.0}
	var result: Dictionary = TechniqueContractScript.from_wire_dict(wire)
	assert_eq(result["outcome"], "out_of_bounds")


func test_from_wire_dict_rejects_primary_not_in_requirements() -> void:
	var wire: Dictionary = _jump_slash_wire()
	wire["primary_node"] = "CHA"  # not among the requirements
	var result: Dictionary = TechniqueContractScript.from_wire_dict(wire)
	assert_eq(result["outcome"], "primary_not_required")


func test_from_wire_dict_rejects_unknown_primary_node() -> void:
	var wire: Dictionary = _jump_slash_wire()
	wire["primary_node"] = "LUCK"
	var result: Dictionary = TechniqueContractScript.from_wire_dict(wire)
	assert_eq(result["outcome"], "unsupported_node")


func test_from_wire_dict_rejects_non_dictionary() -> void:
	var result: Dictionary = TechniqueContractScript.from_wire_dict(7)
	assert_eq(result["outcome"], "malformed")
