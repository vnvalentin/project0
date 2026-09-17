extends RefCounted
class_name SpawnAnchor
## Slice 124 (Phase 14): the spawn-anchor / NPC-population contract. Pure value +
## deterministic helpers, like the other shared contracts
## (shared/activity_routine.gd, shared/status_effect.gd): no scene tree, no
## network I/O, no authority, no secrets. See issue #232 and
## docs/adr/0007-unified-character-and-npc-generalization.md.
##
## A settlement is staffed at FIXED anchors — a guard post, a market stall — each
## wanting a certain number of a role filled. When an occupant is lost (defeated,
## wandered off), the anchor does NOT instantly respawn a clone: refill is
## DELAYED and driven by PRESSURE (demand), so a busy place refills faster than a
## sleepy one. A refill is either a SILENT PROMOTION of an existing ambient NPC
## into the role, or, when none is available, a NEWLY GENERATED identity — never
## the same individual back from the dead (no reincarnation of named NPCs).
##
## This contract owns the deterministic staffing math: deficit, the
## pressure-scaled delay, whether a replacement is due, and whether it promotes
## or generates. Contextual identity generation, the actual NPC spawn, and which
## ambient candidate is chosen are scene-layer/later concerns.

const SCHEMA_VERSION: int = 1

const PRESSURE_MIN: float = 0.0
const PRESSURE_MAX: float = 1.0

## How a due replacement is sourced.
const SOURCE_PROMOTE: String = "promote"
const SOURCE_GENERATE: String = "generate"
const SOURCE_NONE: String = "none"

const MIN_COUNT: int = 0
const MAX_COUNT: int = 1_000_000
const MIN_DELAY_TICKS: int = 0
const MAX_DELAY_TICKS: int = 1_000_000_000

const OUTCOME_OK: String = "ok"
const OUTCOME_MALFORMED: String = "malformed"
const OUTCOME_UNSUPPORTED_VERSION: String = "unsupported_version"
const OUTCOME_OUT_OF_BOUNDS: String = "out_of_bounds"

var schema_version: int
var anchor_id: String
var role: String
var desired_capacity: int
var current_occupancy: int
var replacement_delay_ticks: int
## Ticks the anchor has been understaffed; the delay clock. Reset when full.
var ticks_since_vacancy: int


func _init(
	p_anchor_id: String,
	p_role: String,
	p_desired_capacity: int,
	p_current_occupancy: int,
	p_replacement_delay_ticks: int
) -> void:
	schema_version = SCHEMA_VERSION
	anchor_id = p_anchor_id
	role = p_role
	desired_capacity = p_desired_capacity
	current_occupancy = p_current_occupancy
	replacement_delay_ticks = p_replacement_delay_ticks
	ticks_since_vacancy = 0


## Unfilled slots at the anchor; zero when full or overstaffed.
static func deficit(desired: int, current: int) -> int:
	return maxi(0, desired - current)


## The delay before a refill, shortened by pressure: no pressure keeps the full
## base delay, full pressure refills immediately. Pressure is clamped to 0..1.
static func effective_delay(base_delay: int, pressure: float) -> int:
	var p: float = clampf(pressure, PRESSURE_MIN, PRESSURE_MAX)
	return int(round(float(maxi(0, base_delay)) * (1.0 - p)))


## Whether a replacement is due: there must be a deficit AND the vacancy clock
## must have reached the pressure-scaled delay.
static func is_replacement_due(p_deficit: int, ticks_since_vacancy: int, p_effective_delay: int) -> bool:
	return p_deficit > 0 and ticks_since_vacancy >= p_effective_delay


## How a due replacement is sourced: silently promote an ambient NPC when one is
## available, otherwise generate a new identity.
static func replacement_source(has_ambient_candidate: bool) -> String:
	return SOURCE_PROMOTE if has_ambient_candidate else SOURCE_GENERATE


func current_deficit() -> int:
	return deficit(desired_capacity, current_occupancy)


func is_understaffed() -> bool:
	return current_deficit() > 0


## Advance the vacancy clock: accumulate while understaffed, reset once full.
## Negative/zero ticks are ignored.
func advance(ticks: int) -> void:
	if is_understaffed():
		ticks_since_vacancy += maxi(0, ticks)
	else:
		ticks_since_vacancy = 0


## Record losing occupants (defeated/departed); occupancy floors at zero.
func vacate(count: int) -> void:
	current_occupancy = maxi(MIN_COUNT, current_occupancy - maxi(0, count))


## Place a refilled occupant; occupancy caps at the desired capacity and the
## vacancy clock resets when the anchor becomes full.
func fill() -> void:
	current_occupancy = mini(desired_capacity, current_occupancy + 1)
	if not is_understaffed():
		ticks_since_vacancy = 0


## The staffing decision for the current pressure and ambient availability.
## Returns {due, source}; source is "none" when no replacement is due.
func plan_replacement(pressure: float, has_ambient_candidate: bool) -> Dictionary:
	var due: bool = is_replacement_due(
		current_deficit(), ticks_since_vacancy, effective_delay(replacement_delay_ticks, pressure)
	)
	return {
		"due": due,
		"source": replacement_source(has_ambient_candidate) if due else SOURCE_NONE,
	}


## Parse + validate an untrusted wire Dictionary. Fails closed on version,
## structure, the role string, and count/delay bounds.
static func from_wire_dict(wire: Variant) -> Dictionary:
	if not (wire is Dictionary):
		return _fail(OUTCOME_MALFORMED, "wire is not a Dictionary")
	var data: Dictionary = wire
	if int(data.get("schema_version", -1)) != SCHEMA_VERSION:
		return _fail(OUTCOME_UNSUPPORTED_VERSION, "unsupported schema_version")
	var anchor_id: Variant = data.get("anchor_id")
	if not (anchor_id is String) or String(anchor_id).is_empty():
		return _fail(OUTCOME_MALFORMED, "anchor_id must be a non-empty string")
	var role: Variant = data.get("role")
	if not (role is String) or String(role).is_empty():
		return _fail(OUTCOME_MALFORMED, "role must be a non-empty string")
	var desired := _read_count(data, "desired_capacity")
	if desired["outcome"] != OUTCOME_OK:
		return desired
	var current := _read_count(data, "current_occupancy")
	if current["outcome"] != OUTCOME_OK:
		return current
	var delay := _read_delay(data, "replacement_delay_ticks")
	if delay["outcome"] != OUTCOME_OK:
		return delay
	var anchor := SpawnAnchor.new(
		String(anchor_id), String(role), desired["value"], current["value"], delay["value"]
	)
	return {"outcome": OUTCOME_OK, "detail": "", "anchor": anchor}


static func _read_count(data: Dictionary, key: String) -> Dictionary:
	return _read_int(data, key, MIN_COUNT, MAX_COUNT)


static func _read_delay(data: Dictionary, key: String) -> Dictionary:
	return _read_int(data, key, MIN_DELAY_TICKS, MAX_DELAY_TICKS)


static func _read_int(data: Dictionary, key: String, min_value: int, max_value: int) -> Dictionary:
	var raw: Variant = data.get(key)
	if not (raw is int or raw is float):
		return _fail(OUTCOME_MALFORMED, key + " is not numeric")
	if raw is float and float(raw) != floor(float(raw)):
		return _fail(OUTCOME_MALFORMED, key + " must be a whole number")
	var num: int = int(raw)
	if num < min_value or num > max_value:
		return _fail(OUTCOME_OUT_OF_BOUNDS, key + " out of bounds")
	return {"outcome": OUTCOME_OK, "detail": "", "value": num}


static func _fail(outcome: String, detail: String) -> Dictionary:
	return {"outcome": outcome, "detail": detail, "anchor": null}
