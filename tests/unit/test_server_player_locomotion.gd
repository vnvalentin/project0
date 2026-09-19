extends GutTest

const ServerPlayerStateScript: Script = preload("res://server/server_player_state.gd")
const LocomotionContractScript: Script = preload("res://shared/locomotion_contract.gd")
const SectorCollisionMapScript: Script = preload("res://shared/sector_collision_map.gd")

const _DELTA: float = 1.0 / 60.0


func _new_state(start: Vector3) -> Node:
	var state: Node = ServerPlayerStateScript.new()
	add_child_autofree(state)
	state.start_for_peer(1, start)
	return state


func _advance(state: Node, ticks: int) -> void:
	for _tick in ticks:
		state._physics_process(_DELTA)


func test_jump_uses_a_bounded_arc_and_returns_to_floor() -> void:
	var state: Node = _new_state(Vector3(0, 1, 0))
	state.apply_input_intent(1, LocomotionContractScript.make_intent(Vector2(0, 1), LocomotionContractScript.MODE_JUMP), 0)
	_advance(state, 10)

	assert_gt(state.position.y, 1.0, "jump raises the authoritative Player above the floor")
	var peak: float = state.position.y
	state.apply_input_intent(1, LocomotionContractScript.make_intent(Vector2.ZERO, LocomotionContractScript.MODE_NONE), 1)
	_advance(state, 60)

	assert_lt(state.position.y, peak, "jump follows a descending arc")
	assert_almost_eq(state.position.y, 1.0, 0.01, "jump lands on the original floor height")


func test_jump_lands_on_an_authored_higher_surface() -> void:
	var state: Node = _new_state(Vector3(0, 1, 0))
	var map: Object = SectorCollisionMapScript.new({
		"tiles": [],
		"structures": [],
		"traversal_surfaces": [{"x_min": -2.0, "x_max": 2.0, "z_min": 1.0, "z_max": 5.0, "height": 2.0}]
	})
	state.set_collision_map(map)
	state.apply_input_intent(1, LocomotionContractScript.make_intent(Vector2(0, 1), LocomotionContractScript.MODE_JUMP), 0)
	_advance(state, 60)

	assert_almost_eq(state.position.y, 2.0, 0.01, "jump lands on the higher authored surface")


func test_jump_lands_on_platform_after_crossing_onto_it() -> void:
	var state: Node = _new_state(Vector3(0, 1, 0))
	var map: Object = SectorCollisionMapScript.new({
		"tiles": [],
		"structures": [],
		"traversal_surfaces": [{"x_min": -2.0, "x_max": 2.0, "z_min": 1.0, "z_max": 5.0, "height": 2.2}]
	})
	state.set_collision_map(map)
	state.apply_input_intent(1, LocomotionContractScript.make_intent(Vector2(0, 1), LocomotionContractScript.MODE_JUMP), 0)
	_advance(state, 60)

	assert_gt(state.position.z, 1.0, "the Player crossed onto the authored platform")
	assert_almost_eq(state.position.y, 2.2, 0.01, "the Player lands on the platform top")


func test_dodge_bursts_faster_than_baseline_movement() -> void:
	var state: Node = _new_state(Vector3.ZERO)
	state.apply_input_intent(1, LocomotionContractScript.make_intent(Vector2(1, 0), LocomotionContractScript.MODE_DODGE), 0)
	_advance(state, LocomotionContractScript.DODGE_TICKS)

	assert_gt(state.position.x, 2.0, "dodge produces a bounded authoritative burst")
	var distance_after_dodge: float = state.position.x
	_advance(state, 1)
	assert_lt(state.position.x - distance_after_dodge, 0.2, "dodge ends instead of restarting at burst speed")


func test_duck_and_slide_are_explicit_posture_modes() -> void:
	var state: Node = _new_state(Vector3.ZERO)
	state.apply_input_intent(1, LocomotionContractScript.make_intent(Vector2.ZERO, LocomotionContractScript.MODE_DUCK), 0)
	assert_eq(state._locomotion_mode, LocomotionContractScript.MODE_DUCK, "duck is represented as an explicit server mode")

	state.apply_input_intent(1, LocomotionContractScript.make_intent(Vector2(1, 0), LocomotionContractScript.MODE_SLIDE), 1)
	assert_eq(state._locomotion_mode, LocomotionContractScript.MODE_SLIDE, "slide is represented as an explicit server mode")


func test_ducked_player_stays_ducked_under_low_ceiling() -> void:
	var state: Node = _new_state(Vector3.ZERO)
	var map: Object = SectorCollisionMapScript.new({
		"tiles": [],
		"structures": [],
		"traversal_ceilings": [{"x_min": -1.0, "x_max": 1.0, "z_min": -1.0, "z_max": 1.0, "height": 1.4}]
	})
	state.set_collision_map(map)
	state.apply_input_intent(1, LocomotionContractScript.make_intent(Vector2.ZERO, LocomotionContractScript.MODE_DUCK), 0)
	state.apply_input_intent(1, LocomotionContractScript.make_intent(Vector2.ZERO, LocomotionContractScript.MODE_NONE), 1)

	assert_eq(state.posture(), LocomotionContractScript.MODE_DUCK, "standing is refused while the Player is under a low ceiling")


func test_wrong_owner_and_stale_intents_do_not_change_locomotion() -> void:
	var state: Node = _new_state(Vector3.ZERO)
	state.apply_input_intent(99, LocomotionContractScript.make_intent(Vector2(1, 0), LocomotionContractScript.MODE_DODGE), 0)
	assert_eq(state._locomotion_mode, LocomotionContractScript.MODE_NONE, "wrong owner cannot control locomotion")

	state.apply_input_intent(1, LocomotionContractScript.make_intent(Vector2(0, 1), LocomotionContractScript.MODE_DUCK), 2)
	state.apply_input_intent(1, LocomotionContractScript.make_intent(Vector2(1, 0), LocomotionContractScript.MODE_JUMP), 1)
	assert_eq(state._locomotion_mode, LocomotionContractScript.MODE_DUCK, "stale intent cannot replace a newer mode")


func test_dodge_window_blocks_monster_damage() -> void:
	var state: Node = _new_state(Vector3.ZERO)
	state.apply_input_intent(1, LocomotionContractScript.make_intent(Vector2(1, 0), LocomotionContractScript.MODE_DODGE), 0)
	_advance(state, 1)
	var starting_hp: int = state.current_hp()

	state.receive_monster_damage(1, 0)

	assert_eq(state.current_hp(), starting_hp, "a dodging Player ignores an authoritative monster hit")