extends GutTest
## Slice 130: the town-NPC population manager. Anchors start staffed; a lost
## occupant is NOT instantly refilled — replacement is delayed, shortened by
## pressure (nearby players), and is either a silent promotion of an ambient NPC
## or a newly generated identity. See docs/slices/130-phase14-town-npc-manager.md.

const ServerTownNpcManagerScript: Script = preload("res://server/server_town_npc_manager.gd")

const FORGE_HOME: Vector3 = Vector3(40, 1, 0)
const MARKET_HOME: Vector3 = Vector3(0, 1, 40)


func _anchor_defs(delay: int = 100) -> Array:
	return [
		{
			"anchor_id": "forge", "role": "smith", "home_position": FORGE_HOME,
			"desired_capacity": 1, "replacement_delay_ticks": delay,
			"routine_steps": [{"activity_id": "work", "duration_ticks": 10}],
			"activity_locations": {"work": FORGE_HOME},
		},
		{
			"anchor_id": "market", "role": "vendor", "home_position": MARKET_HOME,
			"desired_capacity": 1, "replacement_delay_ticks": delay,
		},
	]


func _manager(delay: int = 100) -> Object:
	return ServerTownNpcManagerScript.new(_anchor_defs(delay), 42)


func test_anchors_start_staffed_to_capacity() -> void:
	var manager: Object = _manager()
	assert_eq(manager.anchor_count(), 2, "both anchors exist")
	assert_eq(manager.npc_count(), 2, "each anchor starts staffed to capacity")
	assert_eq(manager.anchor_deficit(0), 0, "a fully staffed anchor has no deficit")


func test_removing_an_npc_understaffs_the_anchor() -> void:
	var manager: Object = _manager()
	var npc_id: String = (manager.npcs_at(0)[0] as Object).npc_id
	assert_true(manager.remove_npc(0, npc_id, 1), "the occupant is removed")
	assert_eq(manager.npc_count(), 1, "the anchor is now understaffed")
	assert_eq(manager.anchor_deficit(0), 1, "deficit is one")


func test_no_instant_respawn_before_the_delay() -> void:
	var manager: Object = _manager(100)
	var npc_id: String = (manager.npcs_at(0)[0] as Object).npc_id
	manager.remove_npc(0, npc_id, 1)
	# No nearby players (no pressure): the full delay applies.
	manager.advance([], 50, 51)
	assert_eq(manager.npc_count(), 1, "no replacement before the delay elapses")


func test_generates_a_new_identity_after_the_delay() -> void:
	var manager: Object = _manager(100)
	var original_id: String = (manager.npcs_at(0)[0] as Object).npc_id
	watch_signals(manager)
	manager.remove_npc(0, original_id, 1)
	manager.advance([], 100, 101)
	assert_eq(manager.npc_count(), 2, "the anchor is restaffed after the delay")
	var replacement: Object = manager.npcs_at(0)[0]
	assert_ne(replacement.npc_id, original_id, "the replacement is a new identity, not the same individual")
	assert_signal_emitted(manager, "npc_spawned")
	var params: Array = get_signal_parameters(manager, "npc_spawned", 0)
	assert_eq(params[2], "generate", "with no ambient candidate, the source is a generated identity")


func test_promotes_an_ambient_candidate_when_available() -> void:
	var manager: Object = _manager(100)
	manager.add_ambient_candidate("Rowan the Onlooker")
	var npc_id: String = (manager.npcs_at(0)[0] as Object).npc_id
	watch_signals(manager)
	manager.remove_npc(0, npc_id, 1)
	manager.advance([], 100, 101)
	var replacement: Object = manager.npcs_at(0)[0]
	assert_eq(replacement.display_name, "Rowan the Onlooker", "an ambient NPC is silently promoted into the role")
	var params: Array = get_signal_parameters(manager, "npc_spawned", 0)
	assert_eq(params[2], "promote", "the source is a promotion")


func test_pressure_from_a_nearby_player_shortens_the_delay() -> void:
	var manager: Object = _manager(1000)
	var npc_id: String = (manager.npcs_at(0)[0] as Object).npc_id
	manager.remove_npc(0, npc_id, 1)
	# A player standing at the anchor is full pressure -> immediate refill despite
	# the long base delay.
	manager.advance([FORGE_HOME], 1, 2)
	assert_eq(manager.npc_count(), 2, "pressure shortens the delay to an immediate refill")


func test_generated_identities_are_unique() -> void:
	var manager: Object = _manager(1)
	var first_id: String = (manager.npcs_at(0)[0] as Object).npc_id
	manager.remove_npc(0, first_id, 1)
	manager.advance([], 1, 2)
	var second_id: String = (manager.npcs_at(0)[0] as Object).npc_id
	manager.remove_npc(0, second_id, 3)
	manager.advance([], 1, 4)
	var third_id: String = (manager.npcs_at(0)[0] as Object).npc_id
	assert_ne(first_id, second_id, "each generated identity is unique")
	assert_ne(second_id, third_id, "and unique again")
