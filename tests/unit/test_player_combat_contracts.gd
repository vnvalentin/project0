extends GutTest
## Unit tests for the shared Player HP seed (shared/player_combat_contracts.gd).
## Slice 125 retired the provisional PlayerVitals class; the Player's live pool
## is now the shared CombatHealth contract (covered by test_combat_health.gd).
## What remains meaningful here is the shared default SEED: it must match the
## monster's so both combatants start equally durable, and it must seed a full
## CombatHealth pool. See docs/slices/094-player-hp-monster-damage.md and
## docs/slices/125-phase14-player-health-integration.md.

const PlayerCombatContractsScript: Script = preload("res://shared/player_combat_contracts.gd")
const MonsterContractsScript: Script = preload("res://shared/monster_contracts.gd")
const CombatHealthScript: Script = preload("res://shared/combat_health.gd")


func test_player_max_hp_matches_monster_max_hp_as_shared_seed() -> void:
	# Ticket 04: one shared default seed applied identically to Player and monster.
	assert_eq(
		PlayerCombatContractsScript.PLAYER_MAX_HP,
		MonsterContractsScript.MAX_HP,
		"the Player and monster share the same provisional default HP seed"
	)


func test_seed_makes_a_full_combat_health_pool() -> void:
	# The seed feeds the shared CombatHealth pool the server owns (Slice 125).
	var seed: float = float(PlayerCombatContractsScript.PLAYER_MAX_HP)
	var health: Object = CombatHealthScript.new(seed, seed)
	assert_almost_eq(health.current_health, seed, 0.0001, "a freshly seeded Player pool starts full")
	assert_almost_eq(health.fraction(), 1.0, 0.0001, "a full pool reports a 1.0 health fraction")
	assert_false(health.is_now_defeated(), "a full-HP Player is not defeated")
