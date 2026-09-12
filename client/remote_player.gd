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

const NetworkConfigScript: Script = preload("res://shared/network_config.gd")

var peer_id: int = -1
var _target_position: Vector3 = Vector3.ZERO
var _has_target: bool = false


func _ready() -> void:
	_target_position = position
	NetworkClient.remote_player_position_received.connect(_on_remote_player_position_received)


## Public seam: binds this node to the specific peer id it represents.
## Called once, immediately after instantiation, by
## network_client.gd's spawn_remote_player_representation().
func set_peer_id(new_peer_id: int) -> void:
	peer_id = new_peer_id


func _physics_process(delta: float) -> void:
	if not _has_target:
		return

	if position.distance_to(_target_position) > NetworkConfigScript.NETWORKED_PLAYER_SNAP_DISTANCE:
		position = _target_position
		return

	position = position.move_toward(_target_position, NetworkConfigScript.NETWORKED_PLAYER_SMOOTH_SPEED * delta)


func _on_remote_player_position_received(updated_peer_id: int, updated_position: Vector3) -> void:
	if updated_peer_id != peer_id:
		return
	_target_position = updated_position
	_has_target = true
