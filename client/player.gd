extends CharacterBody3D
## Player movement for the first playable slice, client-side-first for
## immediate responsiveness (see docs/adr/0001 for why the underlying
## movement authority for this node started fully client-side). Slice 005
## adds prediction/reconciliation on top of that unchanged responsive feel:
## this node still moves immediately from local input every tick with no
## wait on the network, but now also tags each input sample with a
## monotonically increasing sequence number, reports it to the server via
## NetworkClient, and — when the server's authoritative snapshot for this
## peer arrives — discards acknowledged samples and replays only the
## still-unacknowledged ones on top of the authoritative position. The server
## remains the sole owner of the authoritative position; this node's own
## position is a prediction that is corrected, never the source of truth.
## See docs/slices/005-prediction-reconciliation.md.
##
## Slice 012 adds melee-strike input capture (LMB or the "attack" action,
## which the project's input map binds to Space): pressing attack while idle
## immediately starts a local predicted windup (disposable visual/locomotion
## feedback only — see _predicted_attack_ticks_remaining below) and submits a
## melee ActionIntent to the server. If the server rejects it, the local
## prediction is discarded on the next reconciliation; nothing here ever
## claims a hit, since only the server can confirm one. See
## docs/slices/012-authoritative-melee-strike.md.
##
## Slice 013 adds player facing and a cosmetic strike-line indicator: this
## node rotates toward its current WASD movement vector each physics tick (so
## -global_transform.basis.z tracks the direction last moved, matching
## CombatContracts' forward convention), and the same facing is what
## _start_predicted_attack() below submits as the ActionIntent's
## aim_direction. A child MeleeStrikeVisual (client/melee_strike_visual.gd)
## is shown for the predicted ACTIVE phase only, purely cosmetic and
## corrected the same way the predicted locomotion slowdown already is. See
## docs/slices/013-melee-strike-visual-indicator.md.

## Planar move speed in yards/second (1 world unit = 1 yard; see
## shared/world_scale.gd, ADR 0003).
@export var move_speed: float = 5.0

const CombatContractsScript: Script = preload("res://shared/combat_contracts.gd")
const NetworkConfigScript: Script = preload("res://shared/network_config.gd")
const LocomotionContractScript: Script = preload("res://shared/locomotion_contract.gd")
const MeleeStrikeVisualScene: PackedScene = preload("res://client/melee_strike_visual.tscn")

## Disposable local prediction of the attack lifecycle's locomotion slowdown
## only. Never used to claim a hit or an accepted action — it exists purely
## so the local Player visibly slows down immediately instead of waiting a
## round trip, and is corrected (extended, shortened, or cleared) whenever an
## authoritative ActionResolution/position arrives.
var _predicted_archetype: Object = CombatContractsScript.generic_sword_archetype()
var _predicted_phase: String = CombatContractsScript.PHASE_IDLE
var _predicted_ticks_remaining: int = 0
var _next_action_sequence: int = 0
var _pending_action_sequence: int = -1

## One recorded local input sample awaiting server acknowledgement.
class PendingInput:
	var sequence: int
	var intent: Vector2
	var mode: String
	var delta: float

	func _init(p_sequence: int, p_intent: Vector2, p_mode: String, p_delta: float) -> void:
		sequence = p_sequence
		intent = p_intent
		mode = p_mode
		delta = p_delta

var _pending_inputs: Array[PendingInput] = []

## Slice 013: cosmetic child node showing the strike line during the
## predicted ACTIVE phase. Never influences hit resolution or movement.
var _strike_visual: Node3D = null
var _player_shape: CapsuleShape3D
var _player_mesh: Node3D


func _ready() -> void:
	NetworkClient.authoritative_position_received.connect(_on_authoritative_position_received)
	NetworkClient.action_resolution_received.connect(_on_action_resolution_received)
	_strike_visual = MeleeStrikeVisualScene.instantiate()
	add_child(_strike_visual)
	_player_shape = get_node("CollisionShape3D").shape.duplicate()
	get_node("CollisionShape3D").shape = _player_shape
	_player_mesh = get_node("MeshInstance3D")


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("attack") and _predicted_phase == CombatContractsScript.PHASE_IDLE:
		_start_predicted_attack()

	var planar_input: Vector2 = get_planar_input()
	var locomotion_mode: String = get_locomotion_mode(planar_input)
	_apply_posture(locomotion_mode)
	_face_movement_direction(planar_input, delta)
	var speed_factor: float = CombatContractsScript.locomotion_speed_factor_for_phase(_predicted_phase, _predicted_archetype)
	_apply_intent(planar_input * speed_factor, locomotion_mode, delta)
	move_and_slide()
	_advance_predicted_phase()

	var sequence: int = NetworkClient.next_input_sequence()
	_pending_inputs.append(PendingInput.new(sequence, planar_input, locomotion_mode, delta))
	NetworkClient.submit_input_intent(planar_input, sequence)


## Public seam: rotates this node so -global_transform.basis.z tracks the
## current movement direction, bounded by NetworkConfig.FACING_TURN_RATE so
## the turn reads as smooth rather than an instant snap. A zero movement
## vector leaves the current facing unchanged (the Player keeps facing the
## last direction it moved, rather than resetting to a default orientation
## whenever input stops), matching how a stationary attacker should still
## swing toward wherever it was last facing.
func _face_movement_direction(planar_input: Vector2, delta: float) -> void:
	if planar_input.length_squared() == 0.0:
		return

	var movement_direction: Vector3 = Vector3(planar_input.x, 0.0, planar_input.y).normalized()
	var target_basis: Basis = Basis.looking_at(movement_direction, Vector3.UP)
	global_transform.basis = global_transform.basis.slerp(target_basis, NetworkConfigScript.FACING_TURN_RATE * delta).orthonormalized()


## Local prediction only: starts the disposable windup slowdown immediately
## on input and submits the authoritative ActionIntent. Never claims a hit or
## an accepted action — see _on_action_resolution_received below for how a
## REJECTED result corrects this prediction.
func _start_predicted_attack() -> void:
	_set_predicted_phase(CombatContractsScript.PHASE_WINDUP, _predicted_archetype.windup_ticks)

	var sequence: int = _next_action_sequence
	_next_action_sequence += 1
	_pending_action_sequence = sequence
	var client_tick: int = Engine.get_physics_frames()
	NetworkClient.submit_action_intent(sequence, client_tick, CombatContractsScript.ACTION_KIND_MELEE_STRIKE, -global_transform.basis.z)


## Advances the local predicted phase by one physics tick using the same
## fixed-tick counting the server uses, so the local locomotion slowdown ends
## at roughly the same time as the server's own phase transition even before
## any authoritative confirmation arrives.
func _advance_predicted_phase() -> void:
	if _predicted_phase == CombatContractsScript.PHASE_IDLE:
		return

	_predicted_ticks_remaining -= 1
	if _predicted_ticks_remaining > 0:
		return

	match _predicted_phase:
		CombatContractsScript.PHASE_WINDUP:
			_set_predicted_phase(CombatContractsScript.PHASE_ACTIVE, _predicted_archetype.active_ticks)
		CombatContractsScript.PHASE_ACTIVE:
			_set_predicted_phase(CombatContractsScript.PHASE_RECOVERY, _predicted_archetype.recovery_ticks)
		CombatContractsScript.PHASE_RECOVERY:
			_set_predicted_phase(CombatContractsScript.PHASE_IDLE, 0)


## Single place that changes _predicted_phase, so the cosmetic strike-line
## visibility (visible only during ACTIVE) always stays consistent with the
## predicted phase, whether the transition came from normal phase advance or
## from a rejection correction.
func _set_predicted_phase(new_phase: String, ticks_remaining: int) -> void:
	_predicted_phase = new_phase
	_predicted_ticks_remaining = ticks_remaining
	if _strike_visual == null:
		return
	if new_phase == CombatContractsScript.PHASE_ACTIVE:
		_strike_visual.start_swing()
	else:
		_strike_visual.end_swing()


## Reconciliation: if the server rejects this client's own pending attack
## sequence, the local predicted phase is discarded immediately rather than
## running out its predicted ticks, since the server never entered WINDUP for
## it at all. An ACCEPTED resolution needs no correction — the local
## prediction already matches what the server just started.
func _on_action_resolution_received(sequence: int, result: String, _rejection_reason: String, _server_tick: int) -> void:
	if sequence != _pending_action_sequence:
		return
	if result == CombatContractsScript.RESULT_REJECTED:
		_set_predicted_phase(CombatContractsScript.PHASE_IDLE, 0)


## Public seam: reads the four directional input actions and returns a
## normalized-or-zero planar direction (x = right/left, y = forward/back).
func get_planar_input() -> Vector2:
	var input_vector: Vector2 = Vector2.ZERO
	input_vector.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	input_vector.y = Input.get_action_strength("move_back") - Input.get_action_strength("move_forward")
	return input_vector


## Public seam: maps named actions to one bounded locomotion mode. Pressed
## actions have priority over held postures so a jump/dodge cannot be replaced
## by duck or slide on the same tick.
func get_locomotion_mode(planar_input: Vector2) -> String:
	if Input.is_action_just_pressed("jump"):
		return LocomotionContractScript.MODE_JUMP
	if Input.is_action_just_pressed("dodge"):
		return LocomotionContractScript.MODE_DODGE
	if Input.is_action_pressed("slide") and planar_input.length_squared() > 0.0:
		return LocomotionContractScript.MODE_SLIDE
	if Input.is_action_pressed("duck"):
		return LocomotionContractScript.MODE_DUCK
	return LocomotionContractScript.MODE_NONE


func _apply_posture(mode: String) -> void:
	var height: float = LocomotionContractScript.STANDING_HEIGHT
	if mode == LocomotionContractScript.MODE_DUCK:
		height = LocomotionContractScript.DUCKING_HEIGHT
	elif mode == LocomotionContractScript.MODE_SLIDE:
		height = LocomotionContractScript.SLIDING_HEIGHT
	_player_shape.height = height
	_player_mesh.scale.y = height / LocomotionContractScript.STANDING_HEIGHT


## Moves this node the same way the server integrates ServerPlayerState, so a
## replayed sample reproduces the server's own math exactly (same speed,
## same normalization rule, same per-sample delta).
func _apply_intent(planar_input: Vector2, mode: String, delta: float) -> void:
	var direction: Vector3 = Vector3(planar_input.x, 0.0, planar_input.y)
	if direction.length_squared() > 0.0:
		direction = direction.normalized()

	var horizontal_speed: float = move_speed
	if mode == LocomotionContractScript.MODE_DODGE:
		horizontal_speed = LocomotionContractScript.DODGE_SPEED
	elif mode == LocomotionContractScript.MODE_SLIDE:
		horizontal_speed *= 1.35
	velocity.x = direction.x * horizontal_speed
	velocity.z = direction.z * horizontal_speed
	if mode == LocomotionContractScript.MODE_JUMP and is_on_floor():
		velocity.y = LocomotionContractScript.JUMP_SPEED
	elif not is_on_floor() or velocity.y > 0.0:
		velocity.y += LocomotionContractScript.GRAVITY * delta
	else:
		velocity.y = 0.0


## Reconciliation: called whenever the server's authoritative snapshot for
## this peer arrives. Discards every pending input the server has already
## processed (sequence <= last_processed_sequence), snaps this node to the
## authoritative position, then replays the remaining unacknowledged inputs
## on top of it so already-responded-to local input is not visually lost.
## Does not change server authority — the server's position is always the
## replay's starting point, never overridden by the client.
func _on_authoritative_position_received(authoritative_position: Vector3, last_processed_sequence: int) -> void:
	var still_pending: Array[PendingInput] = []
	for pending_input: PendingInput in _pending_inputs:
		if pending_input.sequence > last_processed_sequence:
			still_pending.append(pending_input)
	_pending_inputs = still_pending

	position = authoritative_position
	velocity = Vector3.ZERO

	for pending_input: PendingInput in _pending_inputs:
		_apply_intent(pending_input.intent, pending_input.mode, pending_input.delta)
		move_and_slide()
