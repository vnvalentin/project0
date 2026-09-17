extends GutTest
## Slice 121 (Phase 14): public-seam tests for the damage-resolution composition
## contract. Attribute scale is node/baseline; technique reliability and defender
## mitigation scale the strike; mitigation is capped so a hit always stings;
## damage floors at zero; and parsing fails closed. Includes an end-to-end
## composition test wiring ItemContract + TechniqueContract + CombatHealth.

const DamageResolutionScript: Script = preload("res://shared/damage_resolution.gd")
const ItemContractScript: Script = preload("res://shared/item_contract.gd")
const TechniqueContractScript: Script = preload("res://shared/technique_contract.gd")
const CombatHealthScript: Script = preload("res://shared/combat_health.gd")


func _wire(weapon: float, node: float, reliability: float, mitigation: float) -> Dictionary:
	return {
		"schema_version": 1,
		"weapon_effective": weapon,
		"attacker_node": node,
		"technique_reliability": reliability,
		"raw_mitigation": mitigation,
	}


func test_attribute_scale_is_relative_to_baseline() -> void:
	assert_almost_eq(DamageResolutionScript.attribute_scale(10.0), 1.0, 0.0001)
	assert_almost_eq(DamageResolutionScript.attribute_scale(20.0), 2.0, 0.0001)
	# Zero/negative node yields no offense.
	assert_almost_eq(DamageResolutionScript.attribute_scale(0.0), 0.0, 0.0001)
	assert_almost_eq(DamageResolutionScript.attribute_scale(-5.0), 0.0, 0.0001)


func test_mitigation_fraction_clamps_to_zero_and_cap() -> void:
	assert_almost_eq(DamageResolutionScript.mitigation_fraction(0.5), 0.5, 0.0001)
	assert_almost_eq(DamageResolutionScript.mitigation_fraction(-1.0), 0.0, 0.0001)
	# Never fully negates a hit.
	assert_almost_eq(DamageResolutionScript.mitigation_fraction(5.0), 0.9, 0.0001)


func test_resolve_damage_baseline_is_weapon_effective() -> void:
	# Baseline node, perfect reliability, no mitigation -> weapon effective.
	assert_almost_eq(DamageResolutionScript.resolve_damage(10.0, 10.0, 1.0, 0.0), 10.0, 0.0001)


func test_resolve_damage_scales_with_attacker_node() -> void:
	assert_almost_eq(DamageResolutionScript.resolve_damage(10.0, 20.0, 1.0, 0.0), 20.0, 0.0001)


func test_resolve_damage_scales_with_technique_reliability() -> void:
	assert_almost_eq(DamageResolutionScript.resolve_damage(10.0, 10.0, 0.5, 0.0), 5.0, 0.0001)
	# Reliability is clamped to 0..1 (a 2.0 does not amplify).
	assert_almost_eq(DamageResolutionScript.resolve_damage(10.0, 10.0, 2.0, 0.0), 10.0, 0.0001)


func test_resolve_damage_reduced_by_mitigation() -> void:
	assert_almost_eq(DamageResolutionScript.resolve_damage(10.0, 10.0, 1.0, 0.5), 5.0, 0.0001)
	# Mitigation is capped, so damage floors at 10% of offense, never zero.
	assert_almost_eq(DamageResolutionScript.resolve_damage(10.0, 10.0, 1.0, 5.0), 1.0, 0.0001)


func test_resolve_damage_never_negative() -> void:
	assert_almost_eq(DamageResolutionScript.resolve_damage(0.0, 0.0, 0.0, 0.0), 0.0, 0.0001)
	# A negative weapon input cannot produce healing.
	assert_almost_eq(DamageResolutionScript.resolve_damage(-100.0, 10.0, 1.0, 0.0), 0.0, 0.0001)


func test_composition_end_to_end_defeats_target() -> void:
	# Weapon effective magnitude from the item contract (mastered wielder).
	var item: Object = ItemContractScript.from_wire_dict({
		"schema_version": 1, "item_id": "giant_sword", "item_class": "greatsword",
		"slot": "right_hand", "category": "mundane", "binding": "none", "base_effect": 40.0,
	})["item"]
	var weapon_effective: float = ItemContractScript.effective_value(item.base_effect, 1.0, 1.0)
	# Technique reliability from the technique contract at full proficiency.
	var reliability: float = TechniqueContractScript.reliability(1.0)
	# Baseline attacker, unarmoured defender.
	var damage: float = DamageResolutionScript.resolve_damage(weapon_effective, 10.0, reliability, 0.0)
	# 40 * 2.0 effectiveness * 1.0 node * 1.0 reliability = 80 damage.
	assert_almost_eq(damage, 80.0, 0.0001)
	var health: Object = CombatHealthScript.from_wire_dict(
		{"schema_version": 1, "max_health": 60.0, "current_health": 60.0}
	)["health"]
	var defeated: bool = health.take_damage(damage)
	assert_true(defeated, "80 damage should defeat a 60-health target")


func test_from_wire_dict_accepts_valid_request() -> void:
	var result: Dictionary = DamageResolutionScript.from_wire_dict(_wire(10.0, 20.0, 1.0, 0.5))
	assert_eq(result["outcome"], "ok")
	assert_almost_eq(float(result["damage"]), 10.0, 0.0001)


func test_from_wire_dict_rejects_unsupported_version() -> void:
	var wire: Dictionary = _wire(10.0, 10.0, 1.0, 0.0)
	wire["schema_version"] = 2
	var result: Dictionary = DamageResolutionScript.from_wire_dict(wire)
	assert_eq(result["outcome"], "unsupported_version")
	assert_almost_eq(float(result["damage"]), 0.0, 0.0001)


func test_from_wire_dict_rejects_non_finite_input() -> void:
	var wire: Dictionary = _wire(10.0, 10.0, 1.0, 0.0)
	wire["attacker_node"] = INF
	var result: Dictionary = DamageResolutionScript.from_wire_dict(wire)
	assert_eq(result["outcome"], "out_of_bounds")


func test_from_wire_dict_rejects_non_dictionary() -> void:
	var result: Dictionary = DamageResolutionScript.from_wire_dict("not a dict")
	assert_eq(result["outcome"], "malformed")
	assert_almost_eq(float(result["damage"]), 0.0, 0.0001)
