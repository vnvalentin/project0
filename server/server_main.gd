extends SceneTree
## Headless server entry point for Slice 002's connection proof, extended in
## Slice 003 with a configurable bind address for LAN reachability, in
## Slice 004 with authoritative movement for one connected Player, and in
## Slice 007 with support for exactly two concurrently connected peers, each
## with a distinct authoritative Player state and a replicated remote
## representation on the other peer's client.
## Run with: godot --headless --path . -s server/server_main.gd
## Optionally target a LAN interface with:
##   godot --headless --path . -s server/server_main.gd -- --server-bind-address=<LAN IP>
## or the PROJECT0_SERVER_BIND_ADDRESS environment variable. Defaults to
## 127.0.0.1 (localhost-only) when neither is set — see
## shared/network_config.gd's resolve_server_bind_address() and
## docs/slices/003-lan-client-connection.md for the safety rationale.
## Starts an ENetMultiplayerPeer server and, for each connecting client,
## RPCs that client's own NetworkClient autoload to spawn a visible Player
## representation in its already-loaded gameplay scene, creates a
## ServerPlayerState node that owns that peer's authoritative position (Slice
## 004), and (Slice 007) tells every other already-connected peer to spawn a
## remote representation for the new peer, tells the new peer to spawn a
## remote representation for every already-connected peer, and relays each
## peer's authoritative position to every other peer. No collision authority,
## reconciliation, or persistence — see docs/adr/0001,
## docs/slices/002-client-connects-to-server.md,
## docs/slices/004-authoritative-player-movement.md, and
## docs/slices/007-multi-peer-player-replication.md for scope.

const NetworkConfigScript: Script = preload("res://shared/network_config.gd")
const ServerPlayerStateScript: Script = preload("res://server/server_player_state.gd")

## Slice 007 scope: this server proves authoritative replication for exactly
## two connected peers, matching the smallest-slice decision boundary in
## .scratch/game-vision/issues/13-multi-peer-player-replication.md. A third
## concurrent peer is rejected rather than silently accepted (see
## _on_peer_connected below).
const MAX_REPLICATED_PEERS: int = 2

## Keyed by peer id; each connected peer owns exactly one ServerPlayerState,
## so two peers never share mutable position/input-sequence state.
var _player_states: Dictionary = {}
var _peer: ENetMultiplayerPeer


func _initialize() -> void:
	call_deferred("_start_server")


## Public seam: starts listening and wires connection signals. Deferred past
## _initialize() because SceneTree.root's multiplayer API is not yet attached
## when _initialize() runs.
func _start_server() -> void:
	var bind_address: String = NetworkConfigScript.resolve_server_bind_address()

	_peer = ENetMultiplayerPeer.new()
	# set_bind_ip() must be called before create_server(); Godot 4.3's
	# create_server() itself takes no address argument and binds all
	# interfaces ("*") unless set_bind_ip() restricts it first (confirmed
	# empirically — see docs/slices/003-lan-client-connection.md).
	_peer.set_bind_ip(bind_address)
	var listen_error: Error = _peer.create_server(NetworkConfigScript.SERVER_PORT, NetworkConfigScript.MAX_CLIENTS, 0, 0, 0)
	if listen_error != OK:
		push_error("Server failed to listen on %s:%d: %s" % [bind_address, NetworkConfigScript.SERVER_PORT, listen_error])
		quit(1)
		return

	root.multiplayer.multiplayer_peer = _peer
	root.multiplayer.peer_connected.connect(_on_peer_connected)
	root.multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("Server listening on %s:%d" % [bind_address, NetworkConfigScript.SERVER_PORT])
	if bind_address != NetworkConfigScript.SERVER_ADDRESS:
		print("WARNING: bound to a non-localhost address. This server accepts unauthenticated connections from any host that can reach %s:%d. Only do this on a trusted local network." % [bind_address, NetworkConfigScript.SERVER_PORT])


## Called whenever a client peer finishes connecting. Tells that peer (only)
## to spawn its own visible Player representation via its NetworkClient
## autoload, which lives at the same node path (/root/NetworkClient) on
## both sides. Slice 007: also creates that peer's own ServerPlayerState,
## replicates the new peer to every already-connected peer (and vice versa)
## by RPCing a distinct "spawn a remote Player for peer id X" call — never
## reusing one shared representation node for two different peers — and
## rejects a third concurrent connection outright, since this slice's proof
## is scoped to exactly two peers.
func _on_peer_connected(peer_id: int) -> void:
	print("Peer connected: %d" % peer_id)
	var network_client: Node = root.get_node("NetworkClient")

	if _player_states.size() >= MAX_REPLICATED_PEERS:
		push_error("Rejecting peer %d: already at MAX_REPLICATED_PEERS (%d)" % [peer_id, MAX_REPLICATED_PEERS])
		root.multiplayer.multiplayer_peer.disconnect_peer(peer_id)
		return

	network_client.rpc_id(peer_id, "spawn_own_player_representation")

	var start_position: Vector3 = _start_position_for_slot(_player_states.size())
	var player_state: Node = ServerPlayerStateScript.new()
	player_state.name = "ServerPlayerState_%d" % peer_id
	player_state.position_updated.connect(_on_player_state_position_updated)
	root.add_child(player_state)
	player_state.start_for_peer(peer_id, start_position)
	_player_states[peer_id] = player_state

	# Replicate existing peers to the new peer, and the new peer to existing
	# peers — each direction is its own explicit RPC call naming the target
	# peer id, so no representation node is ever shared between two peers.
	for existing_peer_id: int in _player_states.keys():
		if existing_peer_id == peer_id:
			continue
		var existing_state: Node = _player_states[existing_peer_id]
		network_client.rpc_id(peer_id, "spawn_remote_player_representation", existing_peer_id, existing_state.position)
		network_client.rpc_id(existing_peer_id, "spawn_remote_player_representation", peer_id, start_position)


## Called whenever a client peer disconnects. Removes that peer's
## ServerPlayerState entirely (Slice 007: no longer just unbinds a shared
## instance, since each peer now owns its own) and tells every remaining
## peer to despawn that departed peer's remote representation.
func _on_peer_disconnected(peer_id: int) -> void:
	print("Peer disconnected: %d" % peer_id)
	var player_state: Node = _player_states.get(peer_id)
	if player_state != null:
		player_state.position_updated.disconnect(_on_player_state_position_updated)
		_player_states.erase(peer_id)
		player_state.queue_free()

	var network_client: Node = root.get_node_or_null("NetworkClient")
	if network_client == null:
		return
	for remaining_peer_id: int in _player_states.keys():
		network_client.rpc_id(remaining_peer_id, "despawn_remote_player_representation", peer_id)


## Relays one peer's authoritative position to every other connected peer so
## each client's remote representation of that peer can be updated. Never
## sent back to the owning peer itself, which already receives its own
## authoritative position (plus sequence acknowledgement) directly from
## ServerPlayerState._physics_process via receive_authoritative_position.
func _on_player_state_position_updated(peer_id: int, updated_position: Vector3) -> void:
	var network_client: Node = root.get_node_or_null("NetworkClient")
	if network_client == null:
		return
	for other_peer_id: int in _player_states.keys():
		if other_peer_id == peer_id:
			continue
		network_client.rpc_id(other_peer_id, "receive_remote_player_position", peer_id, updated_position)


## Deterministic, visibly distinct starting positions for the first two
## connected peers so two Player representations never spawn on top of each
## other in this slice's proof.
func _start_position_for_slot(slot_index: int) -> Vector3:
	if slot_index == 0:
		return Vector3(3.0, 1.0, 3.0)
	return Vector3(-3.0, 1.0, -3.0)
