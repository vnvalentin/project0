extends GutTest
## Public-seam unit tests for Slice 012's shared/combat_contracts.gd:
## contract shape, the Generic Sword baseline archetype, deterministic vector
## reach/arc hit-test math, and the phase-based locomotion speed factor. Pure
## and stateless — no server/client/network involved. Also covers
## server/server_player_state.gd's sequence ordering, idempotent replay, and
## rejection codes by calling apply_action_intent() directly as a plain
## in-process seam (the same seam server/network_client.gd's RPC forwarding
## calls) — no ENet connection is needed to exercise this logic.

const CombatContractsScript: Script = preload("res://shared/combat_contracts.gd")
const ServerPlayerStateScript: Script = preload("res://server/server_player_state.gd")


func _make_player_state() -> Node:
	var player_state: Node = ServerPlayerStateScript.new()
	add_child_autofree(player_state)
	player_state.start_for_peer(1, Vector3.ZERO)
	return player_state


func _melee_intent(sequence: int) -> Object:
	return CombatContractsScript.ActionIntent.new(1, sequence, 0, CombatContractsScript.ACTION_KIND_MELEE_STRIKE, Vector3.FORWARD)


func test_first_melee_intent_from_idle_is_accepted() -> void:
	var player_state: Node = _make_player_state()
	var resolution: Object = player_state.apply_action_intent(1, _melee_intent(0))
	assert_eq(resolution.result, CombatContractsScript.RESULT_ACCEPTED, "first intent from IDLE is accepted")
	assert_eq(resolution.rejection_reason, "", "accepted resolution carries no rejection reason")


func test_second_intent_while_busy_is_rejected_busy() -> void:
	var player_state: Node = _make_player_state()
	player_state.apply_action_intent(1, _melee_intent(0))
	var resolution: Object = player_state.apply_action_intent(1, _melee_intent(1))
	assert_eq(resolution.result, CombatContractsScript.RESULT_REJECTED, "a second intent while WINDUP is active is rejected")
	assert_eq(resolution.rejection_reason, CombatContractsScript.REJECTED_BUSY, "busy rejection uses REJECTED_BUSY")


func test_intent_during_recovery_is_rejected_cooldown() -> void:
	var player_state: Node = _make_player_state()
	var archetype: Object = CombatContractsScript.generic_sword_archetype()
	player_state.apply_action_intent(1, _melee_intent(0))

	var total_ticks_into_recovery: int = archetype.windup_ticks + archetype.active_ticks + 1
	for _i in total_ticks_into_recovery:
		player_state._physics_process(1.0 / 60.0)

	var resolution: Object = player_state.apply_action_intent(1, _melee_intent(1))
	assert_eq(resolution.result, CombatContractsScript.RESULT_REJECTED, "an intent submitted during RECOVERY is rejected")
	assert_eq(resolution.rejection_reason, CombatContractsScript.REJECTED_COOLDOWN, "recovery rejection uses REJECTED_COOLDOWN")


func test_duplicate_sequence_replay_is_idempotent() -> void:
	var player_state: Node = _make_player_state()
	var first_resolution: Object = player_state.apply_action_intent(1, _melee_intent(5))
	var replayed_resolution: Object = player_state.apply_action_intent(1, _melee_intent(5))

	assert_eq(replayed_resolution.result, first_resolution.result, "a replayed sequence returns the same cached result")
	assert_same(replayed_resolution, first_resolution, "a replayed sequence returns the identical cached resolution object, never a new one")


func test_stale_sequence_is_rejected_stale() -> void:
	var player_state: Node = _make_player_state()
	player_state.apply_action_intent(1, _melee_intent(5))
	# Let the swing finish so a stale check, not a busy check, is what
	# rejects sequence 3.
	var archetype: Object = CombatContractsScript.generic_sword_archetype()
	var total_ticks: int = archetype.windup_ticks + archetype.active_ticks + archetype.recovery_ticks + 1
	for _i in total_ticks:
		player_state._physics_process(1.0 / 60.0)

	var resolution: Object = player_state.apply_action_intent(1, _melee_intent(3))
	assert_eq(resolution.result, CombatContractsScript.RESULT_REJECTED, "a sequence older than the last processed one is rejected")
	assert_eq(resolution.rejection_reason, CombatContractsScript.REJECTED_STALE, "stale rejection uses REJECTED_STALE")


func test_unrecognized_action_kind_is_rejected_invalid_state() -> void:
	var player_state: Node = _make_player_state()
	var intent: Object = CombatContractsScript.ActionIntent.new(1, 0, 0, "NOT_A_REAL_ACTION", Vector3.FORWARD)
	var resolution: Object = player_state.apply_action_intent(1, intent)
	assert_eq(resolution.result, CombatContractsScript.RESULT_REJECTED, "an unrecognized action kind is rejected")
	assert_eq(resolution.rejection_reason, CombatContractsScript.REJECTED_INVALID_STATE, "unrecognized action kind uses REJECTED_INVALID_STATE")


func test_wrong_sender_id_is_ignored() -> void:
	var player_state: Node = _make_player_state()
	var resolution: Object = player_state.apply_action_intent(999, _melee_intent(0))
	assert_null(resolution, "an intent from a sender id that does not own this state is ignored entirely")


func test_full_swing_lifecycle_returns_to_idle_and_allows_a_new_swing() -> void:
	var player_state: Node = _make_player_state()
	var archetype: Object = CombatContractsScript.generic_sword_archetype()
	player_state.apply_action_intent(1, _melee_intent(0))

	var total_ticks: int = archetype.windup_ticks + archetype.active_ticks + archetype.recovery_ticks
	for _i in total_ticks:
		player_state._physics_process(1.0 / 60.0)

	var resolution: Object = player_state.apply_action_intent(1, _melee_intent(1))
	assert_eq(resolution.result, CombatContractsScript.RESULT_ACCEPTED, "a new intent after the full lifecycle completes is accepted")


func test_generic_sword_archetype_matches_resolved_tuning() -> void:
	var archetype: Object = CombatContractsScript.generic_sword_archetype()
	assert_eq(archetype.archetype_id, "BASIC_SWORD", "archetype id matches resolution ticket")
	assert_eq(archetype.windup_ticks, 6, "windup ticks matches resolution ticket")
	assert_eq(archetype.active_ticks, 4, "active ticks matches resolution ticket")
	assert_eq(archetype.recovery_ticks, 10, "recovery ticks matches resolution ticket")
	assert_eq(archetype.reach_meters, 2.0, "reach meters matches resolution ticket")
	assert_eq(archetype.arc_degrees, 60.0, "arc degrees matches resolution ticket")
	assert_eq(archetype.windup_speed_factor, 0.5, "windup speed factor matches resolution ticket")
	assert_eq(archetype.recovery_speed_factor, 0.8, "recovery speed factor matches resolution ticket")
	assert_eq(archetype.max_targets, 1, "max targets matches resolution ticket")


func test_action_intent_carries_no_trusted_outcome_fields() -> void:
	var intent: Object = CombatContractsScript.ActionIntent.new(7, 3, 120, CombatContractsScript.ACTION_KIND_MELEE_STRIKE, Vector3.FORWARD)
	assert_eq(intent.schema_version, CombatContractsScript.SCHEMA_VERSION, "intent stamps the current schema version")
	assert_eq(intent.player_id, 7, "intent carries player id")
	assert_eq(intent.sequence, 3, "intent carries sequence")
	assert_eq(intent.client_tick, 120, "intent carries client tick")
	assert_eq(intent.action_kind, CombatContractsScript.ACTION_KIND_MELEE_STRIKE, "intent carries action kind")
	assert_eq(intent.aim_direction, Vector3.FORWARD, "intent carries aim direction")


func test_action_resolution_rejection_reason_is_one_of_the_bounded_codes() -> void:
	var codes: Array = [
		CombatContractsScript.REJECTED_BUSY,
		CombatContractsScript.REJECTED_COOLDOWN,
		CombatContractsScript.REJECTED_STALE,
		CombatContractsScript.REJECTED_INVALID_STATE,
	]
	for code: String in codes:
		var resolution: Object = CombatContractsScript.ActionResolution.new(1, 0, CombatContractsScript.RESULT_REJECTED, code, 10)
		assert_eq(resolution.result, CombatContractsScript.RESULT_REJECTED, "rejected resolution reports REJECTED")
		assert_true(codes.has(resolution.rejection_reason), "rejection reason is one of the bounded codes: %s" % code)


func test_combat_event_hit_carries_attacker_target_and_impact() -> void:
	var event: Object = CombatContractsScript.CombatEvent.new(CombatContractsScript.COMBAT_EVENT_HIT, 2, "target_dummy_0", Vector3(1, 1, 1), 42)
	assert_eq(event.kind, CombatContractsScript.COMBAT_EVENT_HIT, "event kind is HIT")
	assert_eq(event.attacker_peer_id, 2, "event carries attacker peer id")
	assert_eq(event.target_id, "target_dummy_0", "event carries target id")
	assert_eq(event.impact_position, Vector3(1, 1, 1), "event carries impact position")
	assert_eq(event.server_tick, 42, "event carries server tick")


func test_hit_within_reach_and_directly_ahead_is_a_hit() -> void:
	var archetype: Object = CombatContractsScript.generic_sword_archetype()
	var hit: bool = CombatContractsScript.is_within_reach_and_arc(Vector3.ZERO, Vector3.FORWARD, Vector3.FORWARD * 1.5, archetype)
	assert_true(hit, "a target within reach directly ahead is a hit")


func test_hit_exactly_at_reach_boundary_is_a_hit() -> void:
	var archetype: Object = CombatContractsScript.generic_sword_archetype()
	var hit: bool = CombatContractsScript.is_within_reach_and_arc(Vector3.ZERO, Vector3.FORWARD, Vector3.FORWARD * archetype.reach_meters, archetype)
	assert_true(hit, "a target exactly at the reach boundary is a hit")


func test_miss_beyond_reach_is_a_miss() -> void:
	var archetype: Object = CombatContractsScript.generic_sword_archetype()
	var hit: bool = CombatContractsScript.is_within_reach_and_arc(Vector3.ZERO, Vector3.FORWARD, Vector3.FORWARD * (archetype.reach_meters + 0.01), archetype)
	assert_false(hit, "a target just beyond reach is a miss")


func test_miss_within_reach_but_outside_arc_is_a_miss() -> void:
	var archetype: Object = CombatContractsScript.generic_sword_archetype()
	# 60 degree arc = +/-30 degrees; place the target 45 degrees off forward.
	var off_arc_direction: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(45.0))
	var hit: bool = CombatContractsScript.is_within_reach_and_arc(Vector3.ZERO, Vector3.FORWARD, off_arc_direction * 1.0, archetype)
	assert_false(hit, "a target within reach but outside the +/-30 degree arc is a miss")


func test_hit_exactly_at_arc_boundary_is_a_hit() -> void:
	var archetype: Object = CombatContractsScript.generic_sword_archetype()
	var boundary_direction: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(30.0))
	var hit: bool = CombatContractsScript.is_within_reach_and_arc(Vector3.ZERO, Vector3.FORWARD, boundary_direction * 1.0, archetype)
	assert_true(hit, "a target exactly at the +/-30 degree arc boundary is a hit")


func test_miss_directly_behind_attacker() -> void:
	var archetype: Object = CombatContractsScript.generic_sword_archetype()
	var hit: bool = CombatContractsScript.is_within_reach_and_arc(Vector3.ZERO, Vector3.FORWARD, Vector3.BACK * 1.0, archetype)
	assert_false(hit, "a target directly behind the attacker is a miss")


func test_zero_length_forward_never_hits() -> void:
	var archetype: Object = CombatContractsScript.generic_sword_archetype()
	var hit: bool = CombatContractsScript.is_within_reach_and_arc(Vector3.ZERO, Vector3.ZERO, Vector3.FORWARD * 1.0, archetype)
	assert_false(hit, "a zero-length forward vector has no defined direction and never hits")


func test_target_at_attacker_position_is_always_a_hit() -> void:
	var archetype: Object = CombatContractsScript.generic_sword_archetype()
	var hit: bool = CombatContractsScript.is_within_reach_and_arc(Vector3.ONE, Vector3.FORWARD, Vector3.ONE, archetype)
	assert_true(hit, "a target exactly at the attacker's position has zero distance and is always within reach")


func test_locomotion_speed_factor_matches_phase() -> void:
	var archetype: Object = CombatContractsScript.generic_sword_archetype()
	assert_eq(CombatContractsScript.locomotion_speed_factor_for_phase(CombatContractsScript.PHASE_WINDUP, archetype), 0.5, "windup uses the archetype's windup speed factor")
	assert_eq(CombatContractsScript.locomotion_speed_factor_for_phase(CombatContractsScript.PHASE_RECOVERY, archetype), 0.8, "recovery uses the archetype's recovery speed factor")
	assert_eq(CombatContractsScript.locomotion_speed_factor_for_phase(CombatContractsScript.PHASE_ACTIVE, archetype), 1.0, "active phase has no locomotion penalty in this slice")
	assert_eq(CombatContractsScript.locomotion_speed_factor_for_phase(CombatContractsScript.PHASE_IDLE, archetype), 1.0, "idle phase has no locomotion penalty")
