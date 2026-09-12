extends GutTest
## Public-seam unit tests for Slice 013: client/player.gd's movement-facing
## rotation and its use for melee aim direction, client/melee_strike_visual.gd's
## show/hide behavior, and server/server_player_state.gd's new
## melee_swing_started signal broadcast to every peer (not just the attacker).
## Run with: godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit
## -gselect=test_melee_strike_visual_indicator -gexit

const CombatContractsScript: Script = preload("res://shared/combat_contracts.gd")
const ServerPlayerStateScript: Script = preload("res://server/server_player_state.gd")

var _instance: Node = null


func after_each() -> void:
	if is_instance_valid(_instance):
		_instance.queue_free()
	_instance = null


func _load_gameplay_player() -> CharacterBody3D:
	var scene: PackedScene = load("res://client/gameplay.tscn")
	_instance = scene.instantiate()
	add_child_autofree(_instance)
	return _instance.get_node("Player")


func test_player_rotates_to_face_movement_direction() -> void:
	var player: CharacterBody3D = _load_gameplay_player()
	await wait_physics_frames(1)

	for _tick in range(60):
		player.velocity.x = 3.0
		player.velocity.z = 0.0
		player._face_movement_direction(Vector2(1.0, 0.0), 1.0 / 60.0)

	var forward: Vector3 = -player.global_transform.basis.z
	assert_almost_eq(forward.x, 1.0, 0.05, "facing rotates toward the rightward movement vector's world direction")
	assert_almost_eq(forward.z, 0.0, 0.05, "facing has no residual Z component after turning fully right")


func test_player_keeps_last_facing_when_input_stops() -> void:
	var player: CharacterBody3D = _load_gameplay_player()
	await wait_physics_frames(1)

	for _tick in range(60):
		player._face_movement_direction(Vector2(0.0, 1.0), 1.0 / 60.0)
	var facing_after_movement: Basis = player.global_transform.basis

	player._face_movement_direction(Vector2.ZERO, 1.0 / 60.0)

	assert_eq(player.global_transform.basis, facing_after_movement, "zero movement input leaves the last facing unchanged")


func test_predicted_active_phase_shows_and_hides_strike_visual() -> void:
	var player: CharacterBody3D = _load_gameplay_player()
	await wait_physics_frames(1)

	var strike_visual: Node3D = player._strike_visual
	assert_false(strike_visual.visible, "the strike visual starts hidden")

	var archetype: Object = CombatContractsScript.generic_sword_archetype()
	player._start_predicted_attack()
	assert_false(strike_visual.visible, "the strike visual stays hidden during the predicted WINDUP phase")

	for _i in archetype.windup_ticks:
		player._advance_predicted_phase()
	assert_true(strike_visual.visible, "the strike visual is shown once the predicted phase reaches ACTIVE")

	for _i in archetype.active_ticks:
		player._advance_predicted_phase()
	assert_false(strike_visual.visible, "the strike visual is hidden again once the predicted phase leaves ACTIVE")


func test_rejected_resolution_hides_strike_visual_immediately() -> void:
	var player: CharacterBody3D = _load_gameplay_player()
	await wait_physics_frames(1)

	var strike_visual: Node3D = player._strike_visual
	player._start_predicted_attack()
	var archetype: Object = CombatContractsScript.generic_sword_archetype()
	for _i in archetype.windup_ticks:
		player._advance_predicted_phase()
	assert_true(strike_visual.visible, "sanity check: the visual is showing before the rejection arrives")

	player._on_action_resolution_received(player._pending_action_sequence, CombatContractsScript.RESULT_REJECTED, CombatContractsScript.REJECTED_BUSY, 0)

	assert_false(strike_visual.visible, "a rejected resolution hides the strike visual immediately rather than waiting out predicted ticks")
	assert_eq(player._predicted_phase, CombatContractsScript.PHASE_IDLE, "a rejected resolution resets the predicted phase to IDLE")


func test_melee_strike_visual_component_toggles_independently() -> void:
	var visual_scene: PackedScene = load("res://client/melee_strike_visual.tscn")
	var visual: Node3D = visual_scene.instantiate()
	add_child_autofree(visual)
	await wait_physics_frames(1)

	assert_false(visual.visible, "a freshly instantiated strike visual starts hidden")
	visual.start_swing()
	assert_true(visual.visible, "start_swing() shows the strike visual")
	visual.end_swing()
	assert_false(visual.visible, "end_swing() hides the strike visual")


func test_accepted_melee_intent_emits_swing_started_for_every_observer() -> void:
	var player_state: Node = ServerPlayerStateScript.new()
	add_child_autofree(player_state)
	player_state.start_for_peer(1, Vector3.ZERO)

	var swings: Array = []
	player_state.melee_swing_started.connect(
		func(peer_id: int, windup_ticks: int, active_ticks: int, facing: Vector3) -> void:
			swings.append({"peer_id": peer_id, "windup_ticks": windup_ticks, "active_ticks": active_ticks, "facing": facing})
	)

	var archetype: Object = CombatContractsScript.generic_sword_archetype()
	var intent: Object = CombatContractsScript.ActionIntent.new(1, 0, 0, CombatContractsScript.ACTION_KIND_MELEE_STRIKE, Vector3(0.0, 0.0, -1.0))
	player_state.apply_action_intent(1, intent)

	assert_eq(swings.size(), 1, "an accepted melee intent emits melee_swing_started exactly once")
	assert_eq(swings[0]["peer_id"], 1, "the emitted swing names the attacking peer")
	assert_eq(swings[0]["windup_ticks"], archetype.windup_ticks, "the emitted swing carries the archetype's windup duration")
	assert_eq(swings[0]["active_ticks"], archetype.active_ticks, "the emitted swing carries the archetype's active duration")
	assert_eq(swings[0]["facing"], Vector3(0.0, 0.0, -1.0), "the emitted swing carries the accepted facing")


func test_rejected_melee_intent_does_not_emit_swing_started() -> void:
	var player_state: Node = ServerPlayerStateScript.new()
	add_child_autofree(player_state)
	player_state.start_for_peer(1, Vector3.ZERO)

	var swings: Array = []
	player_state.melee_swing_started.connect(
		func(_peer_id: int, _windup_ticks: int, _active_ticks: int, _facing: Vector3) -> void: swings.append(true)
	)

	var first_intent: Object = CombatContractsScript.ActionIntent.new(1, 0, 0, CombatContractsScript.ACTION_KIND_MELEE_STRIKE, Vector3.FORWARD)
	player_state.apply_action_intent(1, first_intent)
	swings.clear()

	var second_intent: Object = CombatContractsScript.ActionIntent.new(1, 1, 0, CombatContractsScript.ACTION_KIND_MELEE_STRIKE, Vector3.FORWARD)
	player_state.apply_action_intent(1, second_intent)

	assert_eq(swings.size(), 0, "a busy-rejected melee intent never emits melee_swing_started")


func test_remote_player_times_strike_visual_from_swing_started_signal() -> void:
	var remote_player_scene: PackedScene = load("res://client/remote_player.tscn")
	var remote_player: Node3D = remote_player_scene.instantiate()
	add_child_autofree(remote_player)
	remote_player.set_peer_id(2)
	await wait_physics_frames(1)

	var archetype: Object = CombatContractsScript.generic_sword_archetype()
	remote_player._on_melee_swing_started_received(2, archetype.windup_ticks, archetype.active_ticks, Vector3(1.0, 0.0, 0.0))

	assert_false(remote_player._strike_visual.visible, "the remote strike visual stays hidden during the mirrored WINDUP countdown")

	for _i in archetype.windup_ticks:
		remote_player._advance_strike_visual()
	assert_true(remote_player._strike_visual.visible, "the remote strike visual is shown once the mirrored countdown reaches ACTIVE")

	for _i in archetype.active_ticks:
		remote_player._advance_strike_visual()
	assert_false(remote_player._strike_visual.visible, "the remote strike visual is hidden again once the mirrored ACTIVE window ends")


func test_remote_player_ignores_swing_started_for_a_different_peer() -> void:
	var remote_player_scene: PackedScene = load("res://client/remote_player.tscn")
	var remote_player: Node3D = remote_player_scene.instantiate()
	add_child_autofree(remote_player)
	remote_player.set_peer_id(2)
	await wait_physics_frames(1)

	remote_player._on_melee_swing_started_received(99, 6, 4, Vector3.FORWARD)

	assert_eq(remote_player._swing_phase, "", "a swing_started signal for a different peer id is ignored")
