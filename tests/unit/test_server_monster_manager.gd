extends GutTest
## Public-seam tests for the Basic Monsters slice 03 monster manager
## (server/server_monster_manager.gd). Pure/deterministic — drives advance_all
## directly and watches the death/respawn telemetry, no SceneTree. Strongly
## verifies the caveat that monsters never spawn or respawn inside the town.
## See docs/slices/022-monster-spawning-and-respawn.md.

const ServerMonsterManagerScript: Script = preload("res://server/server_monster_manager.gd")
const StartingTownHubFixtureScript: Script = preload("res://server/starting_town_hub_fixture.gd")
const MonsterContractsScript: Script = preload("res://shared/monster_contracts.gd")
const SectorBlueprintSchemaScript: Script = preload("res://shared/sector_blueprint_schema.gd")

var _excl: float = ServerMonsterManagerScript.TOWN_EXCLUSION_HALF_EXTENT


func _hub_spawn_points() -> Array:
	return StartingTownHubFixtureScript.blueprint()["spawn_points"]


func _outside_town(pos: Vector3) -> bool:
	return absf(pos.x) >= _excl - 0.001 or absf(pos.z) >= _excl - 0.001


func test_spawns_one_monster_per_spawn_point() -> void:
	var manager: Object = ServerMonsterManagerScript.new(_hub_spawn_points())
	assert_eq(manager.monster_count(), 4, "one monster per hub spawn point")
	assert_eq(manager.living_count(), 4, "all monsters start alive")


func test_initial_monster_positions_are_outside_town() -> void:
	var manager: Object = ServerMonsterManagerScript.new(_hub_spawn_points())
	for i in manager.monster_count():
		var monster: Object = manager.monster_at(i)
		assert_true(_outside_town(monster.position), "initial monster %d at %s is outside the town" % [i, monster.position])


func test_bounded_by_max_spawn_point_count() -> void:
	var too_many: Array = []
	for i in SectorBlueprintSchemaScript.MAX_SPAWN_POINT_COUNT + 5:
		too_many.append({"spawn_id": "s_%d" % i, "x": 10, "y": i})
	var manager: Object = ServerMonsterManagerScript.new(too_many)
	assert_eq(manager.monster_count(), SectorBlueprintSchemaScript.MAX_SPAWN_POINT_COUNT, "the monster count is capped at MAX_SPAWN_POINT_COUNT")


func test_monsters_idle_and_survive_with_no_players() -> void:
	var manager: Object = ServerMonsterManagerScript.new(_hub_spawn_points())
	for tick in 5:
		manager.advance_all([], 1.0, tick)
	assert_eq(manager.living_count(), 4, "monsters idle and stay alive when no player is connected")


func test_monster_chases_the_nearest_player() -> void:
	# One spawn just outside the east wall; a player one meter away is detected.
	var manager: Object = ServerMonsterManagerScript.new([{"spawn_id": "s0", "x": 10, "y": 0}])
	manager.advance_all([Vector3(9, 1, 0)], 1.0, 0)
	assert_eq(manager.monster_at(0).phase, MonsterContractsScript.PHASE_CHASE, "a monster chases a nearby player")


func test_defeated_monster_dies_then_respawns_after_cooldown() -> void:
	var manager: Object = ServerMonsterManagerScript.new([{"spawn_id": "s0", "x": 10, "y": 0}], 1, 3)
	manager.monster_at(0).receive_damage(MonsterContractsScript.MAX_HP, 1, 0)
	watch_signals(manager)

	manager.advance_all([], 1.0, 1)  # detects death
	assert_signal_emitted(manager, "monster_died", "a defeated monster emits monster_died")
	assert_eq(manager.living_count(), 0, "the monster is gone while respawning")
	assert_null(manager.monster_at(0), "the slot is empty during the respawn cooldown")

	manager.advance_all([], 1.0, 2)  # cooldown 3 -> 2
	manager.advance_all([], 1.0, 3)  # 2 -> 1
	assert_eq(manager.living_count(), 0, "still respawning before the cooldown elapses")
	manager.advance_all([], 1.0, 4)  # 1 -> 0 -> respawn
	assert_signal_emitted(manager, "monster_respawned", "the monster respawns after the cooldown")
	assert_eq(manager.living_count(), 1, "the respawned monster is alive again")


func test_living_targets_excludes_dead_monsters() -> void:
	var manager: Object = ServerMonsterManagerScript.new([{"spawn_id": "s0", "x": 10, "y": 0}], 1, 999)
	var targets: Dictionary = manager.living_targets()
	assert_true(targets.has("s0"), "a living monster is targetable")
	assert_eq(targets["s0"], manager.monster_at(0), "living_targets exposes the same monster instance")

	manager.monster_at(0).receive_damage(MonsterContractsScript.MAX_HP, 1, 0)
	manager.advance_all([], 1.0, 1)  # detects death, clears the slot
	assert_false(manager.living_targets().has("s0"), "a dead/respawning monster is never targetable")


func test_receive_player_hit_applies_damage_per_hit_and_reports_no_death_until_third_hit() -> void:
	var manager: Object = ServerMonsterManagerScript.new([{"spawn_id": "s0", "x": 10, "y": 0}])
	assert_false(manager.receive_player_hit("s0", 1, 0), "the first hit does not defeat a full-HP monster")
	assert_eq(manager.monster_at(0).current_hp(), MonsterContractsScript.MAX_HP - MonsterContractsScript.DAMAGE_PER_HIT, "the first hit applies exactly DAMAGE_PER_HIT")

	assert_false(manager.receive_player_hit("s0", 1, 1), "the second hit still does not defeat the monster")
	assert_eq(manager.monster_at(0).current_hp(), MonsterContractsScript.MAX_HP - 2 * MonsterContractsScript.DAMAGE_PER_HIT, "the second hit applies another DAMAGE_PER_HIT")

	assert_true(manager.receive_player_hit("s0", 1, 2), "the third hit defeats the monster and reports exactly one death")


func test_receive_player_hit_on_dead_monster_is_a_no_op() -> void:
	var manager: Object = ServerMonsterManagerScript.new([{"spawn_id": "s0", "x": 10, "y": 0}], 1, 999)
	manager.monster_at(0).receive_damage(MonsterContractsScript.MAX_HP, 1, 0)
	assert_true(manager.monster_at(0).is_dead(), "the monster is dead before the next hit")

	assert_false(manager.receive_player_hit("s0", 1, 1), "a hit on an already-dead monster is a no-op, not a second death")


func test_receive_player_hit_on_unknown_or_respawning_target_is_a_no_op() -> void:
	var manager: Object = ServerMonsterManagerScript.new([{"spawn_id": "s0", "x": 10, "y": 0}], 1, 999)
	assert_false(manager.receive_player_hit("no_such_target", 1, 0), "an unknown target_id is a no-op")

	manager.monster_at(0).receive_damage(MonsterContractsScript.MAX_HP, 1, 0)
	manager.advance_all([], 1.0, 1)  # detects death, clears the slot (now respawning)
	assert_false(manager.receive_player_hit("s0", 1, 2), "a hit on a respawning (slotted-null) target is a no-op")


func test_every_respawn_stays_outside_town() -> void:
	# The user caveat: monsters must never (re)appear inside the town. Drive many
	# kill/respawn cycles across all four hub spawn points and assert every
	# respawn position is outside the town exclusion box.
	var manager: Object = ServerMonsterManagerScript.new(_hub_spawn_points(), 12345, 1)
	var respawns: Array = []
	manager.monster_respawned.connect(func(_spawn_id: String, position: Vector3, _tick: int) -> void:
		respawns.append(position))

	var tick: int = 0
	for cycle in 30:
		for i in manager.monster_count():
			var monster: Object = manager.monster_at(i)
			if monster != null:
				monster.receive_damage(MonsterContractsScript.MAX_HP, 1, tick)
		# Two advances: one to detect death + start the 1-tick cooldown, one to respawn.
		manager.advance_all([], 1.0, tick)
		tick += 1
		manager.advance_all([], 1.0, tick)
		tick += 1

	assert_gt(respawns.size(), 0, "respawns occurred")
	for position: Vector3 in respawns:
		assert_true(_outside_town(position), "respawn at %s is outside the town" % position)


func test_town_exclusion_half_extent_matches_fixture_constant() -> void:
	var extent: float = ServerMonsterManagerScript.town_exclusion_half_extent(StartingTownHubFixtureScript.blueprint())
	assert_eq(extent, 32.0, "the shipped fixture (radius 30) derives to exactly 32.0, matching prior hard-coded behavior")


func test_town_exclusion_half_extent_scales_with_small_blueprint() -> void:
	var blueprint: Dictionary = {"tiles": [{"x": 5, "y": 0}, {"x": -3, "y": 4}, {"x": 2, "y": -5}]}
	var extent: float = ServerMonsterManagerScript.town_exclusion_half_extent(blueprint)
	assert_eq(extent, 5.0 + ServerMonsterManagerScript.TOWN_EXCLUSION_MARGIN_YARDS, "extent is max(|x|,|y|) over tiles plus the margin")


func test_town_exclusion_half_extent_scales_with_larger_blueprint() -> void:
	var blueprint: Dictionary = {"tiles": [{"x": 40, "y": 0}, {"x": 0, "y": -12}]}
	var extent: float = ServerMonsterManagerScript.town_exclusion_half_extent(blueprint)
	assert_eq(extent, 40.0 + ServerMonsterManagerScript.TOWN_EXCLUSION_MARGIN_YARDS, "a larger blueprint derives a proportionally larger extent")


func test_town_exclusion_half_extent_falls_back_when_no_tiles() -> void:
	var extent: float = ServerMonsterManagerScript.town_exclusion_half_extent({"tiles": []})
	assert_eq(extent, ServerMonsterManagerScript.TOWN_EXCLUSION_HALF_EXTENT, "an empty-tiles blueprint falls back to the fixed constant")

	var extent_missing_key: float = ServerMonsterManagerScript.town_exclusion_half_extent({})
	assert_eq(extent_missing_key, ServerMonsterManagerScript.TOWN_EXCLUSION_HALF_EXTENT, "a blueprint missing the tiles key also falls back")


func test_respawn_stays_outside_derived_extent_for_a_small_blueprint() -> void:
	# A small hand-built blueprint whose derived extent (5 + 2 = 7) is much
	# smaller than the real fixture's 32 — proves respawn exclusion actually
	# uses the derived per-instance extent, not the fixed fallback constant.
	var small_blueprint: Dictionary = {"tiles": [{"x": 5, "y": 0}, {"x": 0, "y": 5}]}
	var derived_extent: float = ServerMonsterManagerScript.town_exclusion_half_extent(small_blueprint)
	assert_eq(derived_extent, 7.0, "sanity: derived extent for this small blueprint is 7.0")

	var manager: Object = ServerMonsterManagerScript.new([{"spawn_id": "s0", "x": 10, "y": 0}], 777, 1, derived_extent)
	var respawns: Array = []
	manager.monster_respawned.connect(func(_spawn_id: String, position: Vector3, _tick: int) -> void:
		respawns.append(position))

	var tick: int = 0
	for cycle in 20:
		var monster: Object = manager.monster_at(0)
		if monster != null:
			monster.receive_damage(MonsterContractsScript.MAX_HP, 1, tick)
		manager.advance_all([], 1.0, tick)
		tick += 1
		manager.advance_all([], 1.0, tick)
		tick += 1

	assert_gt(respawns.size(), 0, "respawns occurred")
	for position: Vector3 in respawns:
		assert_true(absf(position.x) >= derived_extent - 0.001 or absf(position.z) >= derived_extent - 0.001, "respawn at %s stays outside the small derived exclusion box" % position)
