extends RefCounted
class_name BurnoutInstance
## Slice 138 (Phase 15, P-016-E): Biological Burnout. Pushing maximum Output
## through one pathway is an Overload Surge; once the server accepts it, that
## pathway enters Burnout from internal friction, and its effective DEX / Kinetic
## Control are flattened to zero until the cooldown expires on the server clock.
## Burnout is a TEMPORARY MODIFIER with authoritative start/end tick, pathway,
## source action, and tuning version — it MUST NOT write zero into persistent
## vessel DEX, training history, or the unmodified kinetic inputs. Pure value +
## deterministic time/lifecycle helpers; the server owns the clock and every
## state transition. See docs/SYSTEMS-SPECIFICATION.md ("Biological Burnout") and
## docs/adr/0006-versioned-embodiment-mechanics-architecture.md.

const SCHEMA_VERSION: int = 1

const SUPPORTED_PATHWAYS: PackedStringArray = ["impact", "flow", "spark"]

## Normative lifecycle states. Only the server may enter ACTIVE_SURGE,
## BURNED_OUT, or RECOVERED.
const STATE_READY: String = "READY"
const STATE_SURGE_VALIDATING: String = "SURGE_VALIDATING"
const STATE_ACTIVE_SURGE: String = "ACTIVE_SURGE"
const STATE_BURNED_OUT: String = "BURNED_OUT"
const STATE_RECOVERED: String = "RECOVERED"
const STATE_REJECTED: String = "REJECTED"

const OUTCOME_OK: String = "ok"
const OUTCOME_MALFORMED: String = "malformed"
const OUTCOME_UNSUPPORTED_PATHWAY: String = "unsupported_pathway"

## Allowed lifecycle transitions (READY -> SURGE_VALIDATING -> ACTIVE_SURGE ->
## BURNED_OUT -> RECOVERED -> READY; SURGE_VALIDATING/ACTIVE_SURGE -> REJECTED).
const _TRANSITIONS: Dictionary = {
	"READY": ["SURGE_VALIDATING"],
	"SURGE_VALIDATING": ["ACTIVE_SURGE", "REJECTED"],
	"ACTIVE_SURGE": ["BURNED_OUT", "REJECTED"],
	"BURNED_OUT": ["RECOVERED"],
	"RECOVERED": ["READY"],
	"REJECTED": ["READY"],
}

var schema_version: int
var burnout_id: String
var pathway: String
var source_action_id: String
var start_tick: int
var end_tick: int
var tuning_version: String


func _init(
	p_burnout_id: String,
	p_pathway: String,
	p_source_action_id: String,
	p_start_tick: int,
	p_end_tick: int,
	p_tuning_version: String
) -> void:
	schema_version = SCHEMA_VERSION
	burnout_id = p_burnout_id
	pathway = p_pathway
	source_action_id = p_source_action_id
	start_tick = p_start_tick
	end_tick = p_end_tick
	tuning_version = p_tuning_version


## Create a Burnout from an accepted Overload Surge: the cooldown window is
## [start_tick, start_tick + duration) from the current tuning. Fails closed on an
## unsupported pathway or malformed ids. Returns {outcome, detail, burnout}.
static func from_accepted_surge(
	burnout_id: String,
	pathway: String,
	source_action_id: String,
	start_tick: int,
	tuning: Object
) -> Dictionary:
	if not SUPPORTED_PATHWAYS.has(pathway):
		return _fail(OUTCOME_UNSUPPORTED_PATHWAY, "unknown pathway: %s" % pathway)
	if burnout_id.is_empty() or source_action_id.is_empty():
		return _fail(OUTCOME_MALFORMED, "burnout_id and source_action_id must be non-empty")
	var duration: int = int(tuning.burnout()["duration_ticks"])
	var end_tick: int = start_tick + duration
	var burnout := BurnoutInstance.new(
		burnout_id, pathway, source_action_id, start_tick, end_tick, String(tuning.tuning_version)
	)
	return {"outcome": OUTCOME_OK, "detail": "", "burnout": burnout}


## Whether the Burnout is active at the given authoritative tick.
func is_active(current_tick: int) -> bool:
	return current_tick >= start_tick and current_tick < end_tick


## Whether the Burnout has expired (the server restores effective values here).
func is_expired(current_tick: int) -> bool:
	return current_tick >= end_tick


## The multiplier applied to effective Control/DEX for the given pathway at the
## current tick: 0.0 (flattened) while this Burnout is active on that same
## pathway, else 1.0. A pure derivation modifier — it never writes the base.
func control_multiplier_for(query_pathway: String, current_tick: int) -> float:
	if query_pathway == pathway and is_active(current_tick):
		return 0.0
	return 1.0


## Whether a lifecycle transition is allowed by the normative state machine.
static func valid_transition(from_state: String, to_state: String) -> bool:
	var allowed: Array = _TRANSITIONS.get(from_state, [])
	return allowed.has(to_state)


static func _fail(outcome: String, detail: String) -> Dictionary:
	return {"outcome": outcome, "detail": detail, "burnout": null}
