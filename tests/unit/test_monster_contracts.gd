extends GutTest
## Unit tests for shared/monster_contracts.gd's monster HP seed and the
## COMBAT_EVENT_DEATH kind on shared/combat_contracts.gd. Slice 126 retired the
## provisional MonsterCombatState; the monster's live pool is now the shared
## CombatHealth contract (damage/defeat covered by test_combat_health.gd). What
## remains meaningful here is that default_monster() seeds a full CombatHealth
## pool at MAX_HP, plus the death-event kind. See
## docs/slices/020-monster-hp-damage-death.md and
## docs/slices/126-phase14-monster-health-integration.md.

const MonsterContractsScript: Script = preload("res://shared/monster_contracts.gd")


func test_attack_state_snapshot_round_trips_versioned_windup_contract() -> void:
	var snapshot: Object = MonsterContractsScript.AttackStateSnapshot.new(
		MonsterContractsScript.PHASE_WINDUP, 42, 10, Vector3.LEFT
	)
	var parsed: Object = MonsterContractsScript.AttackStateSnapshot.from_wire(snapshot.to_wire())
	assert_not_null(parsed, "the current attack-state schema parses its wire form")
	assert_eq(parsed.schema_version, MonsterContractsScript.ATTACK_STATE_SCHEMA_VERSION)
	assert_eq(parsed.phase, MonsterContractsScript.PHASE_WINDUP)
	assert_eq(parsed.target_tick, 42)
	assert_eq(parsed.duration_ticks, 10)
	assert_eq(parsed.facing, Vector3.LEFT)


func test_attack_state_snapshot_rejects_unknown_schema() -> void:
	var parsed: Object = MonsterContractsScript.AttackStateSnapshot.from_wire({"schema_version": 999})
	assert_null(parsed, "an unknown attack-state schema fails closed")
const CombatContractsScript: Script = preload("res://shared/combat_contracts.gd")
const CombatHealthScript: Script = preload("res://shared/combat_health.gd")


func test_default_monster_seeds_a_full_combat_health_pool() -> void:
	var monster: Object = MonsterContractsScript.default_monster()
	assert_almost_eq(monster.max_health, float(MonsterContractsScript.MAX_HP), 0.0001, "max health is the fixed MAX_HP seed")
	assert_almost_eq(monster.current_health, float(MonsterContractsScript.MAX_HP), 0.0001, "a fresh monster starts at full HP")
	assert_almost_eq(monster.fraction(), 1.0, 0.0001, "a full pool reports a 1.0 health fraction")
	assert_false(monster.is_now_defeated(), "a fresh monster is not defeated")


func test_combat_event_death_kind_exists_and_fits_the_shared_event() -> void:
	assert_eq(CombatContractsScript.COMBAT_EVENT_DEATH, "DEATH", "the DEATH combat-event kind exists")
	var event: Object = CombatContractsScript.CombatEvent.new(
		CombatContractsScript.COMBAT_EVENT_DEATH, 7, "monster_0", Vector3(1, 0, 2), 123
	)
	assert_eq(event.kind, CombatContractsScript.COMBAT_EVENT_DEATH, "a CombatEvent can carry the DEATH kind")
	assert_eq(event.target_id, "monster_0", "a death event names its target")
