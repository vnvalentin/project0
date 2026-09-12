extends GutTest
## Public-seam integration test for Slice 012: proves the full authoritative
## melee-strike lifecycle — an ActionIntent submitted through the same
## in-process seam client/network_client.gd's RPC target forwards to
## (ServerPlayerState.apply_action_intent), the fixed-tick
## WINDUP -> ACTIVE -> RECOVERY -> IDLE state machine advancing on real
## _physics_process ticks, the authoritative locomotion speed factor being
## enforced during WINDUP/RECOVERY, and a deterministic reach/arc hit
## confirmation against a real server-owned TargetDummy node emitting
## CombatEvent.HIT. A real ENet client/server pair cannot share one process
## (Godot 4.3 allows only one MultiplayerAPI peer per SceneTree — see
## scripts/test_multi_peer_replication.gd's docstring), so — matching this
## repository's existing GUT integration tests for server-side seams
## (tests/integration/test_sector_blueprint_contract.gd,
## test_provisional_sector_generation.gd) — this test drives the real
## server-only nodes directly rather than through a live socket.

const CombatContractsScript: Script = preload("res://shared/combat_contracts.gd")
const ServerPlayerStateScript: Script = preload("res://server/server_player_state.gd")

const PHYSICS_DELTA: float = 1.0 / 60.0


func _make_player_state(start_position: Vector3, target_dummies: Dictionary) -> Node:
	var player_state: Node = ServerPlayerStateScript.new()
	add_child_autofree(player_state)
	player_state.start_for_peer(1, start_position)
	player_state.set_target_dummies(target_dummies)
	return player_state


func _make_target_dummy(target_position: Vector3) -> Node3D:
	var dummy: Node3D = Node3D.new()
	add_child_autofree(dummy)
	dummy.position = target_position
	return dummy


func test_full_lifecycle_confirms_hit_on_target_within_reach() -> void:
	var target_dummy: Node3D = _make_target_dummy(Vector3(0.0, 0.0, -1.5))
	var player_state: Node = _make_player_state(Vector3.ZERO, {"target_dummy_0": target_dummy})
	player_state.facing = Vector3.FORWARD * -1.0 # -Z is Godot's forward.

	var resolved_results: Array = []
	var combat_events: Array = []
	player_state.action_resolved.connect(func(_peer_id: int, resolution: Object) -> void: resolved_results.append(resolution))
	player_state.combat_event_emitted.connect(func(_peer_id: int, combat_event: Object) -> void: combat_events.append(combat_event))

	var intent: Object = CombatContractsScript.ActionIntent.new(1, 0, 0, CombatContractsScript.ACTION_KIND_MELEE_STRIKE, Vector3(0.0, 0.0, -1.0))
	var resolution: Object = player_state.apply_action_intent(1, intent)

	assert_eq(resolution.result, CombatContractsScript.RESULT_ACCEPTED, "the intent is accepted from IDLE")
	assert_eq(resolved_results.size(), 1, "action_resolved fires exactly once for the accepted intent")

	var archetype: Object = CombatContractsScript.generic_sword_archetype()

	for _i in archetype.windup_ticks:
		player_state._physics_process(PHYSICS_DELTA)
	assert_eq(combat_events.size(), 0, "no hit is confirmed before the ACTIVE phase begins")

	for _i in archetype.active_ticks:
		player_state._physics_process(PHYSICS_DELTA)

	assert_eq(combat_events.size(), 1, "exactly one CombatEvent.HIT is emitted for a target within reach and arc")
	var combat_event: Object = combat_events[0]
	assert_eq(combat_event.kind, CombatContractsScript.COMBAT_EVENT_HIT, "the emitted event is a HIT")
	assert_eq(combat_event.attacker_peer_id, 1, "the event names the attacking peer")
	assert_eq(combat_event.target_id, "target_dummy_0", "the event names the struck target")
	assert_eq(combat_event.impact_position, target_dummy.position, "the event carries the target's authoritative position")

	for _i in archetype.recovery_ticks:
		player_state._physics_process(PHYSICS_DELTA)

	var post_recovery_intent: Object = CombatContractsScript.ActionIntent.new(1, 1, 0, CombatContractsScript.ACTION_KIND_MELEE_STRIKE, Vector3.FORWARD)
	var post_recovery_resolution: Object = player_state.apply_action_intent(1, post_recovery_intent)
	assert_eq(post_recovery_resolution.result, CombatContractsScript.RESULT_ACCEPTED, "a new intent is accepted once the full lifecycle returns to IDLE")


func test_target_out_of_reach_produces_no_hit() -> void:
	var target_dummy: Node3D = _make_target_dummy(Vector3(0.0, 0.0, -10.0))
	var player_state: Node = _make_player_state(Vector3.ZERO, {"target_dummy_0": target_dummy})

	var combat_events: Array = []
	player_state.combat_event_emitted.connect(func(_peer_id: int, combat_event: Object) -> void: combat_events.append(combat_event))

	var intent: Object = CombatContractsScript.ActionIntent.new(1, 0, 0, CombatContractsScript.ACTION_KIND_MELEE_STRIKE, Vector3(0.0, 0.0, -1.0))
	player_state.apply_action_intent(1, intent)

	var archetype: Object = CombatContractsScript.generic_sword_archetype()
	var total_ticks: int = archetype.windup_ticks + archetype.active_ticks
	for _i in total_ticks:
		player_state._physics_process(PHYSICS_DELTA)

	assert_eq(combat_events.size(), 0, "a target far outside reach never produces a hit event")


func test_locomotion_speed_is_authoritatively_reduced_during_windup_and_recovery() -> void:
	var player_state: Node = _make_player_state(Vector3.ZERO, {})
	var intent: Object = CombatContractsScript.ActionIntent.new(1, 0, 0, CombatContractsScript.ACTION_KIND_MELEE_STRIKE, Vector3.FORWARD)
	player_state.apply_action_intent(1, intent)
	player_state.apply_input_intent(1, Vector2(0.0, 1.0), 0)

	var archetype: Object = CombatContractsScript.generic_sword_archetype()

	player_state._physics_process(PHYSICS_DELTA)
	var windup_step_distance: float = player_state.position.length()
	var full_speed_step_distance: float = 5.0 * PHYSICS_DELTA # NetworkConfig.AUTHORITATIVE_MOVE_SPEED

	assert_almost_eq(windup_step_distance, full_speed_step_distance * archetype.windup_speed_factor, 0.001, "windup applies the archetype's windup speed factor to authoritative movement")

	for _i in (archetype.windup_ticks - 1) + archetype.active_ticks:
		player_state._physics_process(PHYSICS_DELTA)

	var position_before_recovery_step: Vector3 = player_state.position
	player_state.apply_input_intent(1, Vector2(0.0, 1.0), 1)
	player_state._physics_process(PHYSICS_DELTA)
	var recovery_step_distance: float = player_state.position.distance_to(position_before_recovery_step)

	assert_almost_eq(recovery_step_distance, full_speed_step_distance * archetype.recovery_speed_factor, 0.001, "recovery applies the archetype's recovery speed factor to authoritative movement")


func test_duplicate_intent_during_active_swing_does_not_start_a_second_swing_or_double_hit() -> void:
	var target_dummy: Node3D = _make_target_dummy(Vector3(0.0, 0.0, -1.5))
	var player_state: Node = _make_player_state(Vector3.ZERO, {"target_dummy_0": target_dummy})

	var combat_events: Array = []
	player_state.combat_event_emitted.connect(func(_peer_id: int, combat_event: Object) -> void: combat_events.append(combat_event))

	var intent: Object = CombatContractsScript.ActionIntent.new(1, 0, 0, CombatContractsScript.ACTION_KIND_MELEE_STRIKE, Vector3(0.0, 0.0, -1.0))
	player_state.apply_action_intent(1, intent)

	var archetype: Object = CombatContractsScript.generic_sword_archetype()
	for _i in archetype.windup_ticks:
		player_state._physics_process(PHYSICS_DELTA)

	# Replay the exact same sequence mid-swing: must not restart windup or
	# affect the in-flight swing at all.
	var replay_resolution: Object = player_state.apply_action_intent(1, intent)
	assert_eq(replay_resolution.result, CombatContractsScript.RESULT_ACCEPTED, "the cached resolution for the replayed sequence is still ACCEPTED")

	for _i in archetype.active_ticks:
		player_state._physics_process(PHYSICS_DELTA)

	assert_eq(combat_events.size(), 1, "a duplicate intent replay during the swing does not cause a double hit")
