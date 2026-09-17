extends RefCounted
class_name ItemContract
## Slice 118 (Phase 14): the item + equipment-effectiveness contract. Pure value
## + deterministic helpers, like the other shared contracts
## (shared/character_foundation.gd, shared/character_alignment.gd): no scene
## tree, no network I/O, no authority, no secrets. See issue #233 and
## docs/adr/0007-unified-character-and-npc-generalization.md.
##
## An item carries fixed metadata (slot, category, binding, base_effect). How
## effective it is for a given Character is a pure function of two separate
## 0..1 proficiencies: item proficiency (specific item, grows fast) and
## item-class proficiency (transfers across the class, grows slowly). The
## effectiveness curve matches the canonical giant-sword example:
##   item_prof 0% -> 50% effect, 50% -> 100%, 100% -> 150%;
##   at 100% class proficiency the unfamiliarity penalty is gone (floor 100%)
##   and mastery reaches 200%, with an improved direct-effect proc.
## Proficiency values themselves are per-Character-per-item state owned
## elsewhere; this contract only derives outcomes from them.

const SCHEMA_VERSION: int = 1

## Fixed equipment slots.
const SLOTS: PackedStringArray = [
	"head", "body", "arms", "hands", "rings", "back", "legs", "boots",
	"necklace", "earrings", "left_hand", "right_hand", "ranged_weapon", "bags",
]

const CATEGORY_MUNDANE: String = "mundane"
const CATEGORY_MAGICAL: String = "magical"
const SUPPORTED_CATEGORIES: PackedStringArray = ["mundane", "magical"]

const BINDING_NONE: String = "none"
const BINDING_QUEST: String = "quest"
const BINDING_PLAYER_LOCKED: String = "player_locked"
const SUPPORTED_BINDINGS: PackedStringArray = ["none", "quest", "player_locked"]

const PROFICIENCY_MIN: float = 0.0
const PROFICIENCY_MAX: float = 1.0
const MAX_BASE_EFFECT: float = 1.0e9

## Effectiveness curve: multiplier = BASE_FLOOR + CLASS_FLOOR_BONUS*class + item.
## class 0: 0.5 + item (0.5 .. 1.5). class 1: 1.0 + item (1.0 .. 2.0).
const BASE_FLOOR: float = 0.5
const CLASS_FLOOR_BONUS: float = 0.5

## Direct-effect proc unlocks at full item proficiency; class mastery improves it.
const PROC_UNLOCK_THRESHOLD: float = 1.0
const PROC_BASE_MULTIPLIER: float = 1.0
const PROC_CLASS_BONUS: float = 0.5

const OUTCOME_OK: String = "ok"
const OUTCOME_MALFORMED: String = "malformed"
const OUTCOME_UNSUPPORTED_VERSION: String = "unsupported_version"
const OUTCOME_OUT_OF_BOUNDS: String = "out_of_bounds"
const OUTCOME_UNSUPPORTED_SLOT: String = "unsupported_slot"
const OUTCOME_UNSUPPORTED_CATEGORY: String = "unsupported_category"
const OUTCOME_UNSUPPORTED_BINDING: String = "unsupported_binding"

var schema_version: int
var item_id: String
var item_class: String
var slot: String
var category: String
var binding: String
var base_effect: float


func _init(
	p_item_id: String,
	p_item_class: String,
	p_slot: String,
	p_category: String,
	p_binding: String,
	p_base_effect: float
) -> void:
	schema_version = SCHEMA_VERSION
	item_id = p_item_id
	item_class = p_item_class
	slot = p_slot
	category = p_category
	binding = p_binding
	base_effect = p_base_effect


## Effectiveness multiplier for the given per-Character proficiencies. Inputs are
## clamped to 0..1 so out-of-range state can never produce an absurd multiplier.
static func effectiveness_multiplier(item_proficiency: float, class_proficiency: float) -> float:
	var item_p: float = clampf(item_proficiency, PROFICIENCY_MIN, PROFICIENCY_MAX)
	var class_p: float = clampf(class_proficiency, PROFICIENCY_MIN, PROFICIENCY_MAX)
	return BASE_FLOOR + (CLASS_FLOOR_BONUS * class_p) + item_p


## The item's effective magnitude for a Character with these proficiencies.
static func effective_value(base_effect: float, item_proficiency: float, class_proficiency: float) -> float:
	return base_effect * effectiveness_multiplier(item_proficiency, class_proficiency)


## Whether the item's direct-effect proc is unlocked at this item proficiency.
static func has_proc(item_proficiency: float) -> bool:
	return clampf(item_proficiency, PROFICIENCY_MIN, PROFICIENCY_MAX) >= PROC_UNLOCK_THRESHOLD


## The proc magnitude multiplier, improved by class mastery.
static func proc_multiplier(class_proficiency: float) -> float:
	var class_p: float = clampf(class_proficiency, PROFICIENCY_MIN, PROFICIENCY_MAX)
	return PROC_BASE_MULTIPLIER + (PROC_CLASS_BONUS * class_p)


## Whether this item is freely tradeable (only quest/player-locked items bind).
func is_tradeable() -> bool:
	return binding == BINDING_NONE


## Parse + validate an untrusted wire Dictionary. Fails closed on version,
## structure, slot/category/binding enums, and base_effect bounds.
static func from_wire_dict(wire: Variant) -> Dictionary:
	if not (wire is Dictionary):
		return _fail(OUTCOME_MALFORMED, "wire is not a Dictionary")
	var data: Dictionary = wire
	if int(data.get("schema_version", -1)) != SCHEMA_VERSION:
		return _fail(OUTCOME_UNSUPPORTED_VERSION, "unsupported schema_version")
	var item_id: Variant = data.get("item_id")
	if not (item_id is String) or String(item_id).is_empty():
		return _fail(OUTCOME_MALFORMED, "item_id must be a non-empty string")
	var item_class: Variant = data.get("item_class")
	if not (item_class is String) or String(item_class).is_empty():
		return _fail(OUTCOME_MALFORMED, "item_class must be a non-empty string")
	var slot: Variant = data.get("slot")
	if not (slot is String) or not SLOTS.has(slot):
		return _fail(OUTCOME_UNSUPPORTED_SLOT, "unknown slot")
	var category: Variant = data.get("category")
	if not (category is String) or not SUPPORTED_CATEGORIES.has(category):
		return _fail(OUTCOME_UNSUPPORTED_CATEGORY, "unknown category")
	var binding: Variant = data.get("binding", BINDING_NONE)
	if not (binding is String) or not SUPPORTED_BINDINGS.has(binding):
		return _fail(OUTCOME_UNSUPPORTED_BINDING, "unknown binding")
	var base_effect_raw: Variant = data.get("base_effect")
	if not (base_effect_raw is float or base_effect_raw is int):
		return _fail(OUTCOME_MALFORMED, "base_effect is not numeric")
	var base_effect: float = float(base_effect_raw)
	if not is_finite(base_effect) or base_effect < 0.0 or base_effect > MAX_BASE_EFFECT:
		return _fail(OUTCOME_OUT_OF_BOUNDS, "base_effect out of bounds")
	var item := ItemContract.new(
		String(item_id), String(item_class), String(slot), String(category), String(binding), base_effect
	)
	return {"outcome": OUTCOME_OK, "detail": "", "item": item}


static func _fail(outcome: String, detail: String) -> Dictionary:
	return {"outcome": outcome, "detail": detail, "item": null}
