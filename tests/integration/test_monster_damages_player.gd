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
