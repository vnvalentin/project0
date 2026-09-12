extends Node3D
## Slice 004 sampled the same WASD directional input actions used by the
## local Player (client/player.gd) and reported them to the server each
## physics tick as input intent — never a requested position. Slice 005
## keeps that unchanged (this is still the same single peer's own intent,
## now sequence-tagged and sent by client/player.gd's own
## NetworkClient.submit_input_intent() call as part of its
## predict-then-reconcile loop, so this node no longer needs to send intent
## itself — see docs/slices/005-prediction-reconciliation.md) and adds
## smoothing: rather than snapping straight to each incoming authoritative
## snapshot, this node moves toward it at a bounded speed
## (NetworkConfig.NETWORKED_PLAYER_SMOOTH_SPEED), only snapping directly when
## the snapshot is farther away than
## NetworkConfig.NETWORKED_PLAYER_SNAP_DISTANCE (e.g. right after spawn).
## This does not change server authority: the target this node smooths
## toward always comes from the server's own authoritative snapshot, never
## from local input or prediction.

const NetworkConfigScript: Script = preload("res://shared/network_config.gd")

var _target_position: Vector3 = Vector3.ZERO
var _has_target: bool = false


func _ready() -> void:
	_target_position = position
	NetworkClient.authoritative_position_received.connect(_on_authoritative_position_received)


func _physics_process(delta: float) -> void:
	if not _has_target:
		return

	if position.distance_to(_target_position) > NetworkConfigScript.NETWORKED_PLAYER_SNAP_DISTANCE:
		position = _target_position
		return

	position = position.move_toward(_target_position, NetworkConfigScript.NETWORKED_PLAYER_SMOOTH_SPEED * delta)


func _on_authoritative_position_received(authoritative_position: Vector3, _last_processed_sequence: int) -> void:
	_target_position = authoritative_position
	_has_target = true
