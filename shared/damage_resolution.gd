extends RefCounted
class_name DamageResolution
## Slice 121 (Phase 14): the damage-resolution composition contract. Pure,
## deterministic static helpers — like the resolution seam in
## shared/combat_contracts.gd and the other shared value contracts
## (shared/item_contract.gd, shared/technique_contract.gd,
## shared/combat_health.gd): no scene tree, no network I/O, no authority, no
## secrets. See issue #231 and
## docs/adr/0007-unified-character-and-npc-generalization.md.
##
## This is the seam that TIES the Phase 14 combat contracts together. It does
## NOT re-derive nodes, effectiveness, or reliability — those belong to their own
## contracts. It COMPOSES their already-derived scalars into a single incoming
## damage amount for CombatHealth.apply_damage:
##
##   weapon_effective   = ItemContract.effective_value(base, item_prof, class_prof)
##   attacker_node      = CharacterFoundation.effective_nodes()[primary_node]
##   technique_reliab.  = TechniqueContract.reliability(technique_prof)
##   raw_mitigation     = defender armor/CON-derived reduction (0..1)
##
##   offense = weapon_effective * attribute_scale(attacker_node) * reliability
##   damage  = offense * (1 - mitigation_fraction(raw_mitigation))
##
## The server owns every input; this contract only combines them. It is
## deliberately stateless (no value object) because damage resolution is a pure
## function of its inputs, not a persisted entity.

const SCHEMA_VERSION: int = 1

## Attribute scale reference: an attacker at the balanced creation baseline
## (CharacterFoundation.BASELINE_PER_NODE) scales offense by exactly 1.0.
const BASELINE_NODE: float = 10.0

## Mitigation never fully nullifies a hit — a landed strike always stings.
const MITIGATION_MIN: float = 0.0
const MITIGATION_CAP: float = 0.9

const MIN_DAMAGE: float = 0.0
const RELIABILITY_MIN: float = 0.0
const RELIABILITY_MAX: float = 1.0
const MAX_INPUT: float = 1.0e9

const OUTCOME_OK: String = "ok"
const OUTCOME_MALFORMED: String = "malformed"
const OUTCOME_UNSUPPORTED_VERSION: String = "unsupported_version"
const OUTCOME_OUT_OF_BOUNDS: String = "out_of_bounds"


## Attacker attribute scale: node / baseline, so a baseline node scales 1.0 and
## a doubled node scales 2.0. Negative/zero nodes scale 0.0 (no defined offense).
static func attribute_scale(node_value: float) -> float:
	return maxf(0.0, node_value) / BASELINE_NODE


## Defender mitigation as a bounded 0..CAP fraction of damage removed. Clamped so
## out-of-range armor state can neither heal the attacker (negative) nor fully
## negate a hit (>= 1.0).
static func mitigation_fraction(raw_mitigation: float) -> float:
	return clampf(raw_mitigation, MITIGATION_MIN, MITIGATION_CAP)


## Resolve a single strike's incoming damage from its already-derived parts.
## Deterministic and floored at zero; the caller feeds the result to
## CombatHealth.apply_damage.
static func resolve_damage(
	weapon_effective: float,
	attacker_node: float,
	technique_reliability: float,
	raw_mitigation: float
) -> float:
	var reliability: float = clampf(technique_reliability, RELIABILITY_MIN, RELIABILITY_MAX)
	var offense: float = maxf(0.0, weapon_effective) * attribute_scale(attacker_node) * reliability
	var damage: float = offense * (1.0 - mitigation_fraction(raw_mitigation))
	return maxf(MIN_DAMAGE, damage)


## Parse + validate an untrusted strike request and return the resolved damage.
## Fails closed on version, structure, and bounds so no caller can inject an
## absurd (non-finite/out-of-range) damage input. Returns
## {outcome, detail, damage}; damage is 0.0 on any failure.
static func from_wire_dict(wire: Variant) -> Dictionary:
	if not (wire is Dictionary):
		return _fail(OUTCOME_MALFORMED, "wire is not a Dictionary")
	var data: Dictionary = wire
	if int(data.get("schema_version", -1)) != SCHEMA_VERSION:
		return _fail(OUTCOME_UNSUPPORTED_VERSION, "unsupported schema_version")
	var weapon := _read_bounded(data, "weapon_effective", 0.0, MAX_INPUT)
	if weapon["outcome"] != OUTCOME_OK:
		return weapon
	var node := _read_bounded(data, "attacker_node", 0.0, MAX_INPUT)
	if node["outcome"] != OUTCOME_OK:
		return node
	var reliability := _read_bounded(data, "technique_reliability", 0.0, MAX_INPUT)
	if reliability["outcome"] != OUTCOME_OK:
		return reliability
	var mitigation := _read_bounded(data, "raw_mitigation", 0.0, MAX_INPUT)
	if mitigation["outcome"] != OUTCOME_OK:
		return mitigation
	var damage: float = resolve_damage(
		weapon["value"], node["value"], reliability["value"], mitigation["value"]
	)
	return {"outcome": OUTCOME_OK, "detail": "", "damage": damage}


static func _read_bounded(data: Dictionary, key: String, min_value: float, max_value: float) -> Dictionary:
	var raw: Variant = data.get(key)
	if not (raw is float or raw is int):
		return _fail(OUTCOME_MALFORMED, key + " is not numeric")
	var num: float = float(raw)
	if not is_finite(num) or num < min_value or num > max_value:
		return _fail(OUTCOME_OUT_OF_BOUNDS, key + " out of bounds")
	return {"outcome": OUTCOME_OK, "detail": "", "value": num}


static func _fail(outcome: String, detail: String) -> Dictionary:
	return {"outcome": outcome, "detail": detail, "damage": 0.0}
