extends RefCounted
class_name ActivityRoutine
## Slice 123 (Phase 14): the activity-routine contract for activity-driven NPC
## movement. Pure value + deterministic helpers, like the other shared contracts
## (shared/technique_contract.gd, shared/status_effect.gd): no scene tree, no
## network I/O, no authority, no secrets. See issue #229 and
## docs/adr/0007-unified-character-and-npc-generalization.md.
##
## An NPC follows a looping sequence of timed activities (its routine). Which
## activity it is doing is a PURE function of elapsed ticks — so an unobserved
## NPC can be simulated off-screen for free and, when re-observed, is exactly
## where its route says it should be (route-consistent arrival) with no drift.
## When the routine is empty the NPC falls back to a default idle/patrol
## activity. A routine is interruptible: an interruption (e.g. combat) overrides
## the current activity until resumed, without losing the routine's own clock.
##
## This contract defines the routine, resolves the current activity from time,
## and models the interrupt/resume lifecycle. Actual pathfinding, rendering,
## world locations, and activity-scoped following are scene-layer concerns and
## are NOT modeled here.

const SCHEMA_VERSION: int = 1

const FALLBACK_IDLE: String = "idle"
const FALLBACK_PATROL: String = "patrol"
const SUPPORTED_FALLBACKS: PackedStringArray = ["idle", "patrol"]

## Where the current activity came from.
const SOURCE_ROUTINE: String = "routine"
const SOURCE_FALLBACK: String = "fallback"
const SOURCE_INTERRUPT: String = "interrupt"

const STATE_ACTIVE: String = "active"
const STATE_INTERRUPTED: String = "interrupted"

const MIN_STEP_TICKS: int = 1
const MAX_STEP_TICKS: int = 1_000_000_000

const OUTCOME_OK: String = "ok"
const OUTCOME_MALFORMED: String = "malformed"
const OUTCOME_UNSUPPORTED_VERSION: String = "unsupported_version"
const OUTCOME_OUT_OF_BOUNDS: String = "out_of_bounds"
const OUTCOME_UNSUPPORTED_FALLBACK: String = "unsupported_fallback"

var schema_version: int
## Ordered steps: each an immutable {activity_id: String, duration_ticks: int}.
var steps: Array
var fallback_mode: String
var state: String
var interrupt_activity_id: String


func _init(p_steps: Array, p_fallback_mode: String) -> void:
	schema_version = SCHEMA_VERSION
	steps = p_steps
	fallback_mode = p_fallback_mode
	state = STATE_ACTIVE
	interrupt_activity_id = ""


## Total looping period of the routine (sum of step durations). Zero when empty.
static func total_duration(p_steps: Array) -> int:
	var total: int = 0
	for step in p_steps:
		total += int((step as Dictionary).get("duration_ticks", 0))
	return total


## Resolve which routine step is current at the given elapsed ticks, looping over
## the total period so the routine repeats deterministically. Returns
## {index, activity_id, step_elapsed, step_remaining}; index -1 for an empty
## routine. A pure function of time — this is the off-screen simulation.
static func resolve_step(p_steps: Array, elapsed_ticks: int) -> Dictionary:
	var period: int = total_duration(p_steps)
	if p_steps.is_empty() or period <= 0:
		return {"index": -1, "activity_id": "", "step_elapsed": 0, "step_remaining": 0}
	var phase: int = maxi(0, elapsed_ticks) % period
	var cursor: int = 0
	for i in p_steps.size():
		var duration: int = int((p_steps[i] as Dictionary).get("duration_ticks", 0))
		if phase < cursor + duration:
			var step_elapsed: int = phase - cursor
			return {
				"index": i,
				"activity_id": String((p_steps[i] as Dictionary).get("activity_id", "")),
				"step_elapsed": step_elapsed,
				"step_remaining": duration - step_elapsed,
			}
		cursor += duration
	# Unreachable while phase < period, but fail safe to the last step.
	var last: Dictionary = p_steps[p_steps.size() - 1]
	return {
		"index": p_steps.size() - 1,
		"activity_id": String(last.get("activity_id", "")),
		"step_elapsed": int(last.get("duration_ticks", 0)),
		"step_remaining": 0,
	}


## The NPC's current activity at the given elapsed ticks. An interruption
## overrides everything; an empty routine falls back to idle/patrol; otherwise
## the routine step. Returns {activity_id, source}.
func current_activity(elapsed_ticks: int) -> Dictionary:
	if state == STATE_INTERRUPTED:
		return {"activity_id": interrupt_activity_id, "source": SOURCE_INTERRUPT}
	if steps.is_empty():
		return {"activity_id": fallback_mode, "source": SOURCE_FALLBACK}
	var step: Dictionary = resolve_step(steps, elapsed_ticks)
	return {"activity_id": step["activity_id"], "source": SOURCE_ROUTINE}


## Interrupt the routine with an overriding activity. The routine's own clock is
## unaffected, so resuming lands on the route-consistent activity for the time.
func interrupt(activity_id: String) -> void:
	state = STATE_INTERRUPTED
	interrupt_activity_id = activity_id


func resume() -> void:
	state = STATE_ACTIVE
	interrupt_activity_id = ""


func is_interrupted() -> bool:
	return state == STATE_INTERRUPTED


## Parse + validate an untrusted wire Dictionary. Fails closed on version,
## structure, the steps array (activity_id/duration), and the fallback mode. An
## empty steps array is valid and means pure idle/patrol fallback.
static func from_wire_dict(wire: Variant) -> Dictionary:
	if not (wire is Dictionary):
		return _fail(OUTCOME_MALFORMED, "wire is not a Dictionary")
	var data: Dictionary = wire
	if int(data.get("schema_version", -1)) != SCHEMA_VERSION:
		return _fail(OUTCOME_UNSUPPORTED_VERSION, "unsupported schema_version")
	var raw_steps: Variant = data.get("steps")
	if not (raw_steps is Array):
		return _fail(OUTCOME_MALFORMED, "steps is not an Array")
	var validated: Array = []
	for raw_step in (raw_steps as Array):
		if not (raw_step is Dictionary):
			return _fail(OUTCOME_MALFORMED, "step is not a Dictionary")
		var step: Dictionary = raw_step
		var activity_id: Variant = step.get("activity_id")
		if not (activity_id is String) or String(activity_id).is_empty():
			return _fail(OUTCOME_MALFORMED, "activity_id must be a non-empty string")
		var duration_raw: Variant = step.get("duration_ticks")
		if not (duration_raw is int or duration_raw is float):
			return _fail(OUTCOME_MALFORMED, "duration_ticks is not numeric")
		if duration_raw is float and float(duration_raw) != floor(float(duration_raw)):
			return _fail(OUTCOME_MALFORMED, "duration_ticks must be a whole number")
		var duration_ticks: int = int(duration_raw)
		if duration_ticks < MIN_STEP_TICKS or duration_ticks > MAX_STEP_TICKS:
			return _fail(OUTCOME_OUT_OF_BOUNDS, "duration_ticks out of bounds")
		validated.append({"activity_id": String(activity_id), "duration_ticks": duration_ticks})
	var fallback: Variant = data.get("fallback_mode", FALLBACK_IDLE)
	if not (fallback is String) or not SUPPORTED_FALLBACKS.has(fallback):
		return _fail(OUTCOME_UNSUPPORTED_FALLBACK, "unknown fallback_mode")
	var routine := ActivityRoutine.new(validated, String(fallback))
	return {"outcome": OUTCOME_OK, "detail": "", "routine": routine}


static func _fail(outcome: String, detail: String) -> Dictionary:
	return {"outcome": outcome, "detail": detail, "routine": null}
