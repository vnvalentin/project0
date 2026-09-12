extends Node
## Server-side authority for one connected Player's position, for Slice 004's
## authoritative-movement proof, extended in Slice 005 with input sequence
## tracking for client-side prediction/reconciliation, and in Slice 007 with a
## peer-position-broadcast signal so the server can replicate this Player's
## authoritative position to every other connected peer. Holds the latest
## directional input intent reported by the owning client's NetworkClient
## RPC, integrates position at a fixed speed every physics tick, and RPCs the
## resulting authoritative position plus the latest processed input sequence
## back to that same client. See
## docs/slices/004-authoritative-player-movement.md,
## docs/slices/005-prediction-reconciliation.md,
## docs/slices/007-multi-peer-player-replication.md, and docs/adr/0001 for
## scope: no collision authority, no persistence. The server still never
## accepts a client-supplied position or sequence-tagged position — sequence
## numbers only identify which input the client's intent came from, never
## override the server's own computed position.
##
## Slice 007 scope: `server/server_main.gd` now owns one instance of this
## node per connected peer (keyed by peer id) instead of a single shared
## instance, so exactly two concurrently connected peers each get their own
## authoritative position and input-sequence bookkeeping with no shared
## mutable state between them.

const NetworkConfigScript: Script = preload("res://shared/network_config.gd")

## Emitted every physics tick after this peer's authoritative position is
## computed, so server_main.gd can broadcast it to every other connected
## peer without this node needing to know about peer replication itself.
signal position_updated(peer_id: int, updated_position: Vector3)

var owning_peer_id: int = -1
var position: Vector3 = Vector3.ZERO
var _input_intent: Vector2 = Vector2.ZERO
var _last_processed_sequence: int = -1


## Public seam: called by the server when a peer connects, to bind this state
## node to that peer and its starting position.
func start_for_peer(peer_id: int, start_position: Vector3) -> void:
	owning_peer_id = peer_id
	position = start_position
	_input_intent = Vector2.ZERO
	_last_processed_sequence = -1


## Public seam: called (as a plain in-process call, not an RPC — this node
## exists only server-side, so it is never reached over the network directly;
## see client/network_client.gd's submit_input_intent for the RPC entry
## point) with the latest directional input intent reported by the owning
## client and the client-assigned sequence number for that intent sample.
## Never a requested position — the server still owns the resulting position.
## sender_id is verified against owning_peer_id so only the bound peer's
## intent is applied. Because the intent RPC is unreliable/unordered, a
## sample is only applied if its sequence is not older than the last one
## already processed, so a late-arriving stale sample cannot overwrite a
## newer one.
func apply_input_intent(sender_id: int, intent: Vector2, sequence: int) -> void:
	if sender_id != owning_peer_id:
		return
	if sequence <= _last_processed_sequence:
		return
	_input_intent = intent
	_last_processed_sequence = sequence


func _physics_process(delta: float) -> void:
	if owning_peer_id == -1:
		return

	var direction: Vector3 = Vector3(_input_intent.x, 0.0, _input_intent.y)
	if direction.length_squared() > 0.0:
		direction = direction.normalized()

	position += direction * NetworkConfigScript.AUTHORITATIVE_MOVE_SPEED * delta

	var network_client: Node = get_tree().root.get_node_or_null("NetworkClient")
	if network_client != null:
		network_client.rpc_id(owning_peer_id, "receive_authoritative_position", position, _last_processed_sequence)

	position_updated.emit(owning_peer_id, position)
