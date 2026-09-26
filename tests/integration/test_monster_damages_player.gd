extends GutTest
## Slice 094 integration: the monster manager's landed-attack player_hit routes
## authoritative damage to a ServerPlayerState, and the telegraph dodge window
## is preserved end-to-end. Wires ServerMonsterManager.player_hit ->
## ServerPlayerState.receive_monster_damage exactly as server_main does, without
## a real server/RPC. See docs/slices/094-player-hp-monster-damage.md.

const ServerMonsterManagerScript: Script = preload("res://server/server_monster_manager.gd")
const ServerPlayerStateScript: Script = preload("res://server/server_player_state.gd")
const MonsterContractsScript: Script = preload("res://shared/monster_contracts.gd")
const PlayerCombatContractsScript: Script = preload("res://shared/player_combat_contracts.gd")

const VICTIM_PEER: int = 5


func _wire(manager: Object, state: Object) -> void:
	manager.player_hit.connect(func(victim_peer_id: int, _spawn_id: String, tick: int) -> void:
		if victim_peer_id == state.owning_peer_id:
			state.receive_monster_damage(MonsterContractsScript.DAMAGE_TO_PLAYER, tick))


func test_landed_monster_attack_damages_the_player() -> void:
	var manager: Object = ServerMonsterManagerScript.new([{"spawn_id": "s0", "x": 10, "y": 0}], 1, 999)
	var state: Object = ServerPlayerStateScript.new()
	autofree(state)
	state.start_for_peer(VICTIM_PEER, Vector3(9, 1, 0))  # within the monster's 2.0 reach
	_wire(manager, state)

	for tick in 20:
		manager.advance_all([state.position], 1.0, tick, [VICTIM_PEER])
		if state.current_hp() < PlayerCombatContractsScript.PLAYER_MAX_HP:
			break
	assert_eq(state.current_hp(), PlayerCombatContractsScript.PLAYER_MAX_HP - MonsterContractsScript.DAMAGE_TO_PLAYER, "one landed monster attack removes exactly DAMAGE_TO_PLAYER from the Player")


func test_player_dodging_during_telegraph_takes_no_damage() -> void:
	var manager: Object = ServerMonsterManagerScript.new([{"spawn_id": "s0", "x": 10, "y": 0}], 1, 999)
	var state: Object = ServerPlayerStateScript.new()
	autofree(state)
	state.start_for_peer(VICTIM_PEER, Vector3(9, 1, 0))
	_wire(manager, state)

	# Enter the monster's WINDUP while in reach, then dodge out for the rest of
	# the telegraph so the committed swing whiffs (and the monster, now far from
	# the player, never re-detects it).
	manager.advance_all([Vector3(9, 1, 0)], 1.0, 0, [VICTIM_PEER])  # detect -> CHASE
	manager.advance_all([Vector3(9, 1, 0)], 1.0, 1, [VICTIM_PEER])  # -> WINDUP (facing locked)
	state.position = Vector3(100, 1, 0)
	for tick in range(2, 30):
		manager.advance_all([state.position], 1.0, tick, [VICTIM_PEER])
	assert_eq(state.current_hp(), PlayerCombatContractsScript.PLAYER_MAX_HP, "a Player who dodges out during the telegraph takes no damage")


func test_player_leaving_locked_telegraph_arc_within_reach_takes_no_damage() -> void:
	var manager: Object = ServerMonsterManagerScript.new([{"spawn_id": "s0", "x": 10, "y": 0}], 1, 999)
	var state: Object = ServerPlayerStateScript.new()
	autofree(state)
	state.start_for_peer(VICTIM_PEER, Vector3(9, 1, 0))
	_wire(manager, state)
	var monster: Object = manager.monster_at(0)
	watch_signals(monster)
	watch_signals(manager)
	assert_lt(state.position.distance_to(monster.position), MonsterContractsScript.MONSTER_REACH_YARDS, "initial position is within reach")
	manager.advance_all([state.position], 1.0, 0, [VICTIM_PEER])
	assert_eq(monster.phase, MonsterContractsScript.PHASE_CHASE)
	manager.advance_all([state.position], 1.0, 1, [VICTIM_PEER])
	assert_eq(monster.phase, MonsterContractsScript.PHASE_WINDUP)
	assert_eq(monster.facing, Vector3.LEFT, "telegraph starts facing the initial player position")
	assert_signal_emitted_with_parameters(monster, "phase_changed", ["s0", MonsterContractsScript.PHASE_CHASE, MonsterContractsScript.PHASE_WINDUP, 1])
	var locked_facing: Vector3 = monster.facing
	state.position = Vector3(10, 1, 1)
	var sidestep: Vector3 = state.position - monster.position
	assert_eq(sidestep.y, 0.0, "fixture is on the same horizontal plane")
	assert_lt(sidestep.length(), MonsterContractsScript.MONSTER_REACH_YARDS, "sidestep remains within reach, so distance cannot explain the miss")
	assert_gt(rad_to_deg(locked_facing.angle_to(sidestep)), MonsterContractsScript.MONSTER_ARC_DEGREES / 2.0, "sidestep is outside the initial locked arc")
	var resolution_tick: int = 1 + MonsterContractsScript.WINDUP_TICKS
	for tick in range(2, resolution_tick):
		manager.advance_all([state.position], 1.0, tick, [VICTIM_PEER])
	assert_eq(monster.phase, MonsterContractsScript.PHASE_WINDUP, "windup lasts until its resolution tick")
	assert_signal_not_emitted(monster, "attack_resolved", "no early resolution")
	assert_signal_not_emitted(manager, "player_hit", "no damage before resolution")
	assert_eq(state.current_hp(), PlayerCombatContractsScript.PLAYER_MAX_HP)
	manager.advance_all([state.position], 1.0, resolution_tick, [VICTIM_PEER])
	assert_eq(monster.phase, MonsterContractsScript.PHASE_ATTACK)
	assert_signal_emitted_with_parameters(monster, "phase_changed", ["s0", MonsterContractsScript.PHASE_WINDUP, MonsterContractsScript.PHASE_ATTACK, resolution_tick])
	assert_signal_emit_count(monster, "attack_resolved", 1)
	assert_signal_emitted_with_parameters(monster, "attack_resolved", ["s0", false, resolution_tick])
	assert_signal_not_emitted(manager, "player_hit", "an in-reach sidestep outside the locked arc must not hit")
	assert_eq(state.current_hp(), PlayerCombatContractsScript.PLAYER_MAX_HP, "the locked-arc miss preserves authoritative HP")
	var recovery_tick: int = resolution_tick + MonsterContractsScript.ATTACK_ACTIVE_TICKS
	for tick in range(resolution_tick + 1, recovery_tick + 1):
		manager.advance_all([state.position], 1.0, tick, [VICTIM_PEER])
	assert_eq(monster.phase, MonsterContractsScript.PHASE_RECOVERY)
	for tick in range(recovery_tick + 1, recovery_tick + MonsterContractsScript.RECOVERY_TICKS + 1):
		manager.advance_all([state.position], 1.0, tick, [VICTIM_PEER])
	assert_eq(monster.phase, MonsterContractsScript.PHASE_IDLE)
	assert_signal_emit_count(monster, "attack_resolved", 1, "active and recovery ticks do not resolve again")
	assert_signal_not_emitted(manager, "player_hit", "the missed swing never becomes a delayed hit")
	assert_eq(state.current_hp(), PlayerCombatContractsScript.PLAYER_MAX_HP, "HP remains unchanged through recovery")


func test_player_staying_in_locked_telegraph_arc_takes_exactly_one_hit() -> void:
	var manager: Object = ServerMonsterManagerScript.new([{"spawn_id": "s0", "x": 10, "y": 0}], 1, 999)
	var state: Object = ServerPlayerStateScript.new()
	autofree(state)
	state.start_for_peer(VICTIM_PEER, Vector3(9, 1, 0))
	_wire(manager, state)
	var monster: Object = manager.monster_at(0)
	watch_signals(monster)
	watch_signals(manager)
	manager.advance_all([state.position], 1.0, 0, [VICTIM_PEER])
	assert_eq(monster.phase, MonsterContractsScript.PHASE_CHASE)
	manager.advance_all([state.position], 1.0, 1, [VICTIM_PEER])
	assert_eq(monster.phase, MonsterContractsScript.PHASE_WINDUP)
	assert_eq(monster.facing, Vector3.LEFT, "telegraph starts facing the player")
	var to_player: Vector3 = state.position - monster.position
	assert_eq(to_player.y, 0.0, "fixture is on the same horizontal plane")
	assert_lt(to_player.length(), MonsterContractsScript.MONSTER_REACH_YARDS, "control remains within reach")
	assert_lt(rad_to_deg(monster.facing.angle_to(to_player)), MonsterContractsScript.MONSTER_ARC_DEGREES / 2.0, "control remains in the locked arc")
	var resolution_tick: int = 1 + MonsterContractsScript.WINDUP_TICKS
	for tick in range(2, resolution_tick):
		manager.advance_all([state.position], 1.0, tick, [VICTIM_PEER])
	assert_eq(monster.phase, MonsterContractsScript.PHASE_WINDUP)
	assert_signal_not_emitted(monster, "attack_resolved", "no early resolution")
	assert_signal_not_emitted(manager, "player_hit", "no early hit")
	assert_eq(state.current_hp(), PlayerCombatContractsScript.PLAYER_MAX_HP)
	manager.advance_all([state.position], 1.0, resolution_tick, [VICTIM_PEER])
	assert_eq(monster.phase, MonsterContractsScript.PHASE_ATTACK)
	assert_signal_emitted_with_parameters(monster, "phase_changed", ["s0", MonsterContractsScript.PHASE_WINDUP, MonsterContractsScript.PHASE_ATTACK, resolution_tick])
	assert_signal_emit_count(monster, "attack_resolved", 1)
	assert_signal_emitted_with_parameters(monster, "attack_resolved", ["s0", true, resolution_tick])
	assert_signal_emit_count(manager, "player_hit", 1)
	assert_signal_emitted_with_parameters(manager, "player_hit", [VICTIM_PEER, "s0", resolution_tick])
	assert_eq(state.current_hp(), PlayerCombatContractsScript.PLAYER_MAX_HP - MonsterContractsScript.DAMAGE_TO_PLAYER, "one hit removes exactly the authoritative damage")
	var recovery_tick: int = resolution_tick + MonsterContractsScript.ATTACK_ACTIVE_TICKS
	for tick in range(resolution_tick + 1, recovery_tick + 1):
		manager.advance_all([state.position], 1.0, tick, [VICTIM_PEER])
	assert_eq(monster.phase, MonsterContractsScript.PHASE_RECOVERY)
	for tick in range(recovery_tick + 1, recovery_tick + MonsterContractsScript.RECOVERY_TICKS + 1):
		manager.advance_all([state.position], 1.0, tick, [VICTIM_PEER])
	assert_eq(monster.phase, MonsterContractsScript.PHASE_IDLE)
	assert_signal_emit_count(monster, "attack_resolved", 1, "active and recovery ticks do not resolve again")
	assert_signal_emit_count(manager, "player_hit", 1, "active and recovery ticks do not duplicate the hit")
	assert_eq(state.current_hp(), PlayerCombatContractsScript.PLAYER_MAX_HP - MonsterContractsScript.DAMAGE_TO_PLAYER, "active and recovery ticks do not duplicate damage")
