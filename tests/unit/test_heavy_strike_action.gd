extends GutTest
## Slice 141 (Phase 12, IP-015): the second authoritative action kind, Heavy
## Strike. It reuses the whole action machine + reach/arc test; only its
## data-driven archetype differs. The server now resolves a bounded action set
## (two kinds) authoritatively. See docs/slices/141-heavy-strike-action.md and
## .scratch/melee-combat/issues/03-model-melee-weapon-archetypes.md.

const CombatContractsScript: Script = preload("res://shared/combat_contracts.gd")
const ServerPlayerStateScript: Script = preload("res://server/server_player_state.gd")


func _player_state() -> Node:
	var player_state: Node = ServerPlayerStateScript.new()
	add_child_autofree(player_state)
	player_state.start_for_peer(1, Vector3.ZERO)
	return player_state


func _heavy_intent(sequence: int) -> Object:
	return CombatContractsScript.ActionIntent.new(1, sequence, 0, CombatContractsScript.ACTION_KIND_HEAVY_STRIKE, Vector3.FORWARD)


func test_both_melee_and_heavy_are_supported_action_kinds() -> void:
	assert_true(CombatContractsScript.is_supported_action_kind("MELEE_STRIKE"))
	assert_true(CombatContractsScript.is_supported_action_kind("HEAVY_STRIKE"))
	assert_false(CombatContractsScript.is_supported_action_kind("BOGUS"))


func test_archetype_for_action_routes_each_kind() -> void:
	assert_eq(CombatContractsScript.archetype_for_action("MELEE_STRIKE").archetype_id, "BASIC_SWORD")
	assert_eq(CombatContractsScript.archetype_for_action("HEAVY_STRIKE").archetype_id, "HEAVY_GREATSWORD")
	assert_null(CombatContractsScript.archetype_for_action("BOGUS"), "an unsupported kind has no archetype")


func test_heavy_archetype_is_slower_wider_and_longer() -> void:
	var heavy: Object = CombatContractsScript.heavy_strike_archetype()
	var sword: Object = CombatContractsScript.generic_sword_archetype()
	assert_true(heavy.windup_ticks >= sword.windup_ticks, "a heavy telegraph is at least as readable")
	assert_true(heavy.reach_yards > sword.reach_yards, "heavy reaches further")
	assert_true(heavy.arc_degrees > sword.arc_degrees, "heavy sweeps wider")
	assert_true(heavy.max_targets > sword.max_targets, "heavy can catch more targets")


func test_heavy_reach_hits_where_the_sword_misses() -> void:
	# A target 2.5 yd directly ahead: inside heavy's 3.0 reach, outside sword's 2.0.
	var target: Vector3 = Vector3.FORWARD * 2.5
	assert_true(CombatContractsScript.is_within_reach_and_arc(Vector3.ZERO, Vector3.FORWARD, target, CombatContractsScript.heavy_strike_archetype()), "heavy reaches it")
	assert_false(CombatContractsScript.is_within_reach_and_arc(Vector3.ZERO, Vector3.FORWARD, target, CombatContractsScript.generic_sword_archetype()), "the sword falls short")


func test_heavy_wide_arc_catches_a_flanking_target() -> void:
	# A target 50 deg off forward at 1.5 yd: inside heavy's 120 deg sweep
	# (half-arc 60), outside the sword's 60 deg (half-arc 30); within both reaches.
	var target: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(50.0)) * 1.5
	assert_true(CombatContractsScript.is_within_reach_and_arc(Vector3.ZERO, Vector3.FORWARD, target, CombatContractsScript.heavy_strike_archetype()), "the wide sweep catches it")
	assert_false(CombatContractsScript.is_within_reach_and_arc(Vector3.ZERO, Vector3.FORWARD, target, CombatContractsScript.generic_sword_archetype()), "the narrow sword arc misses it")


func test_server_accepts_heavy_and_enters_windup_with_heavy_timing() -> void:
	var player_state: Node = _player_state()
	watch_signals(player_state)
	var resolution: Object = player_state.apply_action_intent(1, _heavy_intent(0))
	assert_eq(resolution.result, CombatContractsScript.RESULT_ACCEPTED, "a heavy strike from IDLE is accepted")
	assert_eq(player_state._phase, CombatContractsScript.PHASE_WINDUP)
	assert_eq(player_state._phase_ticks_remaining, 12, "windup uses the heavy archetype's ticks")
	assert_signal_emitted_with_parameters(player_state, "melee_swing_started", [1, 12, 4, Vector3.FORWARD])


func test_server_still_rejects_an_unsupported_action_kind() -> void:
	var player_state: Node = _player_state()
	var bogus: Object = CombatContractsScript.ActionIntent.new(1, 0, 0, "BOGUS", Vector3.FORWARD)
	var resolution: Object = player_state.apply_action_intent(1, bogus)
	assert_eq(resolution.result, CombatContractsScript.RESULT_REJECTED)
	assert_eq(resolution.rejection_reason, CombatContractsScript.REJECTED_INVALID_STATE)
