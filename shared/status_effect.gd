extends RefCounted
class_name StatusEffect
## Slice 122 (Phase 14): the status-effect contract. Pure value + deterministic
## helpers, like the other shared contracts (shared/item_contract.gd,
## shared/technique_contract.gd, shared/combat_health.gd): no scene tree, no
## network I/O, no authority, no secrets. See issue #231 and
## docs/adr/0007-unified-character-and-npc-generalization.md.
##
## A status effect is a DELIBERATE magical or impairment effect (a spell, a
## poison-like slow) — never the consequence of ordinary damage, which does not
## cause injury (issue #231). Two properties define it:
##   - Resistible: a strong enough target resistance negates the effect at
##     application time (is_resisted). Deterministic; no RNG.
##   - Removable: once applied, it can be cleansed/dispelled at any time
##     (remove), and it expires on its own when its duration runs out.
## Effect magnitude (how much it slows/weakens) is consumed by the combat/stat
## layer; this contract only defines the effect, its resistance gate, and its
## lifecycle.

const SCHEMA_VERSION: int = 1

const CATEGORY_MAGICAL: String = "magical"
const CATEGORY_IMPAIRMENT: String = "impairment"
const SUPPORTED_CATEGORIES: PackedStringArray = ["magical", "impairment"]

const POTENCY_MIN: float = 0.0
const POTENCY_MAX: float = 1.0
const RESISTANCE_MIN: float = 0.0
const RESISTANCE_MAX: float = 1.0

const MIN_DURATION_TICKS: int = 1
const MAX_DURATION_TICKS: int = 1_000_000_000
const MIN_MAGNITUDE: float = 0.0
const MAX_MAGNITUDE: float = 1.0e9

const OUTCOME_OK: String = "ok"
const OUTCOME_MALFORMED: String = "malformed"
const OUTCOME_UNSUPPORTED_VERSION: String = "unsupported_version"
const OUTCOME_OUT_OF_BOUNDS: String = "out_of_bounds"
const OUTCOME_UNSUPPORTED_CATEGORY: String = "unsupported_category"

var schema_version: int
var effect_id: String
var category: String
var potency: float
var magnitude: float
var duration_ticks: int
var remaining_ticks: int


func _init(
	p_effect_id: String,
	p_category: String,
	p_potency: float,
	p_magnitude: float,
	p_duration_ticks: int
) -> void:
	schema_version = SCHEMA_VERSION
	effect_id = p_effect_id
	category = p_category
	potency = p_potency
	magnitude = p_magnitude
	duration_ticks = p_duration_ticks
	remaining_ticks = p_duration_ticks


## Whether a target with this resistance negates an effect of this potency.
## Resistance at or above the effect's potency fully resists it. Both are
## clamped to 0..1 so out-of-range state can never invert the comparison.
static func is_resisted(potency: float, resistance: float) -> bool:
	return clampf(resistance, RESISTANCE_MIN, RESISTANCE_MAX) >= clampf(potency, POTENCY_MIN, POTENCY_MAX)


## Whether this effect lands on a target with the given resistance.
func lands_against(resistance: float) -> bool:
	return not is_resisted(potency, resistance)


## Advance the effect by a number of ticks; remaining floors at zero. Returns
## whether the effect is now expired. Negative/zero ticks are ignored.
func advance(ticks: int) -> bool:
	remaining_ticks = maxi(0, remaining_ticks - maxi(0, ticks))
	return is_expired()


## Removable: cleanse/dispel the effect immediately.
func remove() -> void:
	remaining_ticks = 0


func is_active() -> bool:
	return remaining_ticks > 0


func is_expired() -> bool:
	return remaining_ticks <= 0


## Parse + validate an untrusted wire Dictionary. Fails closed on version,
## structure, category, potency/magnitude bounds, and a positive duration.
static func from_wire_dict(wire: Variant) -> Dictionary:
	if not (wire is Dictionary):
		return _fail(OUTCOME_MALFORMED, "wire is not a Dictionary")
	var data: Dictionary = wire
	if int(data.get("schema_version", -1)) != SCHEMA_VERSION:
		return _fail(OUTCOME_UNSUPPORTED_VERSION, "unsupported schema_version")
	var effect_id: Variant = data.get("effect_id")
	if not (effect_id is String) or String(effect_id).is_empty():
		return _fail(OUTCOME_MALFORMED, "effect_id must be a non-empty string")
	var category: Variant = data.get("category")
	if not (category is String) or not SUPPORTED_CATEGORIES.has(category):
		return _fail(OUTCOME_UNSUPPORTED_CATEGORY, "unknown category")
	var potency_raw: Variant = data.get("potency")
	if not (potency_raw is float or potency_raw is int):
		return _fail(OUTCOME_MALFORMED, "potency is not numeric")
	var potency: float = float(potency_raw)
	if not is_finite(potency) or potency < POTENCY_MIN or potency > POTENCY_MAX:
		return _fail(OUTCOME_OUT_OF_BOUNDS, "potency out of bounds")
	var magnitude_raw: Variant = data.get("magnitude")
	if not (magnitude_raw is float or magnitude_raw is int):
		return _fail(OUTCOME_MALFORMED, "magnitude is not numeric")
	var magnitude: float = float(magnitude_raw)
	if not is_finite(magnitude) or magnitude < MIN_MAGNITUDE or magnitude > MAX_MAGNITUDE:
		return _fail(OUTCOME_OUT_OF_BOUNDS, "magnitude out of bounds")
	var duration_raw: Variant = data.get("duration_ticks")
	if not (duration_raw is int or duration_raw is float):
		return _fail(OUTCOME_MALFORMED, "duration_ticks is not numeric")
	if duration_raw is float and float(duration_raw) != floor(float(duration_raw)):
		return _fail(OUTCOME_MALFORMED, "duration_ticks must be a whole number")
	var duration_ticks: int = int(duration_raw)
	if duration_ticks < MIN_DURATION_TICKS or duration_ticks > MAX_DURATION_TICKS:
		return _fail(OUTCOME_OUT_OF_BOUNDS, "duration_ticks out of bounds")
	var effect := StatusEffect.new(String(effect_id), String(category), potency, magnitude, duration_ticks)
	return {"outcome": OUTCOME_OK, "detail": "", "effect": effect}


static func _fail(outcome: String, detail: String) -> Dictionary:
	return {"outcome": outcome, "detail": detail, "effect": null}
