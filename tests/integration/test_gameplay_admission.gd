extends GutTest

const ServerMainScript: Script = preload("res://server/server_main.gd")
const SessionsScript: Script = preload("res://server/session_registry.gd")
const CharactersScript: Script = preload("res://server/character_service.gd")
const GatewayScript: Script = preload("res://server/login_gateway.gd")
const PEER_ID: int = 51
const CombatScript: Script = preload("res://shared/combat_contracts.gd")
const STEP: float = 1.0 / 60.0

var _sessions: Object
var _gateway: Node
var _state: Node
var _network_client: Node


func before_each() -> void:
	assert_null(get_tree().root.get_node_or_null("LoginGateway"))
	_network_client = get_tree().root.get_node("NetworkClient")
	get_tree().root.remove_child(_network_client)
	_sessions = SessionsScript.new()
	var characters: Node = CharactersScript.new(null, _sessions)
	add_child_autofree(characters)
	_gateway = GatewayScript.new(null, characters, _sessions)
	_gateway.name = "LoginGateway"
	get_tree().root.add_child(_gateway)
	var actor_script: Script = ServerMainScript.get_script_constant_map()["ServerPlayerStateScript"]
	_state = actor_script.new()
	add_child_autofree(_state)
	_state.start_for_peer(PEER_ID, Vector3.ZERO)
	_state.set_physics_process(false)


func after_each() -> void:
	_gateway.free()
	get_tree().root.add_child(_network_client)


func _authenticate() -> void:
	_sessions.bind(PEER_ID, "test-account", "test-player")
	_sessions.set_selected_character_snapshot(PEER_ID, "test-character", "Test Player", {})
	_state.bind_character("test-character", "Test Player", {})


func _advance() -> void:
	for tick: int in range(60):
		_state._physics_process(STEP)


func test_missing_session_cannot_move_or_poison_later_sequence() -> void:
	_state.apply_input_intent(PEER_ID, Vector2.RIGHT, 10000)
	_advance()
	assert_eq(_state.position, Vector3.ZERO, "No session means no authoritative movement")
	_authenticate()
	_state.apply_input_intent(PEER_ID, Vector2.RIGHT, 1)
	_advance()
	assert_gt(_state.position.x, 4.0, "Rejected input did not consume the authenticated sequence")


func test_authenticated_selected_character_can_move() -> void:
	_authenticate()
	_state.apply_input_intent(PEER_ID, Vector2.RIGHT, 1)
	_advance()
	assert_gt(_state.position.x, 4.0)


func test_cleared_session_stops_and_drops_retained_input() -> void:
	_authenticate()
	_state.apply_input_intent(PEER_ID, Vector2.RIGHT, 1)
	_advance()
	var stopped_at: Vector3 = _state.position
	_sessions.clear(PEER_ID)
	_advance()
	assert_eq(_state.position, stopped_at, "Revoked session cannot continue its last intent")
	_authenticate()
	_advance()
	assert_eq(_state.position, stopped_at, "Reauthentication does not restore stale input")


func test_session_without_bound_character_is_not_gameplay_admission() -> void:
	_sessions.bind(PEER_ID, "test-account", "test-player")
	_sessions.set_selected_character_snapshot(PEER_ID, "test-character", "Test Player", {})
	_state.apply_input_intent(PEER_ID, Vector2.RIGHT, 1)
	_advance()
	assert_eq(_state.position, Vector3.ZERO)


func test_unauthenticated_action_does_not_consume_authenticated_sequence() -> void:
	var blocked: Object = CombatScript.ActionIntent.new(PEER_ID, 10000, 0, CombatScript.ACTION_KIND_MELEE_STRIKE, Vector3.FORWARD)
	watch_signals(_state)
	var rejected: Object = _state.apply_action_intent(PEER_ID, blocked)
	assert_not_null(rejected)
	if rejected != null:
		assert_eq(rejected.result, CombatScript.RESULT_REJECTED)
		assert_eq(rejected.rejection_reason, "NOT_ADMITTED")
	assert_signal_emitted(_state, "action_resolved")
	_authenticate()
	var accepted: Object = CombatScript.ActionIntent.new(PEER_ID, 1, 0, CombatScript.ACTION_KIND_MELEE_STRIKE, Vector3.FORWARD)
	var resolution: Object = _state.apply_action_intent(PEER_ID, accepted)
	assert_not_null(resolution)
	if resolution != null:
		assert_eq(resolution.result, CombatScript.RESULT_ACCEPTED)


func test_mismatched_character_and_missing_gateway_fail_closed() -> void:
	_authenticate()
	_state.bind_character("different-character", "Different", {})
	_state.apply_input_intent(PEER_ID, Vector2.RIGHT, 1)
	_advance()
	assert_eq(_state.position, Vector3.ZERO)
	_state.bind_character("test-character", "Test Player", {})
	get_tree().root.remove_child(_gateway)
	_state.apply_input_intent(PEER_ID, Vector2.RIGHT, 2)
	_advance()
	assert_eq(_state.position, Vector3.ZERO)
	get_tree().root.add_child(_gateway)


func test_character_rebinding_discards_previous_input_without_an_idle_tick() -> void:
	_authenticate()
	_state.apply_input_intent(PEER_ID, Vector2.RIGHT, 1)
	_advance()
	var stopped_at: Vector3 = _state.position
	_sessions.clear(PEER_ID)
	_sessions.bind(PEER_ID, "other-account", "other-player")
	_sessions.set_selected_character_snapshot(PEER_ID, "other-character", "Other", {})
	_state.bind_character("other-character", "Other", {})
	_advance()
	assert_eq(_state.position, stopped_at)


func test_replaced_session_requires_new_world_binding_even_for_same_character() -> void:
	_authenticate()
	_state.apply_input_intent(PEER_ID, Vector2.RIGHT, 1)
	_advance()
	var stopped_at: Vector3 = _state.position
	_sessions.clear(PEER_ID)
	_sessions.bind(PEER_ID, "test-account", "test-player")
	_sessions.set_selected_character_snapshot(PEER_ID, "test-character", "Test Player", {})
	_advance()
	assert_eq(_state.position, stopped_at)


func test_revoked_jump_does_not_resume_after_reauthentication() -> void:
	var locomotion: Script = load("res://shared/locomotion_contract.gd")
	_authenticate()
	_state.apply_input_intent(PEER_ID, {"direction": Vector2.ZERO, "mode": locomotion.MODE_JUMP}, 1)
	_state._physics_process(STEP)
	var stopped_height: float = _state.position.y
	assert_gt(stopped_height, 0.0)
	_sessions.clear(PEER_ID)
	_state._physics_process(STEP)
	_authenticate()
	_state._physics_process(STEP)
	assert_lte(_state.position.y, stopped_height)


func test_duplicate_world_binding_does_not_cancel_combat_recovery() -> void:
	_authenticate()
	var first: Object = CombatScript.ActionIntent.new(PEER_ID, 1, 0, CombatScript.ACTION_KIND_MELEE_STRIKE, Vector3.FORWARD)
	assert_eq(_state.apply_action_intent(PEER_ID, first).result, CombatScript.RESULT_ACCEPTED)
	var archetype: Object = CombatScript.generic_sword_archetype()
	for tick: int in range(archetype.windup_ticks + archetype.active_ticks):
		_state._physics_process(STEP)
	_state.bind_character("test-character", "Test Player", {})
	var second: Object = CombatScript.ActionIntent.new(PEER_ID, 2, 0, CombatScript.ACTION_KIND_MELEE_STRIKE, Vector3.FORWARD)
	var rejected: Object = _state.apply_action_intent(PEER_ID, second)
	assert_eq(rejected.result, CombatScript.RESULT_REJECTED)
	assert_eq(rejected.rejection_reason, CombatScript.REJECTED_COOLDOWN)
