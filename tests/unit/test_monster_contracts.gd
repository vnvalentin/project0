extends GutTest
## Public-seam unit tests for the Basic Monsters slice 01 HP/damage/death model
## (shared/monster_contracts.gd) and the new COMBAT_EVENT_DEATH kind on
## shared/combat_contracts.gd. Pure — constructs the state directly and asserts
## its transitions. See docs/slices/020-monster-hp-damage-death.md.

const MonsterContractsScript: Script = preload("res://shared/monster_contracts.gd")
const CombatContractsScript: Script = preload("res://shared/combat_contracts.gd")


func test_default_monster_starts_at_full_hp() -> void:
	var monster: Object = MonsterContractsScript.default_monster("monster_0")
	assert_eq(monster.target_id, "monster_0", "the monster keeps its target id")
	assert_eq(monster.max_hp, MonsterContractsScript.MAX_HP, "max_hp is the fixed MAX_HP")
	assert_eq(monster.current_hp, MonsterContractsScript.MAX_HP, "a fresh monster starts at full HP")
	assert_false(monster.is_dead(), "a fresh monster is not dead")


func test_apply_damage_reduces_hp() -> void:
	var monster: Object = MonsterContractsScript.default_monster("monster_0")
	var died: bool = monster.apply_damage(MonsterContractsScript.DAMAGE_PER_HIT)
	assert_eq(monster.current_hp, MonsterContractsScript.MAX_HP - MonsterContractsScript.DAMAGE_PER_HIT, "one hit removes DAMAGE_PER_HIT")
	assert_false(died, "a non-lethal hit does not report a death")
	assert_false(monster.is_dead(), "the monster is still alive after one hit")


func test_damage_clamps_at_zero_and_never_goes_negative() -> void:
	var monster: Object = MonsterContractsScript.default_monster("monster_0")
	monster.apply_damage(MonsterContractsScript.MAX_HP + 100)
	assert_eq(monster.current_hp, 0, "over-damage clamps current_hp at 0, never negative")
	assert_true(monster.is_dead(), "a monster at 0 HP is dead")


func test_three_hits_defeat_the_baseline_monster() -> void:
	# MAX_HP 30 / DAMAGE_PER_HIT 10 = a deterministic 3 hits.
	var monster: Object = MonsterContractsScript.default_monster("monster_0")
	assert_false(monster.apply_damage(MonsterContractsScript.DAMAGE_PER_HIT), "hit 1 is not lethal")
	assert_false(monster.apply_damage(MonsterContractsScript.DAMAGE_PER_HIT), "hit 2 is not lethal")
	var lethal: bool = monster.apply_damage(MonsterContractsScript.DAMAGE_PER_HIT)
	assert_true(lethal, "the third hit reports the death transition")
	assert_true(monster.is_dead(), "the monster is dead after three hits")


func test_damage_after_death_does_not_report_a_second_death() -> void:
	var monster: Object = MonsterContractsScript.default_monster("monster_0")
	monster.apply_damage(MonsterContractsScript.MAX_HP)
	assert_true(monster.is_dead(), "the monster is dead")
	var again: bool = monster.apply_damage(MonsterContractsScript.DAMAGE_PER_HIT)
	assert_false(again, "hitting an already-dead monster does not report another death")


func test_combat_event_death_kind_exists_and_fits_the_shared_event() -> void:
	assert_eq(CombatContractsScript.COMBAT_EVENT_DEATH, "DEATH", "the DEATH combat-event kind exists")
	var event: Object = CombatContractsScript.CombatEvent.new(
		CombatContractsScript.COMBAT_EVENT_DEATH, 7, "monster_0", Vector3(1, 0, 2), 123
	)
	assert_eq(event.kind, CombatContractsScript.COMBAT_EVENT_DEATH, "a CombatEvent can carry the DEATH kind")
	assert_eq(event.target_id, "monster_0", "a death event names its target")
