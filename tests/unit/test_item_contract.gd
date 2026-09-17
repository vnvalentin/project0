extends GutTest
## Slice 118 (Phase 14): public-seam tests for the item + equipment contract.
## The effectiveness curve matches the canonical giant-sword example, the proc
## unlocks at mastery and improves with class mastery, binding governs
## tradeability, and parsing fails closed.

const ItemContractScript: Script = preload("res://shared/item_contract.gd")


func _wire(slot: String, category: String, base_effect: float, binding: String = "none") -> Dictionary:
	return {
		"schema_version": 1,
		"item_id": "giant_sword_01",
		"item_class": "giant_sword",
		"slot": slot,
		"category": category,
		"binding": binding,
		"base_effect": base_effect,
	}


func test_effectiveness_curve_matches_the_giant_sword_example() -> void:
	# class 0: 0% -> 50%, 50% -> 100%, 100% -> 150%
	assert_almost_eq(ItemContractScript.effectiveness_multiplier(0.0, 0.0), 0.5, 0.0001)
	assert_almost_eq(ItemContractScript.effectiveness_multiplier(0.5, 0.0), 1.0, 0.0001)
	assert_almost_eq(ItemContractScript.effectiveness_multiplier(1.0, 0.0), 1.5, 0.0001)
	# class 1: unfamiliarity gone (floor 100%), mastery reaches 200%
	assert_almost_eq(ItemContractScript.effectiveness_multiplier(0.0, 1.0), 1.0, 0.0001)
	assert_almost_eq(ItemContractScript.effectiveness_multiplier(1.0, 1.0), 2.0, 0.0001)


func test_effective_value_scales_base_effect_by_the_multiplier() -> void:
	assert_almost_eq(ItemContractScript.effective_value(100.0, 0.0, 0.0), 50.0, 0.0001)
	assert_almost_eq(ItemContractScript.effective_value(100.0, 1.0, 0.0), 150.0, 0.0001)
	assert_almost_eq(ItemContractScript.effective_value(100.0, 1.0, 1.0), 200.0, 0.0001)


func test_effectiveness_clamps_out_of_range_proficiency() -> void:
	# Values beyond 0..1 cannot produce an absurd multiplier.
	assert_almost_eq(ItemContractScript.effectiveness_multiplier(5.0, 5.0), 2.0, 0.0001)
	assert_almost_eq(ItemContractScript.effectiveness_multiplier(-5.0, -5.0), 0.5, 0.0001)


func test_proc_unlocks_at_mastery_and_improves_with_class_mastery() -> void:
	assert_false(ItemContractScript.has_proc(0.99), "proc locked below full item proficiency")
	assert_true(ItemContractScript.has_proc(1.0), "proc unlocks at full item proficiency")
	assert_almost_eq(ItemContractScript.proc_multiplier(0.0), 1.0, 0.0001)
	assert_almost_eq(ItemContractScript.proc_multiplier(1.0), 1.5, 0.0001)


func test_binding_governs_tradeability() -> void:
	var free: Object = ItemContractScript.from_wire_dict(_wire("right_hand", "mundane", 100.0, "none"))["item"]
	var quest: Object = ItemContractScript.from_wire_dict(_wire("right_hand", "mundane", 100.0, "quest"))["item"]
	var locked: Object = ItemContractScript.from_wire_dict(_wire("right_hand", "mundane", 100.0, "player_locked"))["item"]
	assert_true(free.is_tradeable())
	assert_false(quest.is_tradeable())
	assert_false(locked.is_tradeable())


func test_magical_and_mundane_categories_both_parse() -> void:
	assert_eq(ItemContractScript.from_wire_dict(_wire("right_hand", "mundane", 10.0))["outcome"], "ok")
	assert_eq(ItemContractScript.from_wire_dict(_wire("back", "magical", 10.0))["outcome"], "ok")


func test_from_wire_dict_rejects_unsupported_version() -> void:
	var wire: Dictionary = _wire("right_hand", "mundane", 10.0)
	wire["schema_version"] = 999
	var result: Dictionary = ItemContractScript.from_wire_dict(wire)
	assert_eq(result["outcome"], "unsupported_version")
	assert_null(result["item"])


func test_from_wire_dict_rejects_unsupported_slot() -> void:
	var result: Dictionary = ItemContractScript.from_wire_dict(_wire("tail", "mundane", 10.0))
	assert_eq(result["outcome"], "unsupported_slot")


func test_from_wire_dict_rejects_unsupported_category() -> void:
	var result: Dictionary = ItemContractScript.from_wire_dict(_wire("right_hand", "cursed", 10.0))
	assert_eq(result["outcome"], "unsupported_category")


func test_from_wire_dict_rejects_unsupported_binding() -> void:
	var result: Dictionary = ItemContractScript.from_wire_dict(_wire("right_hand", "mundane", 10.0, "soulbound"))
	assert_eq(result["outcome"], "unsupported_binding")


func test_from_wire_dict_rejects_out_of_bounds_base_effect() -> void:
	var result: Dictionary = ItemContractScript.from_wire_dict(_wire("right_hand", "mundane", -5.0))
	assert_eq(result["outcome"], "out_of_bounds")


func test_from_wire_dict_rejects_non_dictionary() -> void:
	var result: Dictionary = ItemContractScript.from_wire_dict("not a dict")
	assert_eq(result["outcome"], "malformed")
