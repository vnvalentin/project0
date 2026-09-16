extends RefCounted
class_name MonsterContracts
## Basic Monsters slice 01: the minimal, explicitly provisional flat
## HP/damage/death model for a server-authoritative monster. Pure data and
## stateless transitions only — no authority, no network, no AI (the detect/
## chase/attack state machine and spawning are later Basic Monsters slices).
## See docs/slices/020-monster-hp-damage-death.md and
## .scratch/basic-monsters/issues/01-hp-damage-death-model.md (resolved).
##
## PROVISIONAL: this flat pool is a placeholder for the future six-node
## vessel-derived health formula (CLAUDE.md Phase 12, 0% built). When that
## exists, effective HP derives from CON and tuning; the shape here is a
## bounded stand-in so monsters can be built and fought first.
##
## Death reuses CombatContracts.CombatEvent with its new COMBAT_EVENT_DEATH
## kind (see shared/combat_contracts.gd) rather than a separate event class —
## a death still has an attacker, target, position, and tick.

const CombatContractsScript: Script = preload("res://shared/combat_contracts.gd")

## Fixed full health of the one baseline monster. A single constant, not a
## per-archetype table, since only one monster archetype exists in this map's
## scope (per ticket 01).
const MAX_HP: int = 30

## Fixed damage one accepted melee HIT deals to a monster. 30 / 10 = a
## deterministic 3 hits to defeat the baseline monster. Kept here (not on
## CombatContracts.MeleeWeaponArchetype, which has no damage field by Slice
## 012's explicit non-goal) so this provisional concept stays contained.
const DAMAGE_PER_HIT: int = 10

## Slice 094: fixed damage the monster's own landed (telegraph-fair) attack
## deals to a Player. Mirrors DAMAGE_PER_HIT (a provisional flat constant), so
## 30 / 10 = a deterministic 3 landed monster hits to defeat a full-HP Player
## (PlayerCombatContracts.PLAYER_MAX_HP). The monster owns how much its attack
## hurts, next to how much a player hit hurts it. See
## docs/slices/094-player-hp-monster-damage.md and
## .scratch/npcs/issues/05-hostile-npc-damages-player.md.
const DAMAGE_TO_PLAYER: int = 10

## Authoritative attack lifecycle timing for the baseline monster, in server
## ticks (physics frames). WINDUP_TICKS is intentionally >= the player sword's
## windup (CombatContracts.generic_sword_archetype().windup_ticks == 6) so the
## monster's telegraph is at least as readable as the player's own attack, per
## CLAUDE.md's Combat Reading rules. This is a binding fairness invariant, not
## a coincidence — see test_server_monster_state.gd's regression assertion.
const WINDUP_TICKS: int = 10
const ATTACK_ACTIVE_TICKS: int = 4
const RECOVERY_TICKS: int = 10

## Detection radius (yards) checked each tick while IDLE, and horizontal chase
## speed (yards/second). 1 world unit = 1 yard (see shared/world_scale.gd,
## ADR 0003). Independent fixed constants (not a multiplier of player speed) per
## ticket 02 — coupling them is speculative with one monster archetype and one
## player speed today.
const DETECTION_RADIUS_YARDS: float = 8.0
const CHASE_SPEED_YARDS_PER_SEC: float = 3.0

## The monster's melee reach/arc (yards), applied through the shared
## CombatContracts.is_within_reach_and_arc() hit test rather than a second
## implementation.
const MONSTER_REACH_YARDS: float = 2.0
const MONSTER_ARC_DEGREES: float = 60.0

## Authoritative attack-phase state names (server-owned; driven by
## server/server_monster_state.gd). No separate DETECT state — detection is a
## radius check each tick while IDLE.
const PHASE_IDLE: String = "IDLE"
const PHASE_CHASE: String = "CHASE"
const PHASE_WINDUP: String = "WINDUP"
const PHASE_ATTACK: String = "ATTACK"
const PHASE_RECOVERY: String = "RECOVERY"
const PHASE_DEAD: String = "DEAD"


## A monster's flat, server-owned health. `target_id` mirrors the id a
## CombatEvent's target_id resolves against (as client/target_dummy.gd already
## uses), so hit resolution keys the same way for monsters as for the dummy.
class MonsterCombatState:
	var target_id: String
	var max_hp: int
	var current_hp: int

	func _init(p_target_id: String, p_max_hp: int) -> void:
		target_id = p_target_id
		max_hp = p_max_hp
		current_hp = p_max_hp

	## Applies bounded damage, clamping current_hp at 0 (never negative).
	## Returns true only on the transition to 0 — the tick this hit defeats a
	## still-living monster — so the caller emits exactly one death event and
	## never a second for an already-dead monster.
	func apply_damage(amount: int) -> bool:
		var was_alive: bool = current_hp > 0
		current_hp = maxi(0, current_hp - amount)
		return was_alive and current_hp == 0

	func is_dead() -> bool:
		return current_hp <= 0


## Factory for a fresh, full-HP baseline monster at MAX_HP.
static func default_monster(target_id: String) -> Object:
	return MonsterCombatState.new(target_id, MAX_HP)


## The bounded weapon archetype used ONLY for the monster's reach/arc hit test
## via CombatContracts.is_within_reach_and_arc(). Its timing/factor fields
## mirror the constants above but are unused by that pure geometric test, which
## reads only reach_yards and arc_degrees.
static func monster_attack_archetype() -> Object:
	return CombatContractsScript.MeleeWeaponArchetype.new(
		"MONSTER_CLAW",
		WINDUP_TICKS,
		ATTACK_ACTIVE_TICKS,
		RECOVERY_TICKS,
		MONSTER_REACH_YARDS,
		MONSTER_ARC_DEGREES,
		1.0,
		1.0,
		1
	)
