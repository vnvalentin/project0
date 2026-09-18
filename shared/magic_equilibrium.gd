extends RefCounted
class_name MagicEquilibrium
## Slice 139 (Phase 15, P-016-F): magic equilibrium and its opportunity cost.
## Magic requires bodily equilibrium: muscle mass and physical bulk (STR + CON)
## act as an electrical insulator that grounds magical currents, so a hyper-bulked
## brute cannot channel — the vessel must organically lean out for higher tiers.
## A validated attempt resolves as CHANNELED, FIZZLE, BACKLASH, or REJECTED with a
## bounded reason — never a client-selected success, and never silently consumed
## without an outcome. Pure, deterministic server-side derivation from the
## effective vessel, requested tier, and tuning. See
## docs/SYSTEMS-SPECIFICATION.md ("Magic Equilibrium And Opportunity Cost") and
## docs/adr/0006-versioned-embodiment-mechanics-architecture.md.

const OUTCOME_CHANNELED: String = "CHANNELED"
const OUTCOME_FIZZLE: String = "FIZZLE"
const OUTCOME_BACKLASH: String = "BACKLASH"
const OUTCOME_REJECTED: String = "REJECTED"

const REASON_NONE: String = ""
const REASON_UNSUPPORTED_TIER: String = "unsupported_tier"
const REASON_INSUFFICIENT_EQUILIBRIUM: String = "insufficient_equilibrium"
const REASON_INSULATION_OVERLOAD: String = "insulation_overload"


## Resolve a magic attempt from the effective nodes, requested spell tier, and
## tuning. Insulation = (STR + CON) × coefficient; a tier's channel ceiling
## shrinks with tier, so higher tiers demand a leaner vessel. At/under the ceiling
## channels; within the fizzle margin above it fizzles; beyond that the grounded
## current backlashes. An out-of-range tier is rejected. Always returns an
## explicit {outcome, reason} — a request is never silently consumed.
static func resolve(effective_nodes: Dictionary, spell_tier: int, tuning: Object) -> Dictionary:
	var params: Dictionary = tuning.magic()
	if spell_tier < 1 or spell_tier > int(params["max_tier"]):
		return _result(OUTCOME_REJECTED, REASON_UNSUPPORTED_TIER)
	var bulk: float = maxf(0.0, float(effective_nodes.get("STR", 0.0)) + float(effective_nodes.get("CON", 0.0)))
	var insulation: float = bulk * float(params["insulation_coefficient"])
	var ceiling: float = maxf(0.0, float(params["base_channel_ceiling"]) - float(spell_tier - 1) * float(params["ceiling_step_per_tier"]))
	if insulation <= ceiling:
		return _result(OUTCOME_CHANNELED, REASON_NONE)
	if insulation <= ceiling + float(params["fizzle_margin"]):
		return _result(OUTCOME_FIZZLE, REASON_INSUFFICIENT_EQUILIBRIUM)
	return _result(OUTCOME_BACKLASH, REASON_INSULATION_OVERLOAD)


## The insulation a vessel presents (bulk grounds magic). Exposed for callers and
## tests that reason about equilibrium eligibility.
static func insulation_for(effective_nodes: Dictionary, tuning: Object) -> float:
	var bulk: float = maxf(0.0, float(effective_nodes.get("STR", 0.0)) + float(effective_nodes.get("CON", 0.0)))
	return bulk * float(tuning.magic()["insulation_coefficient"])


static func _result(outcome: String, reason: String) -> Dictionary:
	return {"outcome": outcome, "reason": reason}
