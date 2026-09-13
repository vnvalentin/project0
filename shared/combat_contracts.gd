extends RefCounted
class_name CombatContracts
## Versioned melee-combat value contracts shared by server and client for
## Slice 012's first authoritative melee strike (see
## docs/slices/012-authoritative-melee-strike.md and
## .scratch/melee-combat/issues/01-05). Pure data/constants and stateless
## helpers only — no authority, no network calls, no mutable singleton state.
## Matches CLAUDE.md's Shared Contracts rule: this module owns the shape both
## processes must interpret identically; it grants neither side authority.
##
## Scope: `ActionIntent`, `ActionResolution`, `CombatEvent`, and the single
## `MeleeWeaponArchetype` baseline ("Generic Sword"). No damage/HP fields, no
## inventory/equipment fields, and no progression fields exist here — those
## remain explicit non-goals for this slice.

const SCHEMA_VERSION: int = 1

## The only action kind this slice defines. Kept as a String constant (like
## the rest of this repository's outcome/kind enums, e.g.
## SectorBlueprintSchema's OUTCOME_* constants) so it serializes directly for
## RPC/telemetry without a separate lookup step.
const ACTION_KIND_MELEE_STRIKE: String = "MELEE_STRIKE"

## `ActionResolution.result` values.
const RESULT_ACCEPTED: String = "ACCEPTED"
const RESULT_REJECTED: String = "REJECTED"

## Bounded rejection reasons per
## .scratch/melee-combat/issues/02-set-melee-action-authority-and-lifetime.md.
## Empty string ("") is the non-rejected default, never a rejection reason.
const REJECTED_BUSY: String = "REJECTED_BUSY"
const REJECTED_COOLDOWN: String = "REJECTED_COOLDOWN"
const REJECTED_STALE: String = "REJECTED_STALE"
const REJECTED_INVALID_STATE: String = "REJECTED_INVALID_STATE"

## Authoritative attack lifecycle phases (see server/server_player_state.gd).
const PHASE_IDLE: String = "IDLE"
const PHASE_WINDUP: String = "WINDUP"
const PHASE_ACTIVE: String = "ACTIVE"
const PHASE_RECOVERY: String = "RECOVERY"

## `CombatEvent.kind` values. HIT confirms a landed strike. DEATH (added by
## the Basic Monsters slice) marks a target reduced to 0 HP; it reuses the
## same CombatEvent shape (attacker/target/position/tick) rather than a
## separate event class. See shared/monster_contracts.gd.
const COMBAT_EVENT_HIT: String = "HIT"
const COMBAT_EVENT_DEATH: String = "DEATH"


## A bounded client-submitted request to perform an action. Never contains
## trusted outcome, damage, timing, or cooldown fields — see CLAUDE.md's
## `ActionIntent` contract. Immutable once constructed to match the read-only
## intent shape both sides parse identically.
class ActionIntent:
	var schema_version: int
	var player_id: int
	var sequence: int
	var client_tick: int
	var action_kind: String
	var aim_direction: Vector3

	func _init(p_player_id: int, p_sequence: int, p_client_tick: int, p_action_kind: String, p_aim_direction: Vector3) -> void:
		schema_version = SCHEMA_VERSION
		player_id = p_player_id
		sequence = p_sequence
		client_tick = p_client_tick
		action_kind = p_action_kind
		aim_direction = p_aim_direction


## The server's authoritative response to one `ActionIntent`. `result` is
## either RESULT_ACCEPTED or RESULT_REJECTED; `rejection_reason` is only set
## (non-empty) when `result == RESULT_REJECTED`. Never carries a
## client-authored outcome — every field here is server-computed.
class ActionResolution:
	var player_id: int
	var sequence: int
	var result: String
	var rejection_reason: String
	var server_tick: int

	func _init(p_player_id: int, p_sequence: int, p_result: String, p_rejection_reason: String, p_server_tick: int) -> void:
		player_id = p_player_id
		sequence = p_sequence
		result = p_result
		rejection_reason = p_rejection_reason
		server_tick = p_server_tick


## A discrete, replicated authoritative combat outcome (e.g. a confirmed
## hit). Distinct from the continuous phase/state snapshot already carried by
## ServerPlayerState's position replication — this is a one-shot event, not a
## per-tick value. See
## .scratch/melee-combat/issues/04-choose-first-target-and-hit-rule.md.
class CombatEvent:
	var kind: String
	var attacker_peer_id: int
	var target_id: String
	var impact_position: Vector3
	var server_tick: int

	func _init(p_kind: String, p_attacker_peer_id: int, p_target_id: String, p_impact_position: Vector3, p_server_tick: int) -> void:
		kind = p_kind
		attacker_peer_id = p_attacker_peer_id
		target_id = p_target_id
		impact_position = p_impact_position
		server_tick = p_server_tick


## Immutable typed melee weapon data. Per
## .scratch/melee-combat/issues/03-model-melee-weapon-archetypes.md, this
## slice defines exactly one archetype ("Generic Sword" / BASIC_SWORD) as a
## bounded data-driven object rather than a per-weapon subclass, so future
## archetypes extend by adding another instance, never a new class.
class MeleeWeaponArchetype:
	var archetype_id: String
	var windup_ticks: int
	var active_ticks: int
	var recovery_ticks: int
	var reach_yards: float
	var arc_degrees: float
	var windup_speed_factor: float
	var recovery_speed_factor: float
	var max_targets: int

	func _init(
		p_archetype_id: String,
		p_windup_ticks: int,
		p_active_ticks: int,
		p_recovery_ticks: int,
		p_reach_yards: float,
		p_arc_degrees: float,
		p_windup_speed_factor: float,
		p_recovery_speed_factor: float,
		p_max_targets: int
	) -> void:
		archetype_id = p_archetype_id
		windup_ticks = p_windup_ticks
		active_ticks = p_active_ticks
		recovery_ticks = p_recovery_ticks
		reach_yards = p_reach_yards
		arc_degrees = p_arc_degrees
		windup_speed_factor = p_windup_speed_factor
		recovery_speed_factor = p_recovery_speed_factor
		max_targets = p_max_targets


## The baseline Generic Sword archetype every Player spawns with in this
## slice. Values are the tuning-shaped constants agreed in
## .scratch/melee-combat/issues/03-model-melee-weapon-archetypes.md. No
## equipping/switching exists yet, so this is the only archetype instance.
static func generic_sword_archetype() -> MeleeWeaponArchetype:
	return MeleeWeaponArchetype.new(
		"BASIC_SWORD",
		6,
		4,
		10,
		2.0,
		60.0,
		0.5,
		0.8,
		1
	)


## Public seam: deterministic vector reach/arc hit test, pure and
## side-effect-free so it is directly unit-testable. Distance uses
## reach_yards exactly (<=); arc uses the half-angle cosine threshold so a
## target exactly on the boundary (attacker_forward re-normalized) is
## deterministic under floating point per
## .scratch/melee-combat/issues/04-choose-first-target-and-hit-rule.md.
## attacker_forward is expected to already be a unit vector on the horizontal
## plane; a zero-length forward vector can never hit (no defined direction).
static func is_within_reach_and_arc(
	attacker_position: Vector3,
	attacker_forward: Vector3,
	target_position: Vector3,
	archetype: MeleeWeaponArchetype
) -> bool:
	if attacker_forward.length_squared() == 0.0:
		return false

	var to_target: Vector3 = target_position - attacker_position
	var distance: float = to_target.length()
	if distance > archetype.reach_yards:
		return false
	if distance == 0.0:
		return true

	var forward: Vector3 = attacker_forward.normalized()
	var direction_to_target: Vector3 = to_target / distance
	var cos_angle: float = forward.dot(direction_to_target)
	var cos_half_arc: float = cos(deg_to_rad(archetype.arc_degrees / 2.0))
	# A small epsilon absorbs floating-point rounding from the trig/normalize
	# chain above so a target exactly on the authored arc boundary (e.g. a
	# vector deliberately rotated by arc_degrees / 2.0) is not spuriously
	# rejected by a sub-degree rounding difference.
	const ARC_EPSILON: float = 1e-6
	return cos_angle >= cos_half_arc - ARC_EPSILON


## Public seam: the authoritative locomotion speed factor for a given attack
## phase, per
## .scratch/melee-combat/issues/02-set-melee-action-authority-and-lifetime.md.
## IDLE and ACTIVE both move at full speed in this slice — only windup and
## recovery are throttled — matching the Generic Sword's resolved parameters.
static func locomotion_speed_factor_for_phase(phase: String, archetype: MeleeWeaponArchetype) -> float:
	match phase:
		PHASE_WINDUP:
			return archetype.windup_speed_factor
		PHASE_RECOVERY:
			return archetype.recovery_speed_factor
		_:
			return 1.0
