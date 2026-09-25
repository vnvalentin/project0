extends "res://server/server_player_state.gd"

var _admitted_session_epoch: int = 0


func bind_character(p_character_id: String, p_display_name: String, p_cosmetic: Dictionary) -> void:
	var gateway: Node = get_tree().root.get_node_or_null("LoginGateway") if is_inside_tree() else null
	var current_epoch: int = gateway.get_session_epoch(owning_peer_id) if gateway != null else 0
	if current_epoch != _admitted_session_epoch or p_character_id != character_id:
		_clear_gameplay_intent()
	_admitted_session_epoch = current_epoch
	super.bind_character(p_character_id, p_display_name, p_cosmetic)


func _gameplay_authorized() -> bool:
	if _admitted_session_epoch <= 0 or character_id.is_empty() or not is_inside_tree():
		return false
	var gateway: Node = get_tree().root.get_node_or_null("LoginGateway")
	if gateway == null or gateway.get_session_epoch(owning_peer_id) != _admitted_session_epoch:
		return false
	var identity: Dictionary = gateway.get_presence_identity(owning_peer_id)
	return not String(identity.get("account_id", "")).is_empty() and String(identity.get("character_id", "")) == character_id


func apply_input_intent(sender_id: int, intent: Variant, sequence: int) -> void:
	if sender_id != owning_peer_id:
		return
	if not _gameplay_authorized():
		_clear_gameplay_intent()
		return
	super.apply_input_intent(sender_id, intent, sequence)


func apply_action_intent(sender_id: int, intent: Object) -> Object:
	if sender_id != owning_peer_id:
		return null
	if not _gameplay_authorized():
		_clear_gameplay_intent()
		var rejected: Object = _make_resolution(intent.sequence, false, CombatContractsScript.REJECTED_NOT_ADMITTED)
		action_resolved.emit(owning_peer_id, rejected)
		return rejected
	return super.apply_action_intent(sender_id, intent)


func _physics_process(delta: float) -> void:
	if not _gameplay_authorized():
		_clear_gameplay_intent()
		return
	super._physics_process(delta)


func _clear_gameplay_intent() -> void:
	_input_intent = Vector2.ZERO
	_vertical_velocity = 0.0
	_locomotion_mode = LocomotionContractScript.MODE_NONE
	_posture = LocomotionContractScript.MODE_NONE
	_dodge_ticks_remaining = 0
	_dodge_direction = Vector3.ZERO
	_slide_ticks_remaining = 0
	_phase = CombatContractsScript.PHASE_IDLE
	_phase_ticks_remaining = 0
	_hit_target_ids_this_swing.clear()
	_last_action_resolution = null
