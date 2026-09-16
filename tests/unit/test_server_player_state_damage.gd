extends GutTest
## Public-seam unit tests for Slice 094's authoritative Player-damage seam on
## ServerPlayerState (server/server_player_state.gd): receive_monster_damage,
## the provisional defeat->full-HP-respawn placeholder, and the health_changed/
## player_defeated telemetry. Drives the node directly (no listening server, so
## its _physics_process rpc path no-ops per its own CONNECTION_CONNECTED guard).
## See docs/slices/094-player-hp-monster-damage.md.

const ServerPlayerStateScript: Script = preload("res://server/server_player_state.gd")
const PlayerCombatContractsScript: Script = preload("res://shared/player_combat_contracts.gd")
const MonsterContractsScript: Script = preload("res://shared/monster_contracts.gd")

const PEER_ID: int = 7
const SPAWN: Vector3 = Vector3(3, 1, -4)


func _started_state() -> Object:
	var state: Object = ServerPlayerStateScript.new()
	autofree(state)
	state.start_for_peer(PEER_ID, SPAWN)
	return state


func test_starts_at_full_hp() -> void:
	var state: Object = _started_state()
	assert_eq(state.current_hp(), PlayerCombatContractsScript.PLAYER_MAX_HP, "a Player enters the world at full HP")
	assert_eq(state.max_hp(), PlayerCombatContractsScript.PLAYER_MAX_HP, "max HP is the provisional pool")


func test_one_monster_hit_reduces_hp_and_emits_health_changed() -> void:
	var state: Object = _started_state()
	watch_signals(state)
	state.receive_monster_damage(MonsterContractsScript.DAMAGE_TO_PLAYER, 100)
	assert_eq(state.current_hp(), PlayerCombatContractsScript.PLAYER_MAX_HP - MonsterContractsScript.DAMAGE_TO_PLAYER, "one landed monster hit removes DAMAGE_TO_PLAYER")
	assert_signal_emitted_with_parameters(state, "health_changed", [PEER_ID, PlayerCombatContractsScript.PLAYER_MAX_HP - MonsterContractsScript.DAMAGE_TO_PLAYER, PlayerCombatContractsScript.PLAYER_MAX_HP, 100])
	assert_signal_not_emitted(state, "player_defeated", "a non-lethal hit does not defeat the Player")


func test_ignores_damage_before_world_entry() -> void:
	var state: Object = ServerPlayerStateScript.new()
	autofree(state)
	watch_signals(state)
	state.receive_monster_damage(MonsterContractsScript.DAMAGE_TO_PLAYER, 1)
	assert_signal_not_emitted(state, "health_changed", "damage before start_for_peer is ignored")


func test_lethal_damage_defeats_then_respawns_at_full_hp_and_spawn_anchor() -> void:
	var state: Object = _started_state()
	# Move the Player away from its spawn anchor so the respawn reposition is observable.
	state.position = Vector3(50, 1, 50)
	watch_signals(state)

	state.receive_monster_damage(MonsterContractsScript.DAMAGE_TO_PLAYER, 1)
	state.receive_monster_damage(MonsterContractsScript.DAMAGE_TO_PLAYER, 2)
	assert_signal_not_emitted(state, "player_defeated", "not defeated before the third hit")

	state.receive_monster_damage(MonsterContractsScript.DAMAGE_TO_PLAYER, 3)
	assert_signal_emitted_with_parameters(state, "player_defeated", [PEER_ID, 3])
	assert_eq(state.current_hp(), PlayerCombatContractsScript.PLAYER_MAX_HP, "the provisional respawn restores full HP")
	assert_eq(state.position, SPAWN, "the defeated Player is returned to its spawn anchor")
	# The final health_changed reports the restored full HP (emitted after defeat).
	assert_signal_emitted_with_parameters(state, "health_changed", [PEER_ID, PlayerCombatContractsScript.PLAYER_MAX_HP, PlayerCombatContractsScript.PLAYER_MAX_HP, 3])


func test_overkill_single_hit_defeats_once() -> void:
	var state: Object = _started_state()
	watch_signals(state)
	state.receive_monster_damage(PlayerCombatContractsScript.PLAYER_MAX_HP * 10, 9)
	assert_eq(state.current_hp(), PlayerCombatContractsScript.PLAYER_MAX_HP, "an overkill hit defeats then respawns to full HP")
	assert_eq(get_signal_emit_count(state, "player_defeated"), 1, "an overkill hit reports exactly one defeat")
