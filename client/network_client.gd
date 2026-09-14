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
## position broadcast. Slice 012 adds melee ActionIntent submission and
## receiving the authoritative ActionResolution/CombatEvent.HIT broadcasts.
## See docs/slices/002-client-connects-to-server.md,
## docs/slices/003-lan-client-connection.md,
## docs/slices/004-authoritative-player-movement.md,
## docs/slices/005-prediction-reconciliation.md,
## docs/slices/007-multi-peer-player-replication.md,
## docs/slices/012-authoritative-melee-strike.md, and docs/adr/0001 for
## scope: this client never sends a requested position, only intent; the
## server remains the sole owner of every peer's resulting position, action
## resolution, and combat outcome.
## Reconciliation of the red predicted Player and smoothing of the blue
## NetworkedPlayer both happen in their own node scripts (client/player.gd,
## client/networked_player_input.gd), which listen to the signal below —
## this autoload only relays what the server sends, it does not implement
## prediction or smoothing itself. Remote-peer smoothing lives in its own
## node script (client/remote_player.gd) for the same reason. Melee
## prediction/reconciliation lives in client/player.gd and
## client/networked_player_input.gd; target-hit feedback lives in
## client/target_dummy.gd, for the same separation-of-concerns reason.
## Slice 033 adds cosmetic replication of living server-authoritative monsters,
## mirroring the remote-player spawn/position/despawn pattern one-for-one:
## receive_monster_spawn/receive_monster_position are thin RPC targets that
## delegate to the static, parent-injected spawn_monster_representation/
## apply_monster_position seams (mirroring render_sector_blueprint's
## testability style) under a dedicated Monsters container. Hit/death reactions
## and despawn-on-death live in client/monster.gd itself, listening directly to
## combat_event_received, matching client/target_dummy.gd's existing pattern —
## this autoload never decides a hit or death.

signal connection_status_changed(status: String)
signal authoritative_position_received(position: Vector3, last_processed_sequence: int)
signal remote_player_position_received(peer_id: int, position: Vector3)

## Slice 012: emitted on this client only, with the authoritative
## ActionResolution for one of this client's own submitted melee ActionIntent
## sequences, so client/player.gd can reconcile its local prediction.
signal action_resolution_received(sequence: int, result: String, rejection_reason: String, server_tick: int)

## Slice 012: emitted on every client for every confirmed CombatEvent.HIT
## (including the attacker's own), so client/target_dummy.gd can render
## authoritative visual feedback without deciding hit outcomes itself.
signal combat_event_received(kind: String, attacker_peer_id: int, target_id: String, impact_position: Vector3, server_tick: int)

## Slice 013: emitted on every client whenever any peer's melee ActionIntent
## is accepted, carrying that swing's already-public phase timing and facing
## so client/remote_player.gd can time a cosmetic strike-line indicator for
## peers other than the local one (client/player.gd predicts its own timing
## directly and does not need this signal for itself).
signal melee_swing_started_received(peer_id: int, windup_ticks: int, active_ticks: int, facing: Vector3)

## Slice 017: emitted on this client after a server-sent sector blueprint is
## received and re-validated, carrying the sector id, validation outcome, and
## rendered tile/structure counts — client-side replication telemetry and an
## observability seam. Rendering itself happens in the RPC target below; this
## signal only reports what happened, matching this file's relay-only pattern.
signal sector_blueprint_received(sector_id: String, outcome: String, tile_count: int, structure_count: int)

## Slice 019: emitted on the owning client when the server reports the house it
## allocated to this peer from the starting town's fixed pool. Relayed via a
## signal so a HUD element decides how to present it, matching this file's
## relay-only pattern.
signal assigned_house_received(house_id: String)

## Slice 040: emitted on the owning client with the server's authoritative
## outcome for this client's own register/login request — an AccountHandle's
## fields on success (never salt/hash material) or a bounded rejection reason
## on failure. Relayed via a signal so a future login/register screen (spec
## slice 5, not built here) decides how to present it, matching this file's
## relay-only pattern; test/harness code may also listen to this directly.
signal auth_result_received(outcome: String, account_id: String, username: String)

const NetworkConfigScript: Script = preload("res://shared/network_config.gd")
const CombatContractsScript: Script = preload("res://shared/combat_contracts.gd")
const SectorBlueprintSchemaScript: Script = preload("res://shared/sector_blueprint_schema.gd")
const SectorGeometryTranslatorScript: Script = preload("res://client/sector_geometry_translator.gd")
const NETWORKED_PLAYER_SCENE_PATH: String = "res://client/networked_player.tscn"
const REMOTE_PLAYER_SCENE_PATH: String = "res://client/remote_player.tscn"
const REMOTE_PLAYERS_CONTAINER_NAME: String = "RemotePlayers"
const MONSTER_SCENE_PATH: String = "res://client/monster.tscn"
## Slice 033: dedicated child of the Gameplay root holding every living
## monster's cosmetic representation, kept separate so
## FlatPlane/Player/camera/UI/RemotePlayers/SectorGeometry are never disturbed.
const MONSTERS_CONTAINER_NAME: String = "Monsters"
## Slice 017: dedicated child of the Gameplay root holding the rendered
## starting-town geometry, kept separate so FlatPlane/Player/camera/UI are
## never disturbed by a received blueprint.
const SECTOR_GEOMETRY_CONTAINER_NAME: String = "SectorGeometry"

var status: String = "disconnected"
var _peer: ENetMultiplayerPeer
var _next_input_sequence: int = 0
var _own_player_spawn_pending: bool = false
var _pending_sector_blueprint: Dictionary = {}
var _latest_sector_blueprint: Dictionary = {}
var _pending_monster_spawns: Dictionary = {}
var _pending_monster_positions: Dictionary = {}
var _latest_monster_spawns: Dictionary = {}
var _latest_monster_positions: Dictionary = {}


func _ready() -> void:
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


## Slice 034: holds the in-process wgnetstack WireGuard tunnel (a WgNetstack
## GDExtension instance) for the lifetime of the connection when tunnel mode
## is on, so it is not freed while the ENet client uses its loopback port.
var _tunnel: Object = null


## Public seam: starts an ENet client connection attempt to the given host
## and port. When host is left as the default, it resolves via
## NetworkConfig.resolve_client_target_host() (CLI arg, then env var, then
## localhost); port defaults to the shared NetworkConfig port. Non-blocking —
## outcome arrives via the connection_status_changed signal.
##
## Slice 044: intended usage is that the login screen opens the connection and
## stores target_host in PlayerIdentity; gameplay then inherits that connection.
## To avoid a second peer, the login scene should persist until world-entry
## succeeds, then transition to gameplay.tscn. Revisit this seam if e2e patterns
## require connect-before-scene-load.
func connect_to_server(host: String = "", port: int = NetworkConfigScript.SERVER_PORT) -> void:
	var target_host: String = host.strip_edges()
	if target_host.is_empty():
		target_host = NetworkConfigScript.resolve_client_target_host()

	# Slice 034: when PROJECT0_TUNNEL=1, open the in-process userspace WireGuard
	# tunnel and connect to its loopback port instead of target_host directly,
	# so a remote tester needs no WireGuard app and no admin/TUN driver.
	var tunnel_port: int = _maybe_start_tunnel()
	if tunnel_port > 0:
		target_host = NetworkConfigScript.SERVER_ADDRESS
		port = tunnel_port

	_peer = ENetMultiplayerPeer.new()
	var connect_error: Error = _peer.create_client(target_host, port)
	if connect_error != OK:
		_set_status("failed: could not start client (%s)" % connect_error)
		return

	multiplayer.multiplayer_peer = _peer
	_set_status("connecting")

## Public seam: ends the current client session before returning to Character
## selection. No server-side account state is persisted by this client action.
func disconnect_from_server() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	_peer = null
	if _tunnel != null:
		_tunnel.stop()
		_tunnel = null
	_set_status("disconnected")


## Slice 034: when PROJECT0_TUNNEL=1, starts the in-process wgnetstack tunnel
## from PROJECT0_TUNNEL_* env config and returns its loopback UDP port. Returns
## 0 when tunnel mode is off, the GDExtension is not loaded, or startup fails,
## so the caller then connects directly exactly as before. The private key is
## referenced only by file path (PROJECT0_TUNNEL_KEY_PATH); it is never read or
## logged here.
func _maybe_start_tunnel() -> int:
	if OS.get_environment("PROJECT0_TUNNEL") != "1":
		return 0
	if not ClassDB.class_exists("WgNetstack"):
		push_warning("PROJECT0_TUNNEL=1 but the WgNetstack GDExtension is not loaded; connecting directly.")
		return 0
	var config: Dictionary = {
		"client_private_key_path": OS.get_environment("PROJECT0_TUNNEL_KEY_PATH"),
		"client_address": OS.get_environment("PROJECT0_TUNNEL_CLIENT_ADDRESS"),
		"server_public_key": OS.get_environment("PROJECT0_TUNNEL_SERVER_PUBKEY"),
		"server_endpoint": OS.get_environment("PROJECT0_TUNNEL_ENDPOINT"),
		"game_host": OS.get_environment("PROJECT0_TUNNEL_GAME_HOST"),
	}
	var keepalive: String = OS.get_environment("PROJECT0_TUNNEL_KEEPALIVE")
	if keepalive.is_valid_int():
		config["persistent_keepalive_interval"] = keepalive.to_int()
	var mtu: String = OS.get_environment("PROJECT0_TUNNEL_MTU")
	if mtu.is_valid_int():
		config["mtu"] = mtu.to_int()
	_tunnel = ClassDB.instantiate("WgNetstack")
	if _tunnel == null:
		push_error("wgnetstack: could not instantiate WgNetstack; connecting directly.")
		return 0
	var tunnel_port: int = _tunnel.start(config)
	if tunnel_port <= 0:
		push_error("wgnetstack: tunnel failed to start; connecting directly.")
		_tunnel = null
		return 0
	print("wgnetstack tunnel up on 127.0.0.1:%d -> %s via %s" % [tunnel_port, config["game_host"], config["server_endpoint"]])
	return tunnel_port


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
	if not gameplay_root is Node3D:
		_own_player_spawn_pending = true
		return

	var existing: Node = gameplay_root.get_node_or_null("NetworkedPlayer")
	if existing != null:
		return

	var networked_player_scene: PackedScene = load(NETWORKED_PLAYER_SCENE_PATH)
	var networked_player: Node3D = networked_player_scene.instantiate()
	networked_player.name = "NetworkedPlayer"
	gameplay_root.add_child(networked_player)
	_own_player_spawn_pending = false
	_set_status("connected: player spawned")


func render_pending_player_representations() -> void:
	if not _own_player_spawn_pending:
		return
	spawn_own_player_representation()


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


## RPC target called by the server on a client for every currently living
## monster: once per living monster when this client first connects (Slice
## 032, mirroring spawn_remote_player_representation's peer-connect
## replication), and once for a monster that just respawned. Spawns a
## distinct client/monster.gd representation per target_id under a dedicated
## Monsters container — never reusing one shared node for two different
## monsters. Delegates to the static, parent-injected spawn_monster_representation()
## seam below so the idempotent spawn logic stays unit-testable without a live
## multiplayer peer or current_scene.
@rpc("authority", "call_remote", "reliable")
func receive_monster_spawn(target_id: String, start_position: Vector3) -> void:
	_latest_monster_spawns[target_id] = start_position
	_latest_monster_positions[target_id] = start_position
	var gameplay_root: Node = get_tree().current_scene
	if not gameplay_root is Node3D:
		_pending_monster_spawns[target_id] = start_position
		_pending_monster_positions[target_id] = start_position
		return
	var container: Node3D = _get_or_create_monsters_container(gameplay_root)
	spawn_monster_representation(target_id, start_position, container)


## RPC target called by the server on every connected peer each physics frame
## for every currently living monster's authoritative position (Slice 033),
## mirroring receive_remote_player_position's one-way replication broadcast.
## A no-op if this client has no representation for target_id yet (e.g. a
## position broadcast racing ahead of the spawn RPC on an unreliable channel
## is not possible here since both are reliable, but a stale/duplicate
## delivery after despawn must still be safe).
@rpc("authority", "call_remote", "unreliable")
func receive_monster_position(target_id: String, position: Vector3) -> void:
	_latest_monster_positions[target_id] = position
	var gameplay_root: Node = get_tree().current_scene
	if not gameplay_root is Node3D:
		_pending_monster_positions[target_id] = position
		return
	var container: Node = gameplay_root.get_node_or_null(MONSTERS_CONTAINER_NAME)
	if container == null:
		_pending_monster_positions[target_id] = position
		return
	apply_monster_position(target_id, position, container)


func render_pending_monsters() -> void:
	var gameplay_root: Node = get_tree().current_scene
	if not gameplay_root is Node3D:
		return
	var container: Node3D = _get_or_create_monsters_container(gameplay_root)
	for target_id: String in _latest_monster_spawns:
		spawn_monster_representation(target_id, _latest_monster_spawns[target_id], container)
	for target_id: String in _latest_monster_positions:
		apply_monster_position(target_id, _latest_monster_positions[target_id], container)
	_pending_monster_spawns.clear()
	_pending_monster_positions.clear()


## Public seam (static, testable): idempotently creates one node per
## target_id under `parent`, named by monster_node_name(), seeded at
## start_position. A duplicate spawn for an already-represented target_id is a
## no-op, matching spawn_remote_player_representation's idempotency. Static
## and parent-injected so it is unit-testable without a live multiplayer peer,
## current_scene, or NetworkClient instance — mirrors render_sector_blueprint's
## seam style.
static func spawn_monster_representation(target_id: String, start_position: Vector3, parent: Node3D) -> void:
	var node_name: String = monster_node_name(target_id)
	if parent.get_node_or_null(node_name) != null:
		return

	var monster_scene: PackedScene = load(MONSTER_SCENE_PATH)
	var monster: Node3D = monster_scene.instantiate()
	monster.name = node_name
	monster.position = start_position
	parent.add_child(monster)
	monster.call("set_target_id", target_id)


## Public seam (static, testable): forwards an authoritative position update
## to the existing node for target_id under `parent`. A no-op (not an error)
## if no such node exists — e.g. the monster has already been despawned, or
## the position broadcast names an unknown target_id.
static func apply_monster_position(target_id: String, position: Vector3, parent: Node3D) -> void:
	var monster: Node = parent.get_node_or_null(monster_node_name(target_id))
	if monster == null:
		return
	monster.call("set_target_position", position)


## Public seam (static, testable): removes target_id's representation node
## from `parent`, if any. A no-op (not an error) if the node is already gone,
## matching despawn_remote_player_representation's idempotency.
static func despawn_monster_representation(target_id: String, parent: Node3D) -> void:
	var monster: Node = parent.get_node_or_null(monster_node_name(target_id))
	if monster != null:
		monster.queue_free()


static func monster_node_name(target_id: String) -> String:
	return "Monster_%s" % target_id


func _get_or_create_monsters_container(gameplay_root: Node) -> Node3D:
	var container: Node3D = gameplay_root.get_node_or_null(MONSTERS_CONTAINER_NAME) as Node3D
	if container == null:
		container = Node3D.new()
		container.name = MONSTERS_CONTAINER_NAME
		gameplay_root.add_child(container)
	return container


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


## Public seam: allocates the next movement-intent sequence for this client
## session. It lives on the persistent autoload so reloading gameplay after
## Character Select cannot reset the server's monotonic sequence boundary.
func next_input_sequence() -> int:
	var sequence: int = _next_input_sequence
	_next_input_sequence += 1
	return sequence


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


## Public seam: called by the client to submit a melee-strike ActionIntent,
## tagged with the caller-assigned monotonic action sequence number (a
## separate sequence space from submit_input_intent's movement sequence —
## see docs/slices/012-authoritative-melee-strike.md). Reliable (unlike
## movement intent) because an attack request must not be silently dropped;
## the server's own sequence/idempotency handling in
## server/server_player_state.gd still makes a duplicate delivery safe. A
## no-op before this client is connected, matching submit_input_intent.
func submit_action_intent(sequence: int, client_tick: int, action_kind: String, aim_direction: Vector3) -> void:
	if not status.begins_with("connected"):
		return
	rpc_id(1, "receive_action_intent_on_server", sequence, client_tick, action_kind, aim_direction)


## RPC target: runs only on the server's NetworkClient instance, called by a
## connected client via submit_action_intent() above. Reliable/any_peer to
## match the intent-submission seam. Constructs the shared ActionIntent value
## object and forwards it to the sender's own server-only ServerPlayerState
## node with a plain function call, mirroring
## receive_input_intent_on_server's forwarding pattern.
@rpc("any_peer", "call_remote", "reliable")
func receive_action_intent_on_server(sequence: int, client_tick: int, action_kind: String, aim_direction: Vector3) -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()
	var server_player_state: Node = get_tree().root.get_node_or_null("ServerPlayerState_%d" % sender_id)
	if server_player_state == null:
		return
	var intent: Object = CombatContractsScript.ActionIntent.new(sender_id, sequence, client_tick, action_kind, aim_direction)
	server_player_state.apply_action_intent(sender_id, intent)


## RPC target: called by the server on the owning client only, with the
## authoritative ActionResolution for one of that client's own submitted
## melee-strike sequences. Relayed via a signal so client/player.gd decides
## how to reconcile its local prediction, matching
## receive_authoritative_position's separation of concerns.
@rpc("authority", "call_remote", "reliable")
func receive_action_resolution(sequence: int, result: String, rejection_reason: String, server_tick: int) -> void:
	action_resolution_received.emit(sequence, result, rejection_reason, server_tick)


## RPC target: called by the server on every connected peer for every
## confirmed CombatEvent.HIT, including the attacker's own. Relayed via a
## signal so client/target_dummy.gd decides how to render feedback — this
## autoload only relays what the server sends.
@rpc("authority", "call_remote", "reliable")
func receive_combat_event(kind: String, attacker_peer_id: int, target_id: String, impact_position: Vector3, server_tick: int) -> void:
	combat_event_received.emit(kind, attacker_peer_id, target_id, impact_position, server_tick)


## RPC target: called by the server on every connected peer whenever any
## peer's melee ActionIntent is accepted (Slice 013), carrying that swing's
## archetype phase-timing (already public data — see
## shared/combat_contracts.gd's generic_sword_archetype()) and accepted
## facing. Relayed via a signal so client/remote_player.gd decides how to
## render the cosmetic strike-line timing for a peer other than the local
## one, matching this file's existing relay-only pattern.
@rpc("authority", "call_remote", "reliable")
func receive_melee_swing_started(peer_id: int, windup_ticks: int, active_ticks: int, facing: Vector3) -> void:
	melee_swing_started_received.emit(peer_id, windup_ticks, active_ticks, facing)


## RPC target: called by the server on the owning client only, with the house
## structure id the server allocated to this peer (Slice 019). Relayed via a
## signal so a HUD element renders it; the client never chooses its own house.
@rpc("authority", "call_remote", "reliable")
func receive_assigned_house(house_id: String) -> void:
	assigned_house_received.emit(house_id)


## RPC target: called by the server on this specific client once, at connect
## (before the player-spawn RPCs), with the validated starting-town hub
## blueprint Dictionary (Slice 016/017). The client never trusts a network
## payload for scene geometry: it re-validates through the shared schema at
## this boundary, then renders into a dedicated SectorGeometry container so
## the existing FlatPlane/Player/UI stay untouched. An invalid payload renders
## nothing (logged), never partial geometry.
@rpc("authority", "call_remote", "reliable")
func receive_sector_blueprint(blueprint: Dictionary) -> void:
	_latest_sector_blueprint = blueprint.duplicate(true)
	var gameplay_root: Node = get_tree().current_scene
	if not gameplay_root is Node3D:
		_pending_sector_blueprint = blueprint.duplicate(true)
		print("Queued sector blueprint until gameplay scene is ready.")
		return
	if gameplay_root == null:
		push_error("NetworkClient: cannot render sector blueprint, no current_scene")
		return
	_render_sector_blueprint_into_scene(gameplay_root, blueprint)


func render_pending_sector_blueprint() -> void:
	var blueprint: Dictionary = _latest_sector_blueprint
	if blueprint.is_empty() and not _pending_sector_blueprint.is_empty():
		blueprint = _pending_sector_blueprint
	if blueprint.is_empty():
		return
	var gameplay_root: Node = get_tree().current_scene
	if not gameplay_root is Node3D:
		return
	_pending_sector_blueprint = {}
	print("Replaying queued sector blueprint into gameplay scene.")
	_render_sector_blueprint_into_scene(gameplay_root, blueprint)


func _render_sector_blueprint_into_scene(gameplay_root: Node, blueprint: Dictionary) -> void:
	var container: Node3D = _get_or_create_sector_geometry_container(gameplay_root)
	var result: Dictionary = render_sector_blueprint(blueprint, container)
	var sector_id: String = String(blueprint.get("sector_id", ""))
	print("Received sector blueprint (sector_id=%s, outcome=%s, %d tiles, %d structures)." % [sector_id, result["outcome"], result["tile_count"], result["structure_count"]])
	sector_blueprint_received.emit(sector_id, result["outcome"], result["tile_count"], result["structure_count"])


## Public seam (static, testable): re-validates `blueprint` through the shared
## SectorBlueprintSchema and, only if OUTCOME_VALID, translates it into
## `parent` via the Slice 015 translator. Returns
## {outcome: String, tile_count: int, structure_count: int}. Static and
## parent-injected so it is unit-testable without a live multiplayer peer,
## current_scene, or NetworkClient instance. On any non-valid outcome it logs
## and renders nothing (fail closed at the client boundary).
static func render_sector_blueprint(blueprint: Dictionary, parent: Node3D) -> Dictionary:
	var validation: Dictionary = SectorBlueprintSchemaScript.validate(blueprint)
	var outcome: String = validation["outcome"]
	if outcome != SectorBlueprintSchemaScript.OUTCOME_VALID:
		push_error("NetworkClient: rejecting sector blueprint (%s: %s); rendering nothing." % [outcome, validation["detail"]])
		return {"outcome": outcome, "tile_count": 0, "structure_count": 0}
	var validated: Dictionary = validation["blueprint"]
	SectorGeometryTranslatorScript.translate(validated, parent)
	return {
		"outcome": outcome,
		"tile_count": (validated.get("tiles", []) as Array).size(),
		"structure_count": (validated.get("structures", []) as Array).size(),
	}


func _get_or_create_sector_geometry_container(gameplay_root: Node) -> Node3D:
	var container: Node3D = gameplay_root.get_node_or_null(SECTOR_GEOMETRY_CONTAINER_NAME) as Node3D
	if container == null:
		container = Node3D.new()
		container.name = SECTOR_GEOMETRY_CONTAINER_NAME
		gameplay_root.add_child(container)
	return container


## Public seam (test/harness helper, not a UI screen — spec slice 5 owns the
## login/register screens): submits a register request, mirroring
## submit_input_intent's shape. A no-op before this client is connected.
func submit_register(username: String, password: String) -> void:
	if not status.begins_with("connected"):
		return
	rpc_id(1, "receive_register_request_on_server", username, password)


## Public seam (test/harness helper, matching submit_register above): submits
## a login request. A no-op before this client is connected.
func submit_login(username: String, password: String) -> void:
	if not status.begins_with("connected"):
		return
	rpc_id(1, "receive_login_request_on_server", username, password)


## RPC target: runs only on the server's NetworkClient instance, called by a
## connected client via submit_register() above. Reliable/any_peer, matching
## receive_action_intent_on_server's forwarding pattern: forwards to the
## server-only auth dispatch (server_main.gd's AuthService instance) with a
## plain function call rather than a second RPC hop, since both live in the
## same server process. This client never contacts the repository, hasher, or
## session registry directly.
@rpc("any_peer", "call_remote", "reliable")
func receive_register_request_on_server(username: String, password: String) -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()
	var auth_service: Node = get_tree().root.get_node_or_null("AuthService")
	if auth_service == null:
		return
	var result: Dictionary = await auth_service.register(sender_id, username, password)
	_reply_auth_result(sender_id, result)


## RPC target: mirrors receive_register_request_on_server above for
## submit_login().
@rpc("any_peer", "call_remote", "reliable")
func receive_login_request_on_server(username: String, password: String) -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()
	var auth_service: Node = get_tree().root.get_node_or_null("AuthService")
	if auth_service == null:
		return
	var result: Dictionary = await auth_service.login(sender_id, username, password)
	_reply_auth_result(sender_id, result)


## Sends the auth_result RPC back to the requesting peer only, translating
## AuthService's result Dictionary into the wire shape: an AccountHandle's
## fields on success, or a bounded reason with empty account fields on
## rejection. Never forwards a "detail" string (may echo caller-supplied
## input) over the network — only the bounded outcome/reason enum and the
## account identity fields travel to the client.
func _reply_auth_result(peer_id: int, result: Dictionary) -> void:
	var network_client: Node = get_tree().root.get_node_or_null("NetworkClient")
	if network_client == null:
		return
	network_client.rpc_id(
		peer_id,
		"receive_auth_result",
		result["outcome"],
		String(result.get("account_id", "")),
		String(result.get("username", ""))
	)


## RPC target: called by the server on the requesting client only, with the
## authoritative outcome of that client's own register/login request. Relayed
## via a signal so a future login/register screen or test harness decides how
## to present it, matching this file's relay-only pattern (e.g.
## receive_auth_result never itself stores an AccountHandle client-side).
@rpc("authority", "call_remote", "reliable")
func receive_auth_result(outcome: String, account_id: String, username: String) -> void:
	auth_result_received.emit(outcome, account_id, username)


## Slice 042: emitted on the requesting client with the authoritative outcome
## of one of its own Character CRUD requests. `characters` carries the
## client-safe CharacterRecord wire dicts the result produced (all live
## characters for list; the one created/selected character for create/select;
## empty for delete or any rejection). Relayed via a signal so a future
## character-select/create screen or test harness decides how to present it.
signal character_result_received(operation: String, outcome: String, characters: Array)


## Public seam (test/harness helper): submits a list-characters request for
## this client's own authenticated session account. A no-op before connected.
func submit_list_characters() -> void:
	if not status.begins_with("connected"):
		return
	rpc_id(1, "receive_list_characters_request_on_server")


## Public seam (test/harness helper): submits a create-character request.
func submit_create_character(character_name: String, cosmetic: Dictionary) -> void:
	if not status.begins_with("connected"):
		return
	rpc_id(1, "receive_create_character_request_on_server", character_name, cosmetic)


## Public seam (test/harness helper): submits a select-character request.
func submit_select_character(character_id: String) -> void:
	if not status.begins_with("connected"):
		return
	rpc_id(1, "receive_select_character_request_on_server", character_id)


## Public seam (test/harness helper): submits a delete-character request.
func submit_delete_character(character_id: String) -> void:
	if not status.begins_with("connected"):
		return
	rpc_id(1, "receive_delete_character_request_on_server", character_id)


## RPC target: runs only on the server's NetworkClient instance, called by a
## connected client via submit_list_characters() above. Mirrors
## receive_register_request_on_server's forwarding pattern: forwards to the
## server-only CharacterService (server_main.gd's /root/CharacterService
## instance), which derives the account from the peer's own session — the
## client never supplies an account_id.
@rpc("any_peer", "call_remote", "reliable")
func receive_list_characters_request_on_server() -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()
	var character_service: Node = get_tree().root.get_node_or_null("CharacterService")
	if character_service == null:
		return
	_reply_character_result(sender_id, "list", character_service.list_characters(sender_id))


@rpc("any_peer", "call_remote", "reliable")
func receive_create_character_request_on_server(character_name: String, cosmetic: Dictionary) -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()
	var character_service: Node = get_tree().root.get_node_or_null("CharacterService")
	if character_service == null:
		return
	_reply_character_result(sender_id, "create", character_service.create_character(sender_id, character_name, cosmetic))


@rpc("any_peer", "call_remote", "reliable")
func receive_select_character_request_on_server(character_id: String) -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()
	var character_service: Node = get_tree().root.get_node_or_null("CharacterService")
	if character_service == null:
		return
	_reply_character_result(sender_id, "select", character_service.select_character(sender_id, character_id))


@rpc("any_peer", "call_remote", "reliable")
func receive_delete_character_request_on_server(character_id: String) -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()
	var character_service: Node = get_tree().root.get_node_or_null("CharacterService")
	if character_service == null:
		return
	_reply_character_result(sender_id, "delete", character_service.delete_character(sender_id, character_id))


## Sends the character_result RPC back to the requesting peer only, translating
## CharacterService's result Dictionary into the wire shape: the bounded
## outcome plus the client-safe CharacterRecord wire dicts. Never forwards the
## "detail" string (may echo caller-supplied input). list -> every record;
## create/select -> the single record; delete/rejection -> empty array.
func _reply_character_result(peer_id: int, operation: String, result: Dictionary) -> void:
	var network_client: Node = get_tree().root.get_node_or_null("NetworkClient")
	if network_client == null:
		return
	var wire_characters: Array = []
	if result.has("characters"):
		for record: Object in result["characters"]:
			wire_characters.append(record.to_wire_dict())
	elif result.has("character"):
		wire_characters.append((result["character"] as Object).to_wire_dict())
	network_client.rpc_id(peer_id, "receive_character_result", operation, String(result["outcome"]), wire_characters)


## RPC target: called by the server on the requesting client only, with the
## authoritative outcome of that client's own Character CRUD request. Relayed
## via a signal, matching this file's relay-only pattern (it never itself
## stores a CharacterRecord client-side).
@rpc("authority", "call_remote", "reliable")
func receive_character_result(operation: String, outcome: String, characters: Array) -> void:
	character_result_received.emit(operation, outcome, characters)


## Slice 043: emitted on the requesting client with the outcome of its own
## world-entry request. On success `character` is the selected CharacterRecord
## wire dict the authoritative Player was bound to; on rejection it is empty and
## `outcome` carries the bounded reason. The character-select screen transitions
## into gameplay on success.
signal world_entry_received(outcome: String, character: Dictionary)


## Public seam (test/harness helper): requests world entry as this client's
## selected Character. A no-op before connected.
func submit_enter_world() -> void:
	if not status.begins_with("connected"):
		return
	rpc_id(1, "receive_enter_world_request_on_server")


## RPC target: runs on the server's NetworkClient instance. Resolves the peer's
## selected Character via CharacterService (which derives it from the session)
## and binds it to that peer's authoritative ServerPlayerState — both server-only
## /root nodes. Additive: the connect-time anonymous spawn is unchanged, so the
## existing no-auth e2e path still works.
@rpc("any_peer", "call_remote", "reliable")
func receive_enter_world_request_on_server() -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()
	var character_service: Node = get_tree().root.get_node_or_null("CharacterService")
	var player_state: Node = get_tree().root.get_node_or_null("ServerPlayerState_%d" % sender_id)
	if character_service == null or player_state == null:
		return
	var result: Dictionary = character_service.get_selected_character(sender_id)
	if result["outcome"] == "ok":
		var record: Object = result["character"]
		player_state.bind_character(record.character_id, record.display_name, record.cosmetic)
	_reply_enter_world_result(sender_id, result)


## Sends the world-entry result back to the requesting peer only: the bounded
## outcome plus the bound Character's wire dict on success (never the detail
## string).
func _reply_enter_world_result(peer_id: int, result: Dictionary) -> void:
	var network_client: Node = get_tree().root.get_node_or_null("NetworkClient")
	if network_client == null:
		return
	var character_wire: Dictionary = {}
	if result.has("character"):
		character_wire = (result["character"] as Object).to_wire_dict()
	network_client.rpc_id(peer_id, "receive_enter_world_result", String(result["outcome"]), character_wire)


## RPC target: called by the server on the requesting client with its own
## world-entry outcome. Relayed via a signal for the character-select screen or
## test harness to transition into gameplay.
@rpc("authority", "call_remote", "reliable")
func receive_enter_world_result(outcome: String, character: Dictionary) -> void:
	world_entry_received.emit(outcome, character)
