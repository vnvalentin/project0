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

## Slice 171: server-authored population snapshot for the single shared v1
## playtest world. The client caches and relays it; it never edits membership.
signal presence_snapshot_received(snapshot: Dictionary)

## Slice 086: emitted on this client when the server replicates another peer's
## bound Character identity (display name + cosmetic) at that peer's world entry,
## so client/remote_player.gd can label its remote representation. Presentation
## only — this autoload never derives identity itself.
signal remote_player_identity_received(peer_id: int, display_name: String, cosmetic: Dictionary)

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

## Slice 097 (P-013): emitted on the owning client with the server's
## authoritative accepted/rejected resolution for a submitted Canon mutation
## intent. Relay only — this autoload never decides the outcome.
signal canon_mutation_resolution_received(resolution: Dictionary)

## Slice 097 (P-013): emitted on the SERVER only when a client's mutation intent
## arrives, carrying the sender peer id so server_main (which owns the mutation
## service and the peer->Player mapping) resolves it authoritatively.
signal canon_mutation_intent_received(sender_peer_id: int, intent: Dictionary)

## Slice 094: emitted on the owning client when the server replicates its
## Player's authoritative HP (on monster damage or the provisional full-HP
## respawn), so a HUD element can display it. Presentation only — this autoload
## never computes HP itself.
signal player_health_changed(current_hp: int, max_hp: int)

## Slice 127: emitted when the server replicates the local Player's
## presentation-safe Character snapshot at world entry, so a HUD element can
## show the vessel readout. Presentation only — derived graph state, no raw stats.
signal character_snapshot_changed(snapshot: Dictionary)

## Slice 142 (Phase 15 follow-on): emitted when the server replicates the local
## Player's presentation-safe EffectiveMechanicsSnapshot at world entry, so a HUD
## element can show the mechanics readout. Presentation only — normalized graph
## axes + subsystem-safe derived summaries, never raw effective numbers.
signal effective_mechanics_changed(snapshot: Dictionary)

## Slice 146: emitted on the SERVER when a connecting peer submits its version
## handshake, so server_main.gd owns the decision without this node knowing the
## gate's rules. Carries the sender peer id, exactly like the other client→server
## intent signals here.
signal version_handshake_received(peer_id: int, handshake: Dictionary)

## Slice 162 (telemetry map #282): emitted on the SERVER when a client's
## batched telemetry arrives, carrying the sender peer id exactly like the
## other client→server intent signals here. `events` are UNTRUSTED
## `{event_type, schema_version, payload}` Dictionaries — server_main.gd
## resolves every correlation/timing field itself before anything reaches the
## telemetry sink.
signal client_telemetry_batch_received(sender_peer_id: int, events: Array, client_sequence: int)

## Slice 146: emitted on a CLIENT the server refused at the version gate, so the
## UI can tell the tester which version is required and where to get it.
signal version_handshake_rejected(rejection: Dictionary)

## Slice 094: emitted on the owning client the tick its Player was defeated
## (and provisionally respawned at full HP), so a HUD element can flash a cue.
signal player_defeated_received()

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

## Slice 069: emitted on the requesting client with the outcome of an assertion
## request to the login process — the signed token on success (a bearer credential
## for this peer only), empty on a bounded failure. Relayed via a signal so the
## client carries the token to the game server, matching this file's relay-only
## pattern.
signal assertion_result_received(outcome: String, assertion: String)

## Slice 069: emitted on the requesting client with the outcome of presenting an
## assertion to the game server (session established from the validated token, or
## a bounded rejection that binds nothing).
signal session_established_received(outcome: String)
## Slice 175: result of presenting a Nakama bearer token to the game server.
signal nakama_session_established_received(outcome: String)

## Slice 087: emitted on the requesting client with the outcome of a resume-token
## request (a longer-lived account assertion the client keeps to re-establish a
## login session on return, without re-typing the password).
signal resume_assertion_result_received(outcome: String, assertion: String)

## Slice 087: emitted when perform_return_to_character_select finishes. "ok" when
## the login session was re-established from the resume token (the Character list
## is now available); any other value means the caller should fall back to the
## login screen to re-authenticate.
signal return_to_character_select_finished(outcome: String)

const NetworkConfigScript: Script = preload("res://shared/network_config.gd")
const NakamaGameplayBridgeClientScript: Script = preload("res://client/nakama_gameplay_bridge_client.gd")
const NakamaScript: Script = preload("res://addons/com.heroiclabs.nakama/Nakama.gd")
const CombatContractsScript: Script = preload("res://shared/combat_contracts.gd")
const PlayerCombatContractsScript: Script = preload("res://shared/player_combat_contracts.gd")
const SectorBlueprintSchemaScript: Script = preload("res://shared/sector_blueprint_schema.gd")
const SectorGeometryTranslatorScript: Script = preload("res://client/sector_geometry_translator.gd")
const EffectiveMechanicsSnapshotScript: Script = preload("res://shared/effective_mechanics_snapshot.gd")
const VersionHandshakeScript: Script = preload("res://shared/version_handshake.gd")
const TelemetryBatchQueueScript: Script = preload("res://client/telemetry_batch_queue.gd")
const NakamaPresenceScript: Script = preload("res://shared/nakama_presence.gd")

const UPDATE_REJECTION_PATH_ENV_VAR: String = "PROJECT0_UPDATE_REJECTION_PATH"
const UPDATE_REQUIRED_EXIT_CODE: int = 20

## Slice 069: server-owned validity window for an assertion minted on request.
## The login process supplies the clock and this bound; the client supplies
## neither.
const ASSERTION_REQUEST_TTL_SECONDS: int = 300

## Slice 087: server-owned validity window for the account resume token, which
## outlives a play session so the in-world "Character Select" button can return
## to the roster without re-login. Resolved on the login process from
## PROJECT0_RESUME_TTL_SECONDS (default 1 hour), clamped to a safe range so a
## malformed or extreme override cannot mint a zero-length or unbounded token.
const RESUME_ASSERTION_DEFAULT_TTL_SECONDS: int = 3600
const RESUME_ASSERTION_MIN_TTL_SECONDS: int = 60
const RESUME_ASSERTION_MAX_TTL_SECONDS: int = 86400
const NETWORKED_PLAYER_SCENE_PATH: String = "res://client/networked_player.tscn"
const REMOTE_PLAYER_SCENE_PATH: String = "res://client/remote_player.tscn"
const REMOTE_PLAYERS_CONTAINER_NAME: String = "RemotePlayers"
const MONSTER_SCENE_PATH: String = "res://client/monster.tscn"
## Slice 033: dedicated child of the Gameplay root holding every living
## monster's cosmetic representation, kept separate so
## FlatPlane/Player/camera/UI/RemotePlayers/SectorGeometry are never disturbed.
const MONSTERS_CONTAINER_NAME: String = "Monsters"
## Slice 131: town NPC cosmetic representation. A script (not a scene) built
## procedurally, and a dedicated Gameplay-root child holding every live town NPC,
## kept separate like the Monsters container.
const TOWN_NPC_SCRIPT_PATH: String = "res://client/town_npc.gd"
const TOWN_NPCS_CONTAINER_NAME: String = "TownNpcs"
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
## Slice 131: town NPC replication state, mirroring the monster dictionaries.
var _pending_town_npc_spawns: Dictionary = {}
var _pending_town_npc_positions: Dictionary = {}
var _latest_town_npc_spawns: Dictionary = {}
var _latest_town_npc_positions: Dictionary = {}
## Slice 086: latest replicated Character identity per remote peer id, kept so a
## RemotePlayer node spawned after (or slightly before) its identity RPC still
## gets labeled. Cleared per peer on despawn.
var _remote_identities: Dictionary = {}
## Latest replicated start position per remote peer id, kept so a spawn RPC that
## arrives before this client's gameplay scene is ready (e.g. the late-joiner is
## still on the login/character screen mid-handoff) is replayed once gameplay
## loads, instead of being lost. Cleared per peer on despawn.
var _latest_remote_players: Dictionary = {}
## Slice 087: the account resume token obtained at handoff, kept in memory so the
## in-world return can re-establish a login session without re-authenticating.
var _resume_assertion: String = ""
var _nakama_gameplay_bridge: Object = null

## Slice 094: latest replicated authoritative HP, retained so a HUD element
## created after the first receive_health_update (scene-entry ordering) reads
## the current value. Defaults to the provisional full pool.
var latest_current_hp: int = PlayerCombatContractsScript.PLAYER_MAX_HP
var latest_max_hp: int = PlayerCombatContractsScript.PLAYER_MAX_HP

## Slice 127: latest replicated presentation-safe Character snapshot, retained so
## a HUD element created after it first arrives still reads the current value.
var latest_character_snapshot: Dictionary = {}

## Slice 142: latest replicated presentation-safe EffectiveMechanicsSnapshot,
## retained so a HUD element created after it first arrives still reads it.
var latest_effective_mechanics: Dictionary = {}

## Slice 146: the server's version-gate rejection, if this client was refused.
## Retained so UI created after the refusal still knows why.
var latest_version_rejection: Dictionary = {}

## Slice 171: latest server-authored shared-world presence, retained so UI or a
## later Nakama socket adapter can read the current population after scene load.
var latest_presence_snapshot: Dictionary = {}

## Slice 162: this client's outgoing telemetry batching queue and its own
## client-local batch sequence counter (for server-side dedup/ordering
## diagnostics only — never a trust boundary).
var _telemetry_queue: TelemetryBatchQueue = null
var _telemetry_sequence: int = 0


func _ready() -> void:
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_telemetry_queue = TelemetryBatchQueueScript.new(Time.get_ticks_msec())


## Slice 162: enqueues one telemetry event for the next periodic flush. No-op
## before this autoload has initialized its queue (should never happen once
## _ready() has run). Callers supply only `event_type`/`schema_version`/
## `payload` — every trust-sensitive field (peer id, character id, timestamp)
## is resolved server-side, never here.
func queue_telemetry_event(event_type: String, schema_version: int, payload: Dictionary) -> void:
	if _telemetry_queue == null:
		return
	_telemetry_queue.enqueue({"event_type": event_type, "schema_version": schema_version, "payload": payload})


## Flushes the pending telemetry batch to the server once the queue's flush
## interval has elapsed. A no-op while disconnected (nothing to send to) or
## while nothing is pending. This autoload runs on both client and server (the
## server's own NetworkClient node never connects, so `status` never begins
## with "connected" there and this is always a cheap no-op on that side).
func _process(_delta: float) -> void:
	if _telemetry_queue == null or not status.begins_with("connected"):
		return
	var now_msec: int = Time.get_ticks_msec()
	if not _telemetry_queue.should_flush(now_msec):
		return
	var batch: Array[Dictionary] = _telemetry_queue.take_batch(now_msec)
	if batch.is_empty():
		return
	_telemetry_sequence += 1
	rpc_id(1, "receive_client_telemetry_batch_on_server", batch, _telemetry_sequence)


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
	# Slice 146: the version handshake is the FIRST thing a client says. The server
	# admits nothing until it accepts this, so it must precede every other RPC.
	rpc_id(1, "receive_version_handshake_on_server", VersionHandshakeScript.request())


func _on_connection_failed() -> void:
	_set_status("failed: connection refused")


func _on_server_disconnected() -> void:
	_set_status("disconnected")


## Slice 171: accepts only a valid server-authored snapshot. Invalid payloads
## are ignored at the client boundary and never become cached presence state.
@rpc("authority", "call_remote", "reliable")
func receive_presence_snapshot(snapshot: Dictionary) -> void:
	var validation: Dictionary = NakamaPresenceScript.validate(snapshot)
	if validation["outcome"] != NakamaPresenceScript.OUTCOME_OK:
		push_warning("NetworkClient: rejected presence snapshot (%s)." % validation["outcome"])
		return
	latest_presence_snapshot = snapshot.duplicate(true)
	presence_snapshot_received.emit(latest_presence_snapshot)


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
	_latest_remote_players[peer_id] = start_position
	var gameplay_root: Node = get_tree().current_scene
	if not gameplay_root is Node3D:
		# Deferred: the gameplay scene is not ready yet (a late-joiner is still on
		# the login/character screen mid-handoff). render_pending_remote_players()
		# replays it when gameplay loads, so the existing peer is not lost.
		return
	_spawn_remote_player_into(peer_id, start_position, gameplay_root)


## Instantiates one RemotePlayer node per peer id under the RemotePlayers
## container, seeded at start_position and labeled from any cached identity.
## Idempotent: a second call for an already-represented peer is a no-op.
func _spawn_remote_player_into(peer_id: int, start_position: Vector3, gameplay_root: Node) -> void:
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
	# Slice 086: if this peer's Character identity already arrived (or was cached
	# from a prior spawn), apply it now so a late spawn is still labeled.
	if _remote_identities.has(peer_id):
		var identity: Dictionary = _remote_identities[peer_id]
		remote_player.call("set_character_identity", String(identity.get("display_name", "")), identity.get("cosmetic", {}))


## Replays deferred remote-Player spawns once the gameplay scene is ready
## (called from connection_status.gd, mirroring render_pending_monsters), so a
## late-joiner sees peers whose spawn RPCs arrived before its scene existed.
func render_pending_remote_players() -> void:
	var gameplay_root: Node = get_tree().current_scene
	if not gameplay_root is Node3D:
		return
	for peer_id: int in _latest_remote_players:
		_spawn_remote_player_into(peer_id, _latest_remote_players[peer_id], gameplay_root)


## RPC target called by the server on every remaining peer when a peer
## disconnects (Slice 007). Removes that peer's remote representation only —
## other peers' remote nodes and this client's own Player/NetworkedPlayer are
## untouched. A no-op (not an error) if the node is already gone, so this
## stays safe to call even if cleanup already happened.
@rpc("authority", "call_remote", "reliable")
func despawn_remote_player_representation(peer_id: int) -> void:
	# Clear the deferred/identity caches first, before any early return, so a
	# peer that departs while this client's gameplay scene is not ready can never
	# be resurrected by render_pending_remote_players().
	_remote_identities.erase(peer_id)
	_latest_remote_players.erase(peer_id)
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


## RPC target (Slice 131): spawns a town NPC representation, mirroring
## receive_monster_spawn. Retained in _latest_town_npc_spawns so a scene-entry
## race defers to render_pending_town_npcs().
@rpc("authority", "call_remote", "reliable")
func receive_town_npc_spawn(npc_id: String, start_position: Vector3) -> void:
	_latest_town_npc_spawns[npc_id] = start_position
	_latest_town_npc_positions[npc_id] = start_position
	var gameplay_root: Node = get_tree().current_scene
	if not gameplay_root is Node3D:
		_pending_town_npc_spawns[npc_id] = start_position
		_pending_town_npc_positions[npc_id] = start_position
		return
	spawn_town_npc_representation(npc_id, start_position, _get_or_create_town_npcs_container(gameplay_root))


## RPC target (Slice 131): forwards a town NPC's authoritative position each tick,
## mirroring receive_monster_position.
@rpc("authority", "call_remote", "unreliable")
func receive_town_npc_position(npc_id: String, position: Vector3) -> void:
	_latest_town_npc_positions[npc_id] = position
	var gameplay_root: Node = get_tree().current_scene
	if not gameplay_root is Node3D:
		return
	apply_town_npc_position(npc_id, position, _get_or_create_town_npcs_container(gameplay_root))


## RPC target (Slice 131): removes a town NPC representation when the server
## reports it left the world (delayed replacement / promotion).
@rpc("authority", "call_remote", "reliable")
func receive_town_npc_despawn(npc_id: String) -> void:
	_latest_town_npc_spawns.erase(npc_id)
	_latest_town_npc_positions.erase(npc_id)
	_pending_town_npc_spawns.erase(npc_id)
	_pending_town_npc_positions.erase(npc_id)
	var gameplay_root: Node = get_tree().current_scene
	if not gameplay_root is Node3D:
		return
	despawn_town_npc_representation(npc_id, _get_or_create_town_npcs_container(gameplay_root))


## Flushes town NPC spawns/positions received before the gameplay scene existed,
## mirroring render_pending_monsters (called from connection_status.gd).
func render_pending_town_npcs() -> void:
	var gameplay_root: Node = get_tree().current_scene
	if not gameplay_root is Node3D:
		return
	var container: Node3D = _get_or_create_town_npcs_container(gameplay_root)
	for npc_id: String in _latest_town_npc_spawns:
		spawn_town_npc_representation(npc_id, _latest_town_npc_spawns[npc_id], container)
	for npc_id: String in _latest_town_npc_positions:
		apply_town_npc_position(npc_id, _latest_town_npc_positions[npc_id], container)
	_pending_town_npc_spawns.clear()
	_pending_town_npc_positions.clear()


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


## Public seam (static, testable): idempotently spawns one town NPC node per
## npc_id under `parent`, mirroring spawn_monster_representation.
static func spawn_town_npc_representation(npc_id: String, start_position: Vector3, parent: Node3D) -> void:
	var node_name: String = town_npc_node_name(npc_id)
	if parent.get_node_or_null(node_name) != null:
		return
	var npc: Node3D = load(TOWN_NPC_SCRIPT_PATH).new()
	npc.name = node_name
	npc.position = start_position
	parent.add_child(npc)
	npc.call("set_npc_id", npc_id)


## Public seam (static, testable): forwards a position update to the existing
## town NPC node, or a no-op if none exists.
static func apply_town_npc_position(npc_id: String, position: Vector3, parent: Node3D) -> void:
	var npc: Node = parent.get_node_or_null(town_npc_node_name(npc_id))
	if npc == null:
		return
	npc.call("set_target_position", position)


## Public seam (static, testable): removes a town NPC node, or a no-op if gone.
static func despawn_town_npc_representation(npc_id: String, parent: Node3D) -> void:
	var npc: Node = parent.get_node_or_null(town_npc_node_name(npc_id))
	if npc != null:
		npc.queue_free()


static func town_npc_node_name(npc_id: String) -> String:
	return "TownNpc_%s" % npc_id


func _get_or_create_town_npcs_container(gameplay_root: Node) -> Node3D:
	var container: Node3D = gameplay_root.get_node_or_null(TOWN_NPCS_CONTAINER_NAME) as Node3D
	if container == null:
		container = Node3D.new()
		container.name = TOWN_NPCS_CONTAINER_NAME
		gameplay_root.add_child(container)
	return container


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
	if _nakama_gameplay_bridge != null and _nakama_gameplay_bridge.available():
		_nakama_gameplay_bridge.submit_input({"move_x": intent.x, "move_z": intent.y}, sequence)
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


## RPC target: called by the server on every other peer when a peer binds its
## selected Character at world entry (Slice 086), with that peer's id, Character
## display name, and cosmetic. Cached (so a not-yet-spawned RemotePlayer still
## gets labeled) and relayed via a signal for the remote representation's own
## node script (client/remote_player.gd) to render — this autoload never
## derives or trusts identity itself.
@rpc("authority", "call_remote", "reliable")
func receive_remote_player_identity(peer_id: int, display_name: String, cosmetic: Dictionary) -> void:
	_remote_identities[peer_id] = {"display_name": display_name, "cosmetic": cosmetic}
	remote_player_identity_received.emit(peer_id, display_name, cosmetic)


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
	if _nakama_gameplay_bridge != null and _nakama_gameplay_bridge.available():
		_nakama_gameplay_bridge.submit_input({"action_kind": action_kind, "aim_x": aim_direction.x, "aim_y": aim_direction.y, "aim_z": aim_direction.z}, sequence)
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


## Slice 097 (P-013): public seam — the client submits a Canon mutation intent
## (built via CanonMutationIntent) to the server. Reliable; a no-op before this
## client is connected. The server owns the outcome; this autoload only ferries
## the intent and relays the resolution below.
func submit_canon_mutation_intent(intent: Dictionary) -> void:
	if not status.begins_with("connected"):
		return
	rpc_id(1, "receive_canon_mutation_intent_on_server", intent)


## RPC target: runs only on the server, called by a connected client via
## submit_canon_mutation_intent(). Emits the sender peer id so server_main
## resolves it against that peer's authenticated Player identity.
@rpc("any_peer", "call_remote", "reliable")
func receive_canon_mutation_intent_on_server(intent: Dictionary) -> void:
	canon_mutation_intent_received.emit(multiplayer.get_remote_sender_id(), intent)


## RPC target: runs only on the server, called by a connected client via the
## `_process()` flush loop above (~250ms cadence). `events` are UNTRUSTED
## `{event_type, schema_version, payload}` Dictionaries; every correlation/
## timing field is resolved server-side (see server_main.gd's
## client_telemetry_batch_received handler) — this autoload only relays the
## sender peer id, exactly like the other client→server intent RPCs here.
## Unreliable per decision #284: telemetry is diagnostic, dropped packets are
## acceptable.
@rpc("any_peer", "call_remote", "unreliable")
func receive_client_telemetry_batch_on_server(events: Array, client_sequence: int) -> void:
	client_telemetry_batch_received.emit(multiplayer.get_remote_sender_id(), events, client_sequence)


## RPC target: called by the server on the submitting client only, with the
## authoritative accepted/rejected resolution. Relayed via a signal.
@rpc("authority", "call_remote", "reliable")
func receive_canon_mutation_resolution(resolution: Dictionary) -> void:
	canon_mutation_resolution_received.emit(resolution)


## RPC target: called by the server on every connected peer for every
## confirmed CombatEvent.HIT, including the attacker's own. Relayed via a
## signal so client/target_dummy.gd decides how to render feedback — this
## autoload only relays what the server sends.
@rpc("authority", "call_remote", "reliable")
func receive_combat_event(kind: String, attacker_peer_id: int, target_id: String, impact_position: Vector3, server_tick: int) -> void:
	combat_event_received.emit(kind, attacker_peer_id, target_id, impact_position, server_tick)


## RPC target (Slice 094): called by the server on the owning client only with
## its Player's current authoritative HP. Retained in latest_current_hp/
## latest_max_hp so a HUD created after this first arrives (scene-entry
## ordering) still reads the current value, and relayed via a signal so the HUD
## decides how to render it — this autoload never computes HP.
@rpc("authority", "call_remote", "reliable")
func receive_health_update(current_hp: int, max_hp: int) -> void:
	latest_current_hp = current_hp
	latest_max_hp = max_hp
	player_health_changed.emit(current_hp, max_hp)


## RPC target (Slice 127): called by the server on the owning client with its
## Player's presentation-safe Character snapshot. Retained in
## latest_character_snapshot so a HUD created after this first arrives still
## reads it, and relayed via a signal so the HUD decides how to render it — this
## autoload never derives Character state.
@rpc("authority", "call_remote", "reliable")
func receive_character_snapshot(snapshot: Dictionary) -> void:
	latest_character_snapshot = snapshot
	character_snapshot_changed.emit(snapshot)


## RPC target (Slice 142): called by the server on the owning client with its
## Player's presentation-safe EffectiveMechanicsSnapshot. Fail-closed: the
## untrusted wire is validated with
## EffectiveMechanicsSnapshot.from_presentation_wire, and a malformed,
## unsupported-version, or out-of-bounds payload is dropped (never stored or
## relayed). A valid snapshot is retained in latest_effective_mechanics so a HUD
## created after it first arrives still reads it, and relayed via a signal so the
## HUD decides how to render it — this autoload never derives mechanics state.
@rpc("authority", "call_remote", "reliable")
func receive_effective_mechanics(snapshot: Dictionary) -> void:
	var validated: Dictionary = EffectiveMechanicsSnapshotScript.from_presentation_wire(snapshot)
	if validated["outcome"] != EffectiveMechanicsSnapshotScript.OUTCOME_OK:
		return
	latest_effective_mechanics = validated["snapshot"]
	effective_mechanics_changed.emit(latest_effective_mechanics)


## RPC target (Slice 146): runs only on the server, called by a connecting client
## with its declared build version. Emits the sender peer id so server_main.gd
## decides the gate — this node never judges a version itself.
@rpc("any_peer", "call_remote", "reliable")
func receive_version_handshake_on_server(handshake: Dictionary) -> void:
	version_handshake_received.emit(multiplayer.get_remote_sender_id(), handshake)


## RPC target (Slice 146): called by the server on a client it refused at the
## version gate, just before disconnecting it. Retained and relayed so the UI can
## show which version is required and where to get it.
@rpc("authority", "call_remote", "reliable")
func receive_version_handshake_rejected(rejection: Dictionary) -> void:
	latest_version_rejection = rejection
	_set_status("refused: %s" % String(rejection.get("outcome", "UNKNOWN")))
	version_handshake_rejected.emit(rejection)
	var handoff_path: String = OS.get_environment(UPDATE_REJECTION_PATH_ENV_VAR).strip_edges()
	if handoff_path.is_empty():
		return
	var temporary_path: String = handoff_path + ".tmp"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(rejection))
	file.close()
	DirAccess.rename_absolute(temporary_path, handoff_path)
	get_tree().quit(UPDATE_REQUIRED_EXIT_CODE)


## RPC target (Slice 094): called by the server on the owning client the tick
## its Player was defeated (then provisionally respawned at full HP). Relayed
## via a signal so the HUD can flash a brief cue.
@rpc("authority", "call_remote", "reliable")
func receive_player_defeated() -> void:
	player_defeated_received.emit()


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
	var login_gateway: Node = get_tree().root.get_node_or_null("LoginGateway")
	if login_gateway == null:
		return
	var result: Dictionary = await login_gateway.register(sender_id, username, password)
	_reply_auth_result(sender_id, result)


## RPC target: mirrors receive_register_request_on_server above for
## submit_login().
@rpc("any_peer", "call_remote", "reliable")
func receive_login_request_on_server(username: String, password: String) -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()
	var login_gateway: Node = get_tree().root.get_node_or_null("LoginGateway")
	if login_gateway == null:
		return
	var result: Dictionary = await login_gateway.login(sender_id, username, password)
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
	var login_gateway: Node = get_tree().root.get_node_or_null("LoginGateway")
	if login_gateway == null:
		return
	_reply_character_result(sender_id, "list", login_gateway.list_characters(sender_id))


@rpc("any_peer", "call_remote", "reliable")
func receive_create_character_request_on_server(character_name: String, cosmetic: Dictionary) -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()
	var login_gateway: Node = get_tree().root.get_node_or_null("LoginGateway")
	if login_gateway == null:
		return
	_reply_character_result(sender_id, "create", login_gateway.create_character(sender_id, character_name, cosmetic))


@rpc("any_peer", "call_remote", "reliable")
func receive_select_character_request_on_server(character_id: String) -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()
	var login_gateway: Node = get_tree().root.get_node_or_null("LoginGateway")
	if login_gateway == null:
		return
	_reply_character_result(sender_id, "select", login_gateway.select_character(sender_id, character_id))


@rpc("any_peer", "call_remote", "reliable")
func receive_delete_character_request_on_server(character_id: String) -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()
	var login_gateway: Node = get_tree().root.get_node_or_null("LoginGateway")
	if login_gateway == null:
		return
	_reply_character_result(sender_id, "delete", login_gateway.delete_character(sender_id, character_id))


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


## Slice 069: assertion handoff — request half (client -> login process).
## Public seam (test/harness helper): asks the login process to mint a signed
## session assertion for this client's authenticated session. A no-op before
## connected.
func submit_request_assertion() -> void:
	if not status.begins_with("connected"):
		return
	rpc_id(1, "receive_assertion_request_on_server")


## RPC target: runs only on the login process's NetworkClient instance. Mints a
## selected-Character assertion, falling back to an account-only assertion when
## no Character is selected, using the SERVER's authoritative clock and a bounded
## TTL (the client supplies neither). Forwards to /root/LoginGateway (which holds
## the issuer) exactly like the register/character receivers.
@rpc("any_peer", "call_remote", "reliable")
func receive_assertion_request_on_server() -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()
	var login_gateway: Node = get_tree().root.get_node_or_null("LoginGateway")
	if login_gateway == null:
		return
	var now_unix: int = int(Time.get_unix_time_from_system())
	var result: Dictionary = login_gateway.issue_character_assertion(sender_id, now_unix, ASSERTION_REQUEST_TTL_SECONDS)
	if result["outcome"] == "no_character":
		result = login_gateway.issue_account_assertion(sender_id, now_unix, ASSERTION_REQUEST_TTL_SECONDS)
	_reply_assertion(sender_id, result)


## Sends the assertion_result RPC back to the requesting peer only: the bounded
## outcome plus the signed token on success (empty otherwise). The token is a
## bearer credential for this peer, sent over that peer's own connection.
func _reply_assertion(peer_id: int, result: Dictionary) -> void:
	var network_client: Node = get_tree().root.get_node_or_null("NetworkClient")
	if network_client == null:
		return
	network_client.rpc_id(peer_id, "receive_assertion_result", String(result["outcome"]), String(result.get("assertion", "")))


## RPC target: called by the login process on the requesting client only, with
## the outcome of its assertion request. Relayed via a signal, matching this
## file's relay-only pattern.
@rpc("authority", "call_remote", "reliable")
func receive_assertion_result(outcome: String, assertion: String) -> void:
	assertion_result_received.emit(outcome, assertion)


## Slice 087: resume-token request (client -> login process). Asks the login
## process for a longer-lived account assertion the client keeps to re-establish
## a login session on return. A no-op before connected.
func submit_request_resume_assertion() -> void:
	if not status.begins_with("connected"):
		return
	rpc_id(1, "receive_resume_assertion_request_on_server")


## RPC target: runs only on the login process's NetworkClient instance. Mints an
## account-only assertion with the resume TTL (server clock + server-resolved
## bound; the client supplies neither) so it survives a play session. Forwards to
## /root/LoginGateway (which holds the issuer).
@rpc("any_peer", "call_remote", "reliable")
func receive_resume_assertion_request_on_server() -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()
	var login_gateway: Node = get_tree().root.get_node_or_null("LoginGateway")
	if login_gateway == null:
		return
	var now_unix: int = int(Time.get_unix_time_from_system())
	var result: Dictionary = login_gateway.issue_account_assertion(sender_id, now_unix, resolve_resume_ttl_seconds())
	_reply_resume_assertion(sender_id, result)


## Sends the resume_assertion_result RPC back to the requesting peer only: the
## bounded outcome plus the signed token on success (empty otherwise).
func _reply_resume_assertion(peer_id: int, result: Dictionary) -> void:
	var network_client: Node = get_tree().root.get_node_or_null("NetworkClient")
	if network_client == null:
		return
	network_client.rpc_id(peer_id, "receive_resume_assertion_result", String(result["outcome"]), String(result.get("assertion", "")))


## RPC target: called by the login process on the requesting client only, with
## the outcome of its resume-token request. Relayed via a signal.
@rpc("authority", "call_remote", "reliable")
func receive_resume_assertion_result(outcome: String, assertion: String) -> void:
	resume_assertion_result_received.emit(outcome, assertion)


## Slice 087: resolves the resume-token TTL (seconds) on the login process from
## PROJECT0_RESUME_TTL_SECONDS, defaulting to one hour and clamping to a safe
## range so a malformed or extreme override cannot mint a zero-length or
## unbounded credential.
static func resolve_resume_ttl_seconds() -> int:
	var raw: String = OS.get_environment("PROJECT0_RESUME_TTL_SECONDS").strip_edges()
	if not raw.is_valid_int():
		return RESUME_ASSERTION_DEFAULT_TTL_SECONDS
	return clampi(raw.to_int(), RESUME_ASSERTION_MIN_TTL_SECONDS, RESUME_ASSERTION_MAX_TTL_SECONDS)


## Slice 069: assertion handoff — present half (client -> game process).
## Public seam (test/harness helper): presents a signed assertion (obtained from
## the login process) to the game server to establish this peer's session without
## the game server reading the accounts DB. A no-op before connected.
func submit_present_assertion(assertion: String) -> void:
	if not status.begins_with("connected"):
		return
	rpc_id(1, "receive_assertion_presentation_on_server", assertion)


## RPC target: runs only on the game process's NetworkClient instance. Establishes
## the peer's session purely from the validated assertion, using the SERVER's
## authoritative clock. Fail-closed: a token that is tampered, expired, or signed
## with a different secret binds nothing. Forwards to /root/LoginGateway (which
## holds the validator).
@rpc("any_peer", "call_remote", "reliable")
func receive_assertion_presentation_on_server(assertion: String) -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()
	var login_gateway: Node = get_tree().root.get_node_or_null("LoginGateway")
	if login_gateway == null:
		return
	var now_unix: int = int(Time.get_unix_time_from_system())
	var result: Dictionary = login_gateway.establish_session_from_assertion(sender_id, assertion, now_unix)
	_reply_session_established(sender_id, result)


## Sends the session_established RPC back to the requesting peer only: the bounded
## outcome (never a "detail" string, which could echo input).
func _reply_session_established(peer_id: int, result: Dictionary) -> void:
	var network_client: Node = get_tree().root.get_node_or_null("NetworkClient")
	if network_client == null:
		return
	network_client.rpc_id(peer_id, "receive_session_established_result", String(result["outcome"]))


## RPC target: called by the game process on the requesting client only, with the
## outcome of presenting its assertion. Relayed via a signal.
@rpc("authority", "call_remote", "reliable")
func receive_session_established_result(outcome: String) -> void:
	session_established_received.emit(outcome)


## Slice 175: presents the Nakama bearer token to the game server. The server
## validates it against Nakama and binds only the returned identity.
func submit_nakama_session(token: String) -> void:
	if not status.begins_with("connected"):
		return
	rpc_id(1, "receive_nakama_session_on_server", token)


@rpc("any_peer", "call_remote", "reliable")
func receive_nakama_session_on_server(token: String) -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()
	var validator: Node = get_tree().root.get_node_or_null("NakamaSessionValidator")
	var gateway: Node = get_tree().root.get_node_or_null("LoginGateway")
	if validator == null or gateway == null:
		_reply_nakama_session(sender_id, "unavailable")
		return
	var validated: Dictionary = await validator.validate(token)
	var result: Dictionary = gateway.bind_validated_nakama_session(sender_id, validated)
	_reply_nakama_session(sender_id, String(result.get("outcome", "validation_failed")))


func _reply_nakama_session(peer_id: int, outcome: String) -> void:
	var network_client: Node = get_tree().root.get_node_or_null("NetworkClient")
	if network_client != null:
		network_client.rpc_id(peer_id, "receive_nakama_session_result", outcome)


@rpc("authority", "call_remote", "reliable")
func receive_nakama_session_result(outcome: String) -> void:
	nakama_session_established_received.emit(outcome)


func _start_nakama_gameplay(match_id: String) -> void:
	if not NetworkConfigScript.client_nakama_gameplay_enabled() or PlayerIdentity.nakama_auth_token.is_empty() or match_id.is_empty():
		return
	var nakama: Node = NakamaScript.new()
	add_child(nakama)
	var bridge: Object = NakamaGameplayBridgeClientScript.new()
	var connected: Dictionary = await bridge.connect_shared_match(nakama, PlayerIdentity.nakama_auth_token, match_id)
	if connected.get("outcome", "") != "ok":
		nakama.queue_free()
		return
	if bridge.attach(connected["socket"], String(connected["match_id"]), PlayerIdentity.nakama_user_id, PlayerIdentity.selected_character_id)["outcome"] != "ok":
		nakama.queue_free()
		return
	bridge.state_received.connect(_on_nakama_state)
	bridge.error_received.connect(_on_nakama_error)
	_nakama_gameplay_bridge = bridge


func _on_nakama_state(message: Dictionary) -> void:
	var payload: Dictionary = message.get("payload", {})
	var position_wire: Dictionary = payload.get("position", {})
	var position: Vector3 = Vector3(float(position_wire.get("x", 0.0)), float(position_wire.get("y", 0.0)), float(position_wire.get("z", 0.0)))
	authoritative_position_received.emit(position, int(message.get("sequence", 0)))
	if payload.has("action_result"):
		action_resolution_received.emit(int(message.get("sequence", 0)), String(payload["action_result"]), String(payload.get("action_rejection_reason", "")), int(payload.get("server_tick", 0)))


func _on_nakama_error(_message: Dictionary) -> void:
	_nakama_gameplay_bridge = null


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
	var login_gateway: Node = get_tree().root.get_node_or_null("LoginGateway")
	var player_state: Node = get_tree().root.get_node_or_null("ServerPlayerState_%d" % sender_id)
	if login_gateway == null or player_state == null:
		return
	var result: Dictionary = login_gateway.get_selected_character(sender_id)
	if result["outcome"] == "ok":
		var record: Object = result["character"]
		player_state.bind_character(record.character_id, record.display_name, record.cosmetic)
		var ticket_service: Object = get_tree().root.get_meta("world_entry_tickets", null)
		var relay: Node = get_tree().root.get_node_or_null("NakamaGameplayRelay")
		if ticket_service != null and relay != null and relay.available():
			var issued: Dictionary = ticket_service.issue(sender_id, int(Time.get_unix_time_from_system()), 30)
			if issued.get("outcome", "") == "ok":
				var consumed: Dictionary = ticket_service.consume(sender_id, String(issued["ticket"]), int(Time.get_unix_time_from_system()))
				if consumed.get("outcome", "") == "ok":
					var identity: Dictionary = login_gateway.get_presence_identity(sender_id)
					relay.bind_world_entry(sender_id, String(identity.get("account_id", "")), record.character_id, String(issued["ticket"]), player_state)
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
	var relay: Node = get_tree().root.get_node_or_null("NakamaGameplayRelay")
	if relay != null and relay.available():
		character_wire["nakama_match_id"] = relay.match_id()
	network_client.rpc_id(peer_id, "receive_enter_world_result", String(result["outcome"]), character_wire)


## RPC target: called by the server on the requesting client with its own
## world-entry outcome. Relayed via a signal for the character-select screen or
## test harness to transition into gameplay.
@rpc("authority", "call_remote", "reliable")
func receive_enter_world_result(outcome: String, character: Dictionary) -> void:
	world_entry_received.emit(outcome, character)
	if outcome == "ok":
		_start_nakama_gameplay(String(character.get("nakama_match_id", "")))


## Slice 077: emitted when perform_login_to_game_handoff finishes, with the final
## outcome ("ok" on world entry) and the bound Character wire dict (empty on any
## earlier failure). The login screen (or a harness) transitions on this.
signal login_to_game_handoff_finished(outcome: String, world_character: Dictionary)

## Slice 077: bounded per-step wait (ms) for the login->game handoff, so a dropped
## reply ends the step with a terminal outcome instead of hanging.
const HANDOFF_STEP_TIMEOUT_MS: int = 20000


## Slice 077: Phase 2 of the login split. Call while connected to the login
## process with a selected Character: requests a signed assertion, hands off to
## the game process (disconnect -> connect -> present assertion), and enters the
## world, emitting login_to_game_handoff_finished(outcome, character). Poll-based
## and bounded; drives only public seams, and the server owns every outcome.
func perform_login_to_game_handoff(game_host: String, game_port: int) -> void:
	var token: String = await _handoff_request_assertion()
	if token.is_empty():
		login_to_game_handoff_finished.emit("assertion_failed", {})
		return

	# Slice 087: while still authenticated on the login process, obtain a
	# longer-lived account resume token so the in-world "Character Select" return
	# can re-establish a login session without re-authenticating. Best-effort — a
	# failure only means that later return falls back to the login screen.
	_resume_assertion = await _handoff_request_resume_assertion()

	disconnect_from_server()
	if not await _handoff_await_connected(false):
		login_to_game_handoff_finished.emit("login_disconnect_timeout", {})
		return

	connect_to_server(game_host, game_port)
	if not await _handoff_await_connected(true):
		login_to_game_handoff_finished.emit("game_connect_timeout", {})
		return

	var session_outcome: String = await _handoff_present_assertion(token)
	if session_outcome != "ok":
		login_to_game_handoff_finished.emit(session_outcome if not session_outcome.is_empty() else "session_timeout", {})
		return

	var world: Dictionary = await _handoff_enter_world()
	login_to_game_handoff_finished.emit(String(world.get("outcome", "world_timeout")), world.get("character", {}))


## Slice 093: WAN world entry after the HTTPS account/character flow. Unlike
## perform_login_to_game_handoff, the client authenticated and selected its
## Character entirely over HTTPS (client/enrollment_http_client.gd) with NO ENet
## login connection, so it already holds a signed CHARACTER assertion and starts
## disconnected. This connects to the game server (bringing up the in-process
## tunnel when PROJECT0_TUNNEL=1), presents that assertion via the existing
## establish_session_from_assertion path, and enters the world — reusing the same
## bounded per-step waits and the login_to_game_handoff_finished signal. The
## server owns every outcome; a tampered/expired assertion binds nothing.
func perform_https_world_entry(game_host: String, game_port: int, character_assertion: String) -> void:
	if character_assertion.is_empty():
		login_to_game_handoff_finished.emit("assertion_failed", {})
		return

	connect_to_server(game_host, game_port)
	if not await _handoff_await_connected(true):
		login_to_game_handoff_finished.emit("game_connect_timeout", {})
		return

	var session_outcome: String = await _handoff_present_assertion(character_assertion)
	if session_outcome != "ok":
		login_to_game_handoff_finished.emit(session_outcome if not session_outcome.is_empty() else "session_timeout", {})
		return

	var world: Dictionary = await _handoff_enter_world()
	login_to_game_handoff_finished.emit(String(world.get("outcome", "world_timeout")), world.get("character", {}))
## Emits return_to_character_select_finished("ok") on success; any other outcome
## means the caller should fall back to the login screen to re-authenticate.
func perform_return_to_character_select(login_host: String, login_port: int) -> void:
	if _resume_assertion.is_empty():
		return_to_character_select_finished.emit("no_resume_token")
		return

	disconnect_from_server()
	if not await _handoff_await_connected(false):
		return_to_character_select_finished.emit("game_disconnect_timeout")
		return

	connect_to_server(login_host, login_port)
	if not await _handoff_await_connected(true):
		return_to_character_select_finished.emit("login_connect_timeout")
		return

	var session_outcome: String = await _handoff_present_assertion(_resume_assertion)
	if session_outcome != "ok":
		return_to_character_select_finished.emit(session_outcome if not session_outcome.is_empty() else "session_timeout")
		return
	return_to_character_select_finished.emit("ok")


func _handoff_request_assertion() -> String:
	var box: Dictionary = {"done": false, "outcome": "", "token": ""}
	var cb: Callable = func(o: String, t: String) -> void:
		box["done"] = true
		box["outcome"] = o
		box["token"] = t
	assertion_result_received.connect(cb, CONNECT_ONE_SHOT)
	submit_request_assertion()
	var reached: bool = await _handoff_poll(box)
	if assertion_result_received.is_connected(cb):
		assertion_result_received.disconnect(cb)
	if not reached or String(box["outcome"]) != "ok":
		return ""
	return String(box["token"])


## Slice 087: requests the account resume token from the login process. Mirrors
## _handoff_request_assertion; returns "" on any failure so the caller treats
## resume as unavailable (falling back to a re-login on return).
func _handoff_request_resume_assertion() -> String:
	var box: Dictionary = {"done": false, "outcome": "", "token": ""}
	var cb: Callable = func(o: String, t: String) -> void:
		box["done"] = true
		box["outcome"] = o
		box["token"] = t
	resume_assertion_result_received.connect(cb, CONNECT_ONE_SHOT)
	submit_request_resume_assertion()
	var reached: bool = await _handoff_poll(box)
	if resume_assertion_result_received.is_connected(cb):
		resume_assertion_result_received.disconnect(cb)
	if not reached or String(box["outcome"]) != "ok":
		return ""
	return String(box["token"])


func _handoff_present_assertion(token: String) -> String:
	var box: Dictionary = {"done": false, "outcome": ""}
	var cb: Callable = func(o: String) -> void:
		box["done"] = true
		box["outcome"] = o
	session_established_received.connect(cb, CONNECT_ONE_SHOT)
	submit_present_assertion(token)
	var reached: bool = await _handoff_poll(box)
	if session_established_received.is_connected(cb):
		session_established_received.disconnect(cb)
	return String(box["outcome"]) if reached else ""


func _handoff_enter_world() -> Dictionary:
	var box: Dictionary = {"done": false, "outcome": "", "character": {}}
	var cb: Callable = func(o: String, c: Dictionary) -> void:
		box["done"] = true
		box["outcome"] = o
		box["character"] = c
	world_entry_received.connect(cb, CONNECT_ONE_SHOT)
	submit_enter_world()
	var reached: bool = await _handoff_poll(box)
	if world_entry_received.is_connected(cb):
		world_entry_received.disconnect(cb)
	if not reached:
		return {"outcome": "", "character": {}}
	return {"outcome": box["outcome"], "character": box["character"]}


## Polls a capture box's "done" flag each frame until set or the step times out.
func _handoff_poll(box: Dictionary) -> bool:
	var deadline: int = Time.get_ticks_msec() + HANDOFF_STEP_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		if box["done"]:
			return true
		await get_tree().process_frame
	return false


## Polls the connection status until it matches `want_connected` or times out.
func _handoff_await_connected(want_connected: bool) -> bool:
	var deadline: int = Time.get_ticks_msec() + HANDOFF_STEP_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		if String(status).begins_with("connected") == want_connected:
			return true
		await get_tree().process_frame
	return false
