extends Node3D
## Slice 007: visible representation of one other connected peer's
## authoritative Player position. A distinct instance of this script/scene is
## spawned per remote peer id by client/network_client.gd
## (spawn_remote_player_representation), named "RemotePlayer_<peer_id>" and
## never shared between two different peers. Smooths toward each incoming
## authoritative snapshot the same bounded way the owning client's own blue
## NetworkedPlayer does (client/networked_player_input.gd), so ordinary
## network jitter does not read as a teleport; an extreme delta still snaps
## in one frame. This node never sends input or receives its own sequence
## acknowledgement — it only ever renders positions the server has already
## computed and broadcast for a peer that is not this client.
##
## Slice 013 adds facing and a cosmetic strike-line indicator: this node
## rotates to face its own movement direction (derived from successive
## position snapshots, the same -global_transform.basis.z convention
## client/player.gd uses) and, on receiving this peer's
## melee_swing_started_received signal, times a local ACTIVE-phase window
## (counted in physics ticks, mirroring server/server_player_state.gd's own
## fixed-tick phase counting) during which its MeleeStrikeVisual child is
## shown. This is presentation only — it never claims a hit; only
## client/target_dummy.gd reacts to the authoritative CombatEvent.HIT. See
## docs/slices/013-melee-strike-visual-indicator.md.

const NetworkConfigScript: Script = preload("res://shared/network_config.gd")
const CombatContractsScript: Script = preload("res://shared/combat_contracts.gd")
const MeleeStrikeVisualScene: PackedScene = preload("res://client/melee_strike_visual.tscn")

var peer_id: int = -1
var _target_position: Vector3 = Vector3.ZERO
var _has_target: bool = false

var _strike_visual: Node3D = null

## Slice 013: mirrors server/server_player_state.gd's WINDUP/ACTIVE fixed-tick
## countdown, but only far enough to time the cosmetic strike-line — no
## RECOVERY tracking is needed since nothing renders differently during
## RECOVERY. "" (no swing in flight) is the default; "WINDUP" counts down
## _ticks_remaining to the ACTIVE transition, "ACTIVE" counts it down to
## hiding the strike line again.
var _swing_phase: String = ""
var _ticks_remaining: int = 0
var _pending_active_ticks: int = 0


func _ready() -> void:
	_target_position = position
	NetworkClient.remote_player_position_received.connect(_on_remote_player_position_received)
	NetworkClient.melee_swing_started_received.connect(_on_melee_swing_started_received)
	_strike_visual = MeleeStrikeVisualScene.instantiate()
	add_child(_strike_visual)


## Public seam: binds this node to the specific peer id it represents.
## Called once, immediately after instantiation, by
## network_client.gd's spawn_remote_player_representation().
func set_peer_id(new_peer_id: int) -> void:
	peer_id = new_peer_id


func _physics_process(delta: float) -> void:
	_advance_strike_visual()

	if not _has_target:
		return

	_face_target_direction(delta)

	if position.distance_to(_target_position) > NetworkConfigScript.NETWORKED_PLAYER_SNAP_DISTANCE:
		position = _target_position
		return

	position = position.move_toward(_target_position, NetworkConfigScript.NETWORKED_PLAYER_SMOOTH_SPEED * delta)


## Rotates toward the direction from this node's currently rendered position
## to its latest authoritative target snapshot, the same bounded turn rate as
## client/player.gd's own facing, so a remote peer's swing direction reads
## consistently across every observing client. A near-zero remaining distance
## (already at the target) leaves the current facing unchanged.
func _face_target_direction(delta: float) -> void:
	var to_target: Vector3 = _target_position - position
	to_target.y = 0.0
	if to_target.length_squared() < 0.0001:
		return

	var target_basis: Basis = Basis.looking_at(to_target.normalized(), Vector3.UP)
	global_transform.basis = global_transform.basis.slerp(target_basis, NetworkConfigScript.FACING_TURN_RATE * delta).orthonormalized()


func _on_remote_player_position_received(updated_peer_id: int, updated_position: Vector3) -> void:
	if updated_peer_id != peer_id:
		return
	_target_position = updated_position
	_has_target = true


## Starts this remote representation's own fixed-tick WINDUP-then-ACTIVE
## countdown for the cosmetic strike-line, mirroring the server's own timing
## so the visible slash appears at roughly the same moment on every observing
## client. Ignores swings from any peer other than the one this node
## represents. Restarts the countdown from WINDUP even if a previous swing's
## visual is still active, matching the server's own single-swing-at-a-time
## authority (a second ActionIntent cannot be ACCEPTED while the first is
## still WINDUP/ACTIVE, so this signal cannot legitimately fire again before
## the prior countdown would have finished).
func _on_melee_swing_started_received(swing_peer_id: int, windup_ticks: int, active_ticks: int, facing: Vector3) -> void:
	if swing_peer_id != peer_id:
		return
	if facing.length_squared() > 0.0:
		global_transform.basis = Basis.looking_at(facing.normalized(), Vector3.UP)
	_swing_phase = CombatContractsScript.PHASE_WINDUP
	_ticks_remaining = windup_ticks
	_pending_active_ticks = active_ticks
	_strike_visual.end_swing()


func _advance_strike_visual() -> void:
	if _swing_phase == "":
		return

	_ticks_remaining -= 1
	if _ticks_remaining > 0:
		return

	match _swing_phase:
		CombatContractsScript.PHASE_WINDUP:
			_swing_phase = CombatContractsScript.PHASE_ACTIVE
			_ticks_remaining = _pending_active_ticks
			_strike_visual.start_swing()
		CombatContractsScript.PHASE_ACTIVE:
			_swing_phase = ""
			_strike_visual.end_swing()
