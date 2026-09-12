extends GutTest
## Public-seam tests for the Basic Monsters slice 02 authoritative state machine
## (server/server_monster_state.gd). Pure/deterministic — drives advance()
## directly and watches the telemetry signals, no SceneTree or physics. See
## docs/slices/021-monster-ai-state-machine.md.

const ServerMonsterStateScript: Script = preload("res://server/server_monster_state.gd")
const MonsterContractsScript: Script = preload("res://shared/monster_contracts.gd")
const CombatContractsScript: Script = preload("res://shared/combat_contracts.gd")


func _monster(spawn: Vector3 = Vector3(0, 1, 0)) -> Object:
	return ServerMonsterStateScript.new("monster_0", spawn)


func _advance_n(monster: Object, player_position: Vector3, n: int, delta: float = 1.0) -> void:
	for i in n:
		monster.advance(player_position, delta, i)


func test_idle_until_player_enters_detection_radius() -> void:
	var monster: Object = _monster()
	monster.advance(Vector3(20, 1, 0), 1.0, 1)
	assert_eq(monster.phase, MonsterContractsScript.PHASE_IDLE, "a far player leaves the monster idle")

	monster.advance(Vector3(5, 1, 0), 1.0, 2)
	assert_eq(monster.phase, MonsterContractsScript.PHASE_CHASE, "a player inside DETECTION_RADIUS starts a chase")


func test_chase_moves_toward_the_player() -> void:
	var monster: Object = _monster()
	var player: Vector3 = Vector3(6, 1, 0)
	monster.advance(player, 1.0, 1)  # IDLE -> CHASE
	monster.advance(player, 1.0, 2)  # CHASE: move
	assert_gt(monster.position.x, 0.0, "the monster moves toward the player while chasing")
	assert_eq(monster.phase, MonsterContractsScript.PHASE_CHASE, "still chasing while out of reach")


func test_chase_returns_to_idle_when_player_flees() -> void:
	var monster: Object = _monster()
	monster.advance(Vector3(5, 1, 0), 1.0, 1)  # -> CHASE
	assert_eq(monster.phase, MonsterContractsScript.PHASE_CHASE, "chasing")
	monster.advance(Vector3(50, 1, 0), 1.0, 2)  # player fled beyond detection
	assert_eq(monster.phase, MonsterContractsScript.PHASE_IDLE, "losing the player returns the monster to idle")


func test_enters_windup_when_player_is_in_reach() -> void:
	var monster: Object = _monster()
	var player: Vector3 = Vector3(1.5, 1, 0)  # within MONSTER_REACH_METERS (2) and ahead
	monster.advance(player, 1.0, 1)  # IDLE -> CHASE
	monster.advance(player, 1.0, 2)  # CHASE -> WINDUP (in reach)
	assert_eq(monster.phase, MonsterContractsScript.PHASE_WINDUP, "a player in reach triggers the attack windup")


func test_windup_telegraph_is_at_least_as_long_as_the_player_attack() -> void:
	# Binding fairness invariant (CLAUDE.md Combat Reading): the monster's
	# telegraph must be at least as readable as the player's own attack.
	var player_windup: int = CombatContractsScript.generic_sword_archetype().windup_ticks
	assert_true(MonsterContractsScript.WINDUP_TICKS >= player_windup, "monster WINDUP_TICKS (%d) >= player windup (%d)" % [MonsterContractsScript.WINDUP_TICKS, player_windup])


func test_windup_resolves_a_hit_after_windup_ticks() -> void:
	var monster: Object = _monster()
	var player: Vector3 = Vector3(1.5, 1, 0)
	monster.advance(player, 1.0, 1)  # -> CHASE
	monster.advance(player, 1.0, 2)  # -> WINDUP
	var resolved: Array = []
	monster.attack_resolved.connect(func(_tid: String, landed: bool, _tick: int) -> void:
		resolved.append(landed))
	# Hold the player in reach through the whole telegraph.
	_advance_n(monster, player, MonsterContractsScript.WINDUP_TICKS)
	assert_eq(monster.phase, MonsterContractsScript.PHASE_ATTACK, "the monster reaches ATTACK after WINDUP_TICKS")
	assert_eq(resolved.size(), 1, "exactly one attack is resolved")
	assert_true(resolved[0], "the held-in-reach player is hit")


func test_player_can_dodge_out_of_the_telegraph() -> void:
	var monster: Object = _monster()
	var player: Vector3 = Vector3(1.5, 1, 0)
	monster.advance(player, 1.0, 1)  # -> CHASE
	monster.advance(player, 1.0, 2)  # -> WINDUP (facing locked)
	var resolved: Array = []
	monster.attack_resolved.connect(func(_tid: String, landed: bool, _tick: int) -> void:
		resolved.append(landed))
	# The player steps well out of reach/arc during the windup.
	_advance_n(monster, Vector3(30, 1, 0), MonsterContractsScript.WINDUP_TICKS)
	assert_eq(resolved.size(), 1, "exactly one attack is resolved")
	assert_false(resolved[0], "a player who dodged out of the locked reach/arc is missed")


func test_full_cycle_returns_to_idle() -> void:
	var monster: Object = _monster()
	var player: Vector3 = Vector3(1.5, 1, 0)
	monster.advance(player, 1.0, 0)  # -> CHASE
	monster.advance(player, 1.0, 1)  # -> WINDUP
	_advance_n(monster, player, MonsterContractsScript.WINDUP_TICKS)      # -> ATTACK
	assert_eq(monster.phase, MonsterContractsScript.PHASE_ATTACK, "reached ATTACK")
	_advance_n(monster, player, MonsterContractsScript.ATTACK_ACTIVE_TICKS)  # -> RECOVERY
	assert_eq(monster.phase, MonsterContractsScript.PHASE_RECOVERY, "reached RECOVERY")
	_advance_n(monster, player, MonsterContractsScript.RECOVERY_TICKS)    # -> IDLE
	assert_eq(monster.phase, MonsterContractsScript.PHASE_IDLE, "the full attack cycle returns to IDLE")


func test_receive_damage_kills_and_emits_one_death() -> void:
	var monster: Object = _monster()
	var deaths: Array = []
	monster.died.connect(func(tid: String, killer: int, pos: Vector3, tick: int) -> void:
		deaths.append({"tid": tid, "killer": killer, "pos": pos, "tick": tick}))
	monster.receive_damage(MonsterContractsScript.MAX_HP, 7, 42)
	assert_true(monster.is_dead(), "taking MAX_HP damage kills the monster")
	assert_eq(monster.phase, MonsterContractsScript.PHASE_DEAD, "a dead monster is in the DEAD phase")
	assert_eq(deaths.size(), 1, "exactly one death event is emitted")
	assert_eq(deaths[0]["killer"], 7, "the death names the killer peer")
	assert_eq(deaths[0]["pos"], Vector3(0, 1, 0), "the death carries the monster position")


func test_dead_monster_ignores_further_advance_and_damage() -> void:
	var monster: Object = _monster()
	monster.receive_damage(MonsterContractsScript.MAX_HP, 7, 1)
	watch_signals(monster)
	monster.advance(Vector3(1, 1, 0), 1.0, 2)
	monster.receive_damage(MonsterContractsScript.DAMAGE_PER_HIT, 7, 3)
	assert_eq(monster.phase, MonsterContractsScript.PHASE_DEAD, "a dead monster stays dead")
	assert_signal_not_emitted(monster, "died", "no second death is emitted for an already-dead monster")
	assert_signal_not_emitted(monster, "phase_changed", "a dead monster emits no further transitions")
