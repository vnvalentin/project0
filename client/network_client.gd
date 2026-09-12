extends Node
## Autoload singleton owning the client's connection to the headless server,
## the visible spawn of this client's own Player representation once the
## server confirms the connection, sending directional input intent to the
## server (Slice 004), and (Slice 005) tagging that intent with a
## monotonically increasing sequence number and receiving back the
## authoritative position plus the latest sequence the server has processed.
## Slice 007 adds replication of other connected peers: spawning/despawning a
## distinct remote representation per peer id (never reusing one shared node
## for two different peers) and receiving each remote peer's authoritative
## position broadcast. See docs/slices/002-client-connects-to-server.md,
## docs/slices/003-lan-client-connection.md,
## docs/slices/004-authoritative-player-movement.md,
## docs/slices/005-prediction-reconciliation.md,
## docs/slices/007-multi-peer-player-replication.md, and docs/adr/0001 for
## scope: this client never sends a requested position, only intent; the
## server remains the sole owner of every peer's resulting position.
## Reconciliation of the red predicted Player and smoothing of the blue
## NetworkedPlayer both happen in their own node scripts (client/player.gd,
## client/networked_player_input.gd), which listen to the signal below —
## this autoload only relays what the server sends, it does not implement
## prediction or smoothing itself. Remote-peer smoothing lives in its own
## node script (client/remote_player.gd) for the same reason.

signal connection_status_changed(status: String)
signal authoritative_position_received(position: Vector3, last_processed_sequence: int)
signal remote_player_position_received(peer_id: int, position: Vector3)

const NetworkConfigScript: Script = preload("res://shared/network_config.gd")
const NETWORKED_PLAYER_SCENE_PATH: String = "res://client/networked_player.tscn"
const REMOTE_PLAYER_SCENE_PATH: String = "res://client/remote_player.tscn"
const REMOTE_PLAYERS_CONTAINER_NAME: String = "RemotePlayers"

var status: String = "disconnected"
var _peer: ENetMultiplayerPeer


func _ready() -> void:
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


## Public seam: starts an ENet client connection attempt to the given host
## and port. When host is left as the default, it resolves via
## NetworkConfig.resolve_client_target_host() (CLI arg, then env var, then
## localhost); port defaults to the shared NetworkConfig port. Non-blocking —
## outcome arrives via the connection_status_changed signal.
func connect_to_server(host: String = "", port: int = NetworkConfigScript.SERVER_PORT) -> void:
	var target_host: String = host
	if target_host.is_empty():
		target_host = NetworkConfigScript.resolve_client_target_host()
	_peer = ENetMultiplayerPeer.new()
	var connect_error: Error = _peer.create_client(target_host, port)
	if connect_error != OK:
		_set_status("failed: could not start client (%s)" % connect_error)
		return

	multiplayer.multiplayer_peer = _peer
	_set_status("connecting")


func _on_connected_to_server() -> void:
	_set_status("connected")


func _on_connection_failed() -> void:
	_set_status("failed: connection refused")


func _on_server_disconnected() -> void:
	_set_status("disconnected")


func _set_status(new_status: String) -> void:
	status = new_status
	connection_status_changed.emit(status)


## RPC target called by the server on this specific client once its peer
## connection is accepted. Spawns a visible Player representation into the
## current scene's Gameplay root, tagged as networked so it is visually
## distinguishable from the pre-existing local WASD Player. Named
## "own" (Slice 007, renamed from "local") to contrast explicitly with
## spawn_remote_player_representation() below, which spawns a distinct node
## per other connected peer.
@rpc("authority", "call_remote", "reliable")
func spawn_own_player_representation() -> void:
	var gameplay_root: Node = get_tree().current_scene
	if gameplay_root == null:
		push_error("NetworkClient: cannot spawn networked Player, no current_scene")
		return

	var existing: Node = gameplay_root.get_node_or_null("NetworkedPlayer")
	if existing != null:
		return

	var networked_player_scene: PackedScene = load(NETWORKED_PLAYER_SCENE_PATH)
	var networked_player: Node3D = networked_player_scene.instantiate()
	networked_player.name = "NetworkedPlayer"
	gameplay_root.add_child(networked_player)
	_set_status("connected: player spawned")


## RPC target called by the server on this client for every other connected
## peer, both when this client first connects (once per already-connected
## peer) and when a new peer connects after this client (Slice 007). Spawns a
## distinct remote-representation node per peer id under a dedicated
## RemotePlayers container, named by peer id so two different peers can never
## collide on or share one node. start_position seeds the node so it appears
## at the peer's current authoritative position immediately, rather than at
## the scene's origin until the first position broadcast arrives.
@rpc("authority", "call_remote", "reliable")
func spawn_remote_player_representation(peer_id: int, start_position: Vector3) -> void:
	var gameplay_root: Node = get_tree().current_scene
	if gameplay_root == null:
		push_error("NetworkClient: cannot spawn remote Player for peer %d, no current_scene" % peer_id)
		return

	var container: Node = _get_or_create_remote_players_container(gameplay_root)
	var node_name: String = _remote_player_node_name(peer_id)
	if container.get_node_or_null(node_name) != null:
		return

	var remote_player_scene: PackedScene = load(REMOTE_PLAYER_SCENE_PATH)
	var remote_player: Node3D = remote_player_scene.instantiate()
	remote_player.name = node_name
	remote_player.position = start_position
	container.add_child(remote_player)
	remote_player.call("set_peer_id", peer_id)


## RPC target called by the server on every remaining peer when a peer
## disconnects (Slice 007). Removes that peer's remote representation only —
## other peers' remote nodes and this client's own Player/NetworkedPlayer are
## untouched. A no-op (not an error) if the node is already gone, so this
## stays safe to call even if cleanup already happened.
@rpc("authority", "call_remote", "reliable")
func despawn_remote_player_representation(peer_id: int) -> void:
	var gameplay_root: Node = get_tree().current_scene
	if gameplay_root == null:
		return
	var container: Node = gameplay_root.get_node_or_null(REMOTE_PLAYERS_CONTAINER_NAME)
	if container == null:
		return
	var remote_player: Node = container.get_node_or_null(_remote_player_node_name(peer_id))
	if remote_player != null:
		remote_player.queue_free()


func _get_or_create_remote_players_container(gameplay_root: Node) -> Node:
	var container: Node = gameplay_root.get_node_or_null(REMOTE_PLAYERS_CONTAINER_NAME)
	if container == null:
		container = Node3D.new()
		container.name = REMOTE_PLAYERS_CONTAINER_NAME
		gameplay_root.add_child(container)
	return container


func _remote_player_node_name(peer_id: int) -> String:
	return "RemotePlayer_%d" % peer_id


## Public seam: called by the client each physics tick to report directional
## input intent to the server, tagged with the monotonically increasing
## sequence number the caller assigned to this sample (Slice 005; the
## sequence itself is generated and tracked by the caller, e.g.
## client/player.gd, not by this autoload). This is intent only — never a
## requested position — the server remains the sole owner of the resulting
## position. Calls the RPC on this client's own local NetworkClient instance
## (rpc_id() requires an in-tree Node on the caller's side); Godot's
## multiplayer API delivers it to the server's NetworkClient instance at the
## matching /root/NetworkClient path, which forwards it to the server-only
## ServerPlayerState node via a plain in-process call (see
## receive_input_intent_on_server below). A no-op before this client is
## connected.
func submit_input_intent(intent: Vector2, sequence: int) -> void:
	if not status.begins_with("connected"):
		return
	rpc_id(1, "receive_input_intent_on_server", intent, sequence)


## RPC target: runs only on the server's NetworkClient instance (the peer
## that owns id 1), called by a connected client via submit_input_intent()
## above. any_peer because the client is the caller; unreliable because a
## dropped intent sample is superseded by the next tick's sample (the
## sequence number lets ServerPlayerState discard a stale/reordered sample
## instead of regressing). Forwards to the sender's own server-only
## ServerPlayerState node (named "ServerPlayerState_<sender_id>" since Slice
## 007 — one distinct node per connected peer, not one shared node) with a
## plain function call — no second RPC hop is needed since both live in the
## same server process.
@rpc("any_peer", "call_remote", "unreliable")
func receive_input_intent_on_server(intent: Vector2, sequence: int) -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()
	var server_player_state: Node = get_tree().root.get_node_or_null("ServerPlayerState_%d" % sender_id)
	if server_player_state == null:
		return
	server_player_state.apply_input_intent(sender_id, intent, sequence)


## RPC target: called by the server on the owning client only, with the
## resulting authoritative position for this connected peer and the latest
## input sequence number the server has processed for it (Slice 005). Relays
## both values via the signal above for the red predicted Player's
## reconciliation (client/player.gd) and the blue NetworkedPlayer's smoothing
## (client/networked_player_input.gd) to consume — this autoload does not
## itself decide how to apply the correction.
@rpc("authority", "call_remote", "unreliable")
func receive_authoritative_position(position: Vector3, last_processed_sequence: int) -> void:
	authoritative_position_received.emit(position, last_processed_sequence)


## RPC target: called by the server on every peer other than the one the
## position belongs to, with that other peer's id and its latest
## authoritative position (Slice 007). Never carries a sequence number — this
## is a one-way replication broadcast for rendering another peer's Player,
## not this client's own prediction/reconciliation input, which stays scoped
## to receive_authoritative_position above. Relayed via a signal so the
## remote representation's own node script (client/remote_player.gd) decides
## how to render it (smoothing), matching the existing separation of
## concerns for the red/blue Players.
@rpc("authority", "call_remote", "unreliable")
func receive_remote_player_position(peer_id: int, position: Vector3) -> void:
	remote_player_position_received.emit(peer_id, position)
