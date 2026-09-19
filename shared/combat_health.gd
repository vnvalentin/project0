extends RefCounted
class_name CombatHealth
## Slice 120 (Phase 14): the shared health / defeat / recovery contract for
## players and NPCs. Ordinary damage reduces a health pool toward defeat and
## recovery restores it; there is **no injury subsystem** (issue #231). Pure
## value + deterministic helpers, like the other shared contracts
## (shared/character_foundation.gd, shared/technique_contract.gd): no scene
## tree, no network I/O, no authority, no secrets. See
## docs/adr/0007-unified-character-and-npc-generalization.md.
##
## Damage magnitudes are produced by a later combat-resolution slice (attacker
## effective stats + equipment + technique + defender mitigation); this contract
## only applies a given amount to a pool. Deliberate magical/impairment status
## effects are a separate contract. The presentation layer gets a 0..1 health
## fraction, not the raw numbers.

const SCHEMA_VERSION: int = 1

const MIN_HEALTH: float = 0.0
const MAX_HEALTH_CAP: float = 1.0e9

const OUTCOME_OK: String = "ok"
const OUTCOME_MALFORMED: String = "malformed"
const OUTCOME_UNSUPPORTED_VERSION: String = "unsupported_version"
const OUTCOME_OUT_OF_BOUNDS: String = "out_of_bounds"

var schema_version: int
var max_health: float
var current_health: float


func _init(p_max_health: float, p_current_health: float) -> void:
	schema_version = SCHEMA_VERSION
	max_health = p_max_health
	current_health = p_current_health


## Apply damage to a health value: current - max(0, amount), floored at 0.
## Negative "damage" is ignored (damage never heals). Deterministic.
static func apply_damage(current: float, amount: float) -> float:
	return maxf(MIN_HEALTH, current - maxf(0.0, amount))


## Apply recovery: current + max(0, amount), capped at max_health. Negative
## "recovery" is ignored (recovery never harms). Deterministic.
static func apply_recovery(current: float, p_max_health: float, amount: float) -> float:
	return minf(p_max_health, current + maxf(0.0, amount))


## A health value is defeated when it reaches zero.
static func is_defeated(current: float) -> bool:
	return current <= MIN_HEALTH


## Presentation-safe health fraction (0..1) for a bar without exposing the raw
## numbers. Fails safe to 0 for a non-positive max.
static func health_fraction(current: float, p_max_health: float) -> float:
	if p_max_health <= 0.0:
		return 0.0
	return clampf(current / p_max_health, 0.0, 1.0)


## Instance convenience: mutate current health by damage; returns whether the
## Character is now defeated.
func take_damage(amount: float) -> bool:
	current_health = apply_damage(current_health, amount)
	return is_now_defeated()


## Instance convenience: mutate current health by recovery.
func heal(amount: float) -> void:
	current_health = apply_recovery(current_health, max_health, amount)


func is_now_defeated() -> bool:
	return is_defeated(current_health)


func fraction() -> float:
	return health_fraction(current_health, max_health)


## Parse + validate an untrusted wire Dictionary. Fails closed on version,
## structure, and bounds (max in (0, cap]; current in [0, max]).
static func from_wire_dict(wire: Variant) -> Dictionary:
	if not (wire is Dictionary):
		return _fail(OUTCOME_MALFORMED, "wire is not a Dictionary")
	var data: Dictionary = wire
	if int(data.get("schema_version", -1)) != SCHEMA_VERSION:
		return _fail(OUTCOME_UNSUPPORTED_VERSION, "unsupported schema_version")
	var max_raw: Variant = data.get("max_health")
	if not (max_raw is float or max_raw is int):
		return _fail(OUTCOME_MALFORMED, "max_health is not numeric")
	var max_health: float = float(max_raw)
	if not is_finite(max_health) or max_health <= 0.0 or max_health > MAX_HEALTH_CAP:
		return _fail(OUTCOME_OUT_OF_BOUNDS, "max_health out of bounds")
	var current_raw: Variant = data.get("current_health")
	if not (current_raw is float or current_raw is int):
		return _fail(OUTCOME_MALFORMED, "current_health is not numeric")
	var current_health: float = float(current_raw)
	if not is_finite(current_health) or current_health < 0.0 or current_health > max_health:
		return _fail(OUTCOME_OUT_OF_BOUNDS, "current_health out of bounds")
	var health := CombatHealth.new(max_health, current_health)
	return {"outcome": OUTCOME_OK, "detail": "", "health": health}


static func _fail(outcome: String, detail: String) -> Dictionary:
	return {"outcome": outcome, "detail": detail, "health": null}
