extends GutTest
## Public-seam unit tests for Slice 094's provisional Player HP pool
## (shared/player_combat_contracts.gd). Pure and stateless — exercises the
## PlayerVitals damage/reset transitions directly, no SceneTree.
## See docs/slices/094-player-hp-monster-damage.md.

const PlayerCombatContractsScript: Script = preload("res://shared/player_combat_contracts.gd")
const MonsterContractsScript: Script = preload("res://shared/monster_contracts.gd")


func _vitals() -> Object:
	return PlayerCombatContractsScript.PlayerVitals.new()


func test_starts_at_full_hp() -> void:
	var v: Object = _vitals()
	assert_eq(v.current_hp, PlayerCombatContractsScript.PLAYER_MAX_HP, "a fresh Player starts at PLAYER_MAX_HP")
	assert_eq(v.max_hp, PlayerCombatContractsScript.PLAYER_MAX_HP, "max_hp is PLAYER_MAX_HP")
	assert_false(v.is_defeated(), "a full-HP Player is not defeated")


func test_player_max_hp_matches_monster_max_hp_as_shared_seed() -> void:
	# Ticket 04: one shared default seed applied identically to Player and monster.
	assert_eq(PlayerCombatContractsScript.PLAYER_MAX_HP, MonsterContractsScript.MAX_HP, "the Player and monster share the same provisional default HP seed")


func test_one_hit_removes_exactly_the_damage_amount() -> void:
	var v: Object = _vitals()
	var defeated: bool = v.apply_damage(MonsterContractsScript.DAMAGE_TO_PLAYER)
	assert_eq(v.current_hp, PlayerCombatContractsScript.PLAYER_MAX_HP - MonsterContractsScript.DAMAGE_TO_PLAYER, "one hit removes exactly DAMAGE_TO_PLAYER")
	assert_false(defeated, "a non-lethal hit does not report defeat")


func test_third_hit_defeats_and_reports_exactly_once() -> void:
	var v: Object = _vitals()
	assert_false(v.apply_damage(MonsterContractsScript.DAMAGE_TO_PLAYER), "first hit does not defeat")
	assert_false(v.apply_damage(MonsterContractsScript.DAMAGE_TO_PLAYER), "second hit does not defeat")
	assert_true(v.apply_damage(MonsterContractsScript.DAMAGE_TO_PLAYER), "the third hit defeats and reports the 0-transition")
	assert_true(v.is_defeated(), "the Player is defeated at 0 HP")


func test_damage_clamps_at_zero_and_reports_defeat_only_on_transition() -> void:
	var v: Object = _vitals()
	assert_true(v.apply_damage(1000), "an overkill hit defeats the Player")
	assert_eq(v.current_hp, 0, "HP clamps at 0, never negative")
	assert_false(v.apply_damage(1000), "a further hit on an already-0 Player never re-reports defeat")


func test_non_positive_damage_is_a_no_op() -> void:
	var v: Object = _vitals()
	assert_false(v.apply_damage(0), "zero damage is a no-op")
	assert_false(v.apply_damage(-5), "negative damage is a no-op")
	assert_eq(v.current_hp, PlayerCombatContractsScript.PLAYER_MAX_HP, "no-op damage leaves HP unchanged")


func test_reset_refills_to_full() -> void:
	var v: Object = _vitals()
	v.apply_damage(1000)
	v.reset()
	assert_eq(v.current_hp, v.max_hp, "reset refills to full HP")
	assert_false(v.is_defeated(), "a reset Player is no longer defeated")
