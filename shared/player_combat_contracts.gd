extends RefCounted
class_name PlayerCombatContracts
## Slice 094: the minimal, explicitly provisional flat HP pool a Player carries,
## so a hostile monster's landed attack has an authoritative consequence. Pure
## data and stateless transitions only — no authority, no network, no AI. The
## server owns the live PlayerVitals (see server/server_player_state.gd) and
## replicates the resulting HP to the owning client for display. See
## docs/slices/094-player-hp-monster-damage.md and
## .scratch/npcs/issues/04-provisional-shared-stat-block.md (resolved with its
## recommended default) and 05-hostile-npc-damages-player.md.
##
## PROVISIONAL: this flat pool is a placeholder for the future six-node
## vessel-derived health formula (CLAUDE.md Phase 12, 0% built). It is the
## shared "stat block" seed both Player and monster carry today; PLAYER_MAX_HP
## deliberately equals MonsterContracts.MAX_HP so a Player and the baseline
## monster start with the same durability until the vessel derives it from CON.

const SCHEMA_VERSION: int = 1

## Fixed full health a Player spawns with. A single constant, not a per-build
## table, since no vessel/derivation exists yet (Phase 12). Mirrors
## MonsterContracts.MAX_HP as the one shared default seed (ticket 04).
const PLAYER_MAX_HP: int = 30


## A Player's flat, server-owned health. Mirrors MonsterContracts.MonsterCombatState's
## shape (max_hp/current_hp + a 0-transition-reporting apply_damage) so both
## combatants clamp and report damage identically, but stays a distinct type so
## the Player concept never depends on the monster module.
class PlayerVitals:
	var max_hp: int
	var current_hp: int

	func _init(p_max_hp: int = PLAYER_MAX_HP) -> void:
		max_hp = p_max_hp
		current_hp = p_max_hp

	## Applies bounded damage, clamping current_hp at 0 (never negative).
	## Returns true only on the transition to 0 — the tick this hit defeats a
	## still-living Player — so the caller emits exactly one defeat outcome and
	## never a second for an already-defeated Player.
	func apply_damage(amount: int) -> bool:
		if amount <= 0:
			return false
		var was_alive: bool = current_hp > 0
		current_hp = maxi(0, current_hp - amount)
		return was_alive and current_hp == 0

	## Refills to full. Used by the provisional defeat->respawn placeholder
	## (ticket 05): a defeated Player is restored to full HP at a spawn anchor
	## until a real death/respawn/penalty system exists.
	func reset() -> void:
		current_hp = max_hp

	func is_defeated() -> bool:
		return current_hp <= 0
