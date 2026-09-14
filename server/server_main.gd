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
## Slice 033 replicates every currently living monster to clients in the same
## style as remote players: a new peer receives a spawn RPC for each living
## monster, every physics frame broadcasts each living monster's position to
## all peers, and a respawn re-sends a spawn RPC at the new position. Monster
## death/despawn reuses the existing COMBAT_EVENT_DEATH broadcast rather than a
## parallel channel — see docs/slices/033-client-monster-replication-and-rendering.md.

const NetworkConfigScript: Script = preload("res://shared/network_config.gd")
const ServerPlayerStateScript: Script = preload("res://server/server_player_state.gd")
const StartingTownHubFixtureScript: Script = preload("res://server/starting_town_hub_fixture.gd")
const HouseAllocatorScript: Script = preload("res://server/house_allocator.gd")
const ServerMonsterManagerScript: Script = preload("res://server/server_monster_manager.gd")
const SectorCollisionMapScript: Script = preload("res://shared/sector_collision_map.gd")
const CombatContractsScript: Script = preload("res://shared/combat_contracts.gd")
const SqliteStoreScript: Script = preload("res://server/sqlite_store.gd")
const AccountCharacterRepositoryScript: Script = preload("res://server/account_character_repository.gd")
const CanonRepositoryScript: Script = preload("res://server/canon_repository.gd")
const ProvisionalSectorGeneratorScript: Script = preload("res://server/provisional_sector_generator.gd")
const SectorBoundaryDetectorScript: Script = preload("res://server/sector_boundary_detector.gd")
const CanonGenerationCoordinatorScript: Script = preload("res://server/canon_generation_coordinator.gd")
const AuthServiceScript: Script = preload("res://server/auth_service.gd")
const CharacterServiceScript: Script = preload("res://server/character_service.gd")

## Slice 040: the accounts/characters database file, opened at server boot
## under user:// (never a shipped res:// asset — see SqliteStore's own rule).
## A relative path so multiple concurrently running server instances (e.g.
## local dev + CI) can each pass a distinct PROJECT0_ACCOUNTS_DB_PATH without
## colliding on one file.
const DEFAULT_ACCOUNTS_DB_PATH: String = "accounts.db"

## Maximum concurrently connected peers supported on this server instance.
## Additional connection attempts beyond this limit are rejected (see
## _on_peer_connected below).
const MAX_REPLICATED_PEERS: int = 10

## Slice 012: a single stationary server-owned target dummy proves the first
## authoritative melee hit deterministically, without relying on remote-peer
## movement jitter — see
## .scratch/melee-combat/issues/01-define-first-melee-exchange.md. Keyed by
## target_id so future dummies extend this dictionary without a schema
## change.
const TARGET_DUMMY_ID: String = "target_dummy_0"
const TARGET_DUMMY_POSITION: Vector3 = Vector3(0.0, 1.0, -2.0)

const START_POSITIONS: Array[Vector3] = [
	Vector3(3.0, 1.0, 3.0),
	Vector3(-3.0, 1.0, -3.0),
	Vector3(3.0, 1.0, -3.0),
	Vector3(-3.0, 1.0, 3.0),
	Vector3(5.0, 1.0, 0.0),
	Vector3(-5.0, 1.0, 0.0),
	Vector3(0.0, 1.0, 5.0),
	Vector3(0.0, 1.0, -5.0),
	Vector3(4.0, 1.0, 4.0),
	Vector3(-4.0, 1.0, -4.0),
]

## Keyed by peer id; each connected peer owns exactly one ServerPlayerState,
## so two peers never share mutable position/input-sequence state.
var _player_states: Dictionary = {}
var _peer: ENetMultiplayerPeer

## Slice 012: keyed by target_id to the server-owned Node3D each
## ServerPlayerState's melee hit test checks against. Populated once in
## _start_server(), shared read-only across every peer's ServerPlayerState.
var _target_dummies: Dictionary = {}

## Slice 016: the validated starting town hub blueprint, materialized eagerly
## and synchronously at server boot from the hard-coded StartingTownHubFixture
## (not from Ollama). Held in memory so a future slice can replicate it to
## clients; empty until _start_server() validates the fixture.
var _starting_town_hub_blueprint: Dictionary = {}

## Slice 030: server-side wall/building collision for the hub, built from the
## validated blueprint at boot and injected into each peer's ServerPlayerState.
var _town_collision: Object = null

## Slice 019: server-authoritative allocation of the hub's fixed 10-house pool,
## one unique house per connected peer, freed immediately on disconnect. Built
## from the validated hub blueprint at boot. Typed as Object and accessed
## dynamically (like this file's other script-backed state) because its
## class_name is not resolvable in headless class-cache runs.
var _house_allocator: Object = null

## Slice 022: server-side monster runtime that spawns one monster per town
## spawn point (outside the town wall), drives their AI each physics frame
## against connected players, and respawns defeated monsters after a cooldown.
var _monster_manager: Object = null
var _monster_tick: int = 0

## Slice 040: the shared server-owned SQLite handle and the Account/Character
## repository/auth dispatch built on top of it. Opened/wired during
## _start_server() before the socket opens; a DB-open failure refuses to
## start the server (fail-closed, matching the existing hub-fixture check).
var _accounts_store: SqliteStore = null
var _account_repository: Object = null
var _auth_service: Object = null
var _character_service: Object = null
var _canon_repository: Object = null
var _provisional_sector_generator: Node = null
var _sector_boundary_detector: Object = null
var _canon_generation_coordinator: Object = null

## Fixed simulation delta used to drive monster chase movement each physics
## frame (the SceneTree physics_frame signal carries no delta).
const MONSTER_TICK_DELTA: float = 1.0 / 60.0


func _initialize() -> void:
	call_deferred("_start_server")


## Public seam: starts listening and wires connection signals. Deferred past
## _initialize() because SceneTree.root's multiplayer API is not yet attached
## when _initialize() runs.
func _start_server() -> void:
	# Slice 016: materialize the starting town hub fixture before opening a
	# socket. It is static data, so validation is synchronous and cheap; a
	# fixture that fails its own schema is a programming error, so fail closed
	# (refuse to start) rather than silently degrading to an empty world.
	var hub: Dictionary = StartingTownHubFixtureScript.materialize(StartingTownHubFixtureScript.blueprint())
	if not hub["ok"]:
		push_error("Refusing to start: starting town hub fixture failed validation: %s — %s" % [hub["outcome"], hub["detail"]])
		quit(1)
		return
	_starting_town_hub_blueprint = hub["blueprint"]
	print("Starting town hub fixture validated: %d structures." % (_starting_town_hub_blueprint["structures"] as Array).size())

	# Slice 030: build the server-side collision map (solid walls + building
	# footprints) from the validated hub, injected into each peer below.
	_town_collision = SectorCollisionMapScript.new(_starting_town_hub_blueprint)
	print("Town collision map ready: %d solid cells." % _town_collision.blocked_count())

	# Slice 019: build the house pool from the validated hub so each peer can be
	# assigned a unique house on connect.
	_house_allocator = HouseAllocatorScript.new(HouseAllocatorScript.house_ids_from_blueprint(_starting_town_hub_blueprint))
	print("Starting town house pool ready: %d houses." % _house_allocator.pool_size())

	# Slice 022: spawn monsters from the hub's spawn points (authored outside the
	# town wall) and drive their AI each physics frame.
	_monster_manager = ServerMonsterManagerScript.new(_starting_town_hub_blueprint.get("spawn_points", []), int(Time.get_ticks_usec()))
	_monster_manager.monster_died.connect(_on_monster_died)
	_monster_manager.monster_respawned.connect(_on_monster_respawned)
	physics_frame.connect(_on_physics_frame)
	print("Spawned %d monsters outside the town." % _monster_manager.monster_count())

	# Slice 040: open the shared accounts/characters SQLite store and ensure its
	# schema before opening a socket. This is the first runtime consumer of the
	# Slice 038/039 SqliteStore/AccountCharacterRepository seams. Fail closed
	# (refuse to start), matching the hub-fixture check above: a DB that cannot
	# open or whose schema cannot be ensured must never silently run with no
	# durable accounts layer.
	var accounts_db_path: String = OS.get_environment("PROJECT0_ACCOUNTS_DB_PATH")
	if accounts_db_path.is_empty():
		accounts_db_path = DEFAULT_ACCOUNTS_DB_PATH
	_accounts_store = SqliteStoreScript.new()
	var open_result: Dictionary = _accounts_store.open(accounts_db_path)
	if open_result["outcome"] != SqliteStoreScript.OUTCOME_OK:
		push_error("Refusing to start: accounts database failed to open: %s — %s" % [open_result["outcome"], open_result["detail"]])
		quit(1)
		return
	_account_repository = AccountCharacterRepositoryScript.new(_accounts_store)
	var schema_result: Dictionary = _account_repository.ensure_schema()
	if schema_result["outcome"] != "ok":
		push_error("Refusing to start: accounts schema failed to initialize: %s — %s" % [schema_result["outcome"], schema_result["detail"]])
		quit(1)
		return
	# Slice 045: Canon shares the one server-owned SQLite handle with accounts.
	# The validated hub is canonicalized before the socket opens, so every peer
	# sees a world record that survives a server restart.
	_canon_repository = CanonRepositoryScript.new(_accounts_store)
	var canon_schema_result: Dictionary = _canon_repository.ensure_schema()
	if canon_schema_result["outcome"] != "ok":
		push_error("Refusing to start: Canon schema failed to initialize: %s — %s" % [canon_schema_result["outcome"], canon_schema_result["detail"]])
		quit(1)
		return
	var canon_result: Dictionary = _canon_repository.canonicalize_blueprint(_starting_town_hub_blueprint)
	if canon_result["outcome"] != CanonRepositoryScript.OUTCOME_OK and canon_result["outcome"] != CanonRepositoryScript.OUTCOME_IDEMPOTENT:
		push_error("Refusing to start: starting town Canon failed: %s — %s" % [canon_result["outcome"], canon_result["detail"]])
		quit(1)
		return
	print("Starting town Canon ready: %s." % canon_result["outcome"])
	# Slice 046: authoritative movement now drives non-blocking JIT requests for
	# unexplored sectors. The detector performs only cheap sector math and the
	# generator accepts work synchronously before awaiting Ollama in a deferred
	# coroutine.
	_provisional_sector_generator = ProvisionalSectorGeneratorScript.new()
	_provisional_sector_generator.name = "ProvisionalSectorGenerator"
	root.add_child(_provisional_sector_generator)
	_canon_generation_coordinator = CanonGenerationCoordinatorScript.new()
	_canon_generation_coordinator.set_canonicalize_callback(Callable(_canon_repository, "canonicalize_blueprint"))
	_canon_generation_coordinator.canonical_sector_ready.connect(_on_canonical_sector_ready)
	_provisional_sector_generator.provisional_sector_ready.connect(_on_provisional_sector_ready)
	_sector_boundary_detector = SectorBoundaryDetectorScript.new()
	_sector_boundary_detector.set_canon_lookup(Callable(_canon_repository, "get_canonical_sector"))
	_sector_boundary_detector.set_request_callback(Callable(self, "_request_sector_from_boundary"))
	_auth_service = AuthServiceScript.new(_account_repository)
	_auth_service.name = "AuthService"
	root.add_child(_auth_service)
	# Slice 042: session-gated Character CRUD dispatch, sharing AuthService's
	# SessionRegistry so a session bound by register/login is visible to
	# character create/select/delete without a second session store.
	_character_service = CharacterServiceScript.new(_account_repository, _auth_service.get_session_registry())
	_character_service.name = "CharacterService"
	root.add_child(_character_service)
	print("Accounts database ready at user://%s (schema ensured)." % accounts_db_path)

	var bind_address: String = NetworkConfigScript.resolve_server_bind_address()
	var server_port: int = NetworkConfigScript.resolve_server_port()

	_peer = ENetMultiplayerPeer.new()
	# set_bind_ip() must be called before create_server(); Godot 4.3's
	# create_server() itself takes no address argument and binds all
	# interfaces ("*") unless set_bind_ip() restricts it first (confirmed
	# empirically — see docs/slices/003-lan-client-connection.md).
	_peer.set_bind_ip(bind_address)
	var listen_error: Error = _peer.create_server(server_port, NetworkConfigScript.MAX_CLIENTS, 0, 0, 0)
	if listen_error != OK:
		push_error("Server failed to listen on %s:%d: %s" % [bind_address, server_port, listen_error])
		quit(1)
		return

	root.multiplayer.multiplayer_peer = _peer
	root.multiplayer.peer_connected.connect(_on_peer_connected)
	root.multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_spawn_target_dummies()
	print("Server listening on %s:%d" % [bind_address, server_port])
	if bind_address != NetworkConfigScript.SERVER_ADDRESS:
		print("WARNING: bound to a non-localhost address. This server accepts unauthenticated connections from any host that can reach %s:%d. Only do this on a trusted local network." % [bind_address, server_port])


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

	# Slice 017: replicate the validated starting town hub to this peer before
	# spawning any Player, so the world exists before its occupants. All these
	# RPCs are reliable, so ordering is guaranteed.
	network_client.rpc_id(peer_id, "receive_sector_blueprint", _starting_town_hub_blueprint)
	print("Sent starting town hub blueprint to peer %d (sector_id=%s)." % [peer_id, _starting_town_hub_blueprint.get("sector_id", "")])

	network_client.rpc_id(peer_id, "spawn_own_player_representation")

	var start_position: Vector3 = _start_position_for_slot(_player_states.size())
	var player_state: Node = ServerPlayerStateScript.new()
	player_state.name = "ServerPlayerState_%d" % peer_id
	player_state.position_updated.connect(_on_player_state_position_updated)
	player_state.action_resolved.connect(_on_player_state_action_resolved)
	player_state.combat_event_emitted.connect(_on_player_state_combat_event_emitted)
	player_state.melee_swing_started.connect(_on_player_state_melee_swing_started)
	root.add_child(player_state)
	player_state.start_for_peer(peer_id, start_position)
	player_state.set_target_dummies(_target_dummies)
	player_state.set_monster_manager(_monster_manager)
	# DT-006/E2E isolation seam: PROJECT0_E2E_DISABLE_TOWN_COLLISION=1 skips
	# injecting the town collision map so ServerPlayerState's null-safe
	# fallback (server/server_player_state.gd) leaves movement unconstrained,
	# restoring the flat-arena path scripts/test_authoritative_melee_strike_e2e.gd
	# depends on. Default OFF; never set on the real LAN server path.
	if OS.get_environment("PROJECT0_E2E_DISABLE_TOWN_COLLISION") != "1":
		player_state.set_collision_map(_town_collision)
	_player_states[peer_id] = player_state

	# Slice 019: assign this peer a unique house from the pool and tell only the
	# owning client. Fail closed (log) if the pool is somehow exhausted — this is
	# unreachable while the pool size matches MAX_REPLICATED_PEERS.
	var house_id: String = _house_allocator.assign(peer_id)
	if house_id.is_empty():
		push_error("Peer %d connected but no house slot is available (pool exhausted)." % peer_id)
	else:
		print("Assigned house %s to peer %d (%d houses free)." % [house_id, peer_id, _house_allocator.available_count()])
		network_client.rpc_id(peer_id, "receive_assigned_house", house_id)

	# Replicate existing peers to the new peer, and the new peer to existing
	# peers — each direction is its own explicit RPC call naming the target
	# peer id, so no representation node is ever shared between two peers.
	for existing_peer_id: int in _player_states.keys():
		if existing_peer_id == peer_id:
			continue
		var existing_state: Node = _player_states[existing_peer_id]
		network_client.rpc_id(peer_id, "spawn_remote_player_representation", existing_peer_id, existing_state.position)
		network_client.rpc_id(existing_peer_id, "spawn_remote_player_representation", peer_id, start_position)

	# Slice 033: replicate every currently living monster to the new peer only
	# — existing peers already have a representation for each from their own
	# connect (or the initial spawn) and do not need it re-sent.
	if _monster_manager != null:
		var living: Dictionary = _monster_manager.living_targets()
		for target_id: String in living.keys():
			var monster: Object = living[target_id]
			network_client.rpc_id(peer_id, "receive_monster_spawn", target_id, monster.position)


## Called whenever a client peer disconnects. Removes that peer's
## ServerPlayerState entirely (Slice 007: no longer just unbinds a shared
## instance, since each peer now owns its own) and tells every remaining
## peer to despawn that departed peer's remote representation.
func _on_peer_disconnected(peer_id: int) -> void:
	print("Peer disconnected: %d" % peer_id)
	# Slice 040: clear this peer's in-memory session, if any. Sessions are
	# never persisted, so a reconnecting peer always finds no session and must
	# fully re-authenticate — see server/session_registry.gd.
	if _auth_service != null:
		_auth_service.clear_session(peer_id)
	# Slice 019: free this peer's house back to the pool immediately (no
	# reconnect reservation).
	if _house_allocator != null:
		_house_allocator.release(peer_id)
		print("Released house for peer %d (%d houses free)." % [peer_id, _house_allocator.available_count()])
	var player_state: Node = _player_states.get(peer_id)
	if player_state != null:
		player_state.position_updated.disconnect(_on_player_state_position_updated)
		player_state.action_resolved.disconnect(_on_player_state_action_resolved)
		player_state.combat_event_emitted.disconnect(_on_player_state_combat_event_emitted)
		player_state.melee_swing_started.disconnect(_on_player_state_melee_swing_started)
		_player_states.erase(peer_id)
		player_state.queue_free()
	if _sector_boundary_detector != null:
		_sector_boundary_detector.forget_peer(peer_id)

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
	if _sector_boundary_detector != null:
		_sector_boundary_detector.observe_position(peer_id, updated_position)
	var network_client: Node = root.get_node_or_null("NetworkClient")
	if network_client == null:
		return
	for other_peer_id: int in _player_states.keys():
		if other_peer_id == peer_id:
			continue
		network_client.rpc_id(other_peer_id, "receive_remote_player_position", peer_id, updated_position)


func _request_sector_from_boundary(peer_id: int, sector_id: String, position: Vector3) -> void:
	if _provisional_sector_generator == null:
		return
	var prompt: String = "Generate the validated sector blueprint for %s near world position (%0.2f, %0.2f)." % [sector_id, position.x, position.z]
	var correlation_id: String = _provisional_sector_generator.request_provisional_sector(sector_id, prompt)
	print("Requested provisional sector %s for peer %d (%s)." % [sector_id, peer_id, correlation_id])


func _on_provisional_sector_ready(sector_id: String, result: Dictionary) -> void:
	if _canon_generation_coordinator == null:
		return
	var finalization: Dictionary = _canon_generation_coordinator.accept_generation_result(sector_id, result)
	if finalization["outcome"] == CanonGenerationCoordinatorScript.OUTCOME_IGNORED:
		print("Ignored provisional sector %s: %s" % [sector_id, finalization["detail"]])
	elif finalization["outcome"] == CanonGenerationCoordinatorScript.OUTCOME_CONFLICT:
		push_warning("Rejected conflicting provisional sector %s: %s" % [sector_id, finalization["detail"]])


func _on_canonical_sector_ready(sector_id: String, blueprint: Dictionary) -> void:
	var network_client: Node = root.get_node_or_null("NetworkClient")
	if network_client == null:
		return
	for peer_id: int in _player_states.keys():
		network_client.rpc_id(peer_id, "receive_sector_blueprint", blueprint)
	print("Replicated canonical sector %s to %d connected peers." % [sector_id, _player_states.size()])


## Deterministic, visibly distinct starting positions for connected peers so
## Player representations never spawn on top of each other.
func _start_position_for_slot(slot_index: int) -> Vector3:
	if slot_index >= 0 and slot_index < START_POSITIONS.size():
		return START_POSITIONS[slot_index]
	var angle: float = float(slot_index) * (TAU / float(MAX_REPLICATED_PEERS))
	var radius: float = 4.0
	return Vector3(cos(angle) * radius, 1.0, sin(angle) * radius)


## Slice 012: creates the server-owned stationary target dummy(ies) every
## ServerPlayerState's melee hit test checks against. A plain Node3D is
## enough here — there is no client-visible representation server-side; the
## client's own client/target_dummy.gd renders and reacts to the replicated
## CombatEvent.HIT separately.
func _spawn_target_dummies() -> void:
	var dummy: Node3D = Node3D.new()
	dummy.name = "TargetDummy_%s" % TARGET_DUMMY_ID
	dummy.position = TARGET_DUMMY_POSITION
	root.add_child(dummy)
	_target_dummies[TARGET_DUMMY_ID] = dummy


## Slice 016: read-only access to the validated starting town hub blueprint
## materialized at boot. Returns an empty Dictionary before _start_server()
## has run. A future slice (server-to-client blueprint replication) consumes
## this; nothing in this slice sends it anywhere.
func get_starting_town_hub_blueprint() -> Dictionary:
	return _starting_town_hub_blueprint


## Slice 019: read-only access to the house currently allocated to a peer, or
## "" if none. Exposed for future slices and inspection.
func get_assigned_house(peer_id: int) -> String:
	if _house_allocator == null:
		return ""
	return _house_allocator.assigned_house(peer_id)


## Slice 022: drives the monster runtime one authoritative tick per physics
## frame, feeding it every connected peer's current position so monsters chase
## the nearest one. Monsters idle when no one is connected.
func _on_physics_frame() -> void:
	if _monster_manager == null:
		return
	var player_positions: Array[Vector3] = []
	for player_state: Node in _player_states.values():
		player_positions.append(player_state.position)
	_monster_manager.advance_all(player_positions, MONSTER_TICK_DELTA, _monster_tick)
	_monster_tick += 1
	_broadcast_monster_positions()


## Slice 033: broadcasts every currently living monster's authoritative
## position to every connected peer, in the same per-entity relay style as
## _on_player_state_position_updated. Reuses ServerMonsterManager.living_targets()
## so a dead/respawning monster is simply never sent — the client despawns it
## via the existing COMBAT_EVENT_DEATH broadcast instead (client/monster.gd),
## rather than a redundant "monster removed" channel.
func _broadcast_monster_positions() -> void:
	var network_client: Node = root.get_node_or_null("NetworkClient")
	if network_client == null:
		return
	var living: Dictionary = _monster_manager.living_targets()
	for target_id: String in living.keys():
		var monster: Object = living[target_id]
		for receiving_peer_id: int in _player_states.keys():
			network_client.rpc_id(receiving_peer_id, "receive_monster_position", target_id, monster.position)


func _on_monster_died(spawn_id: String, server_tick: int) -> void:
	print("Monster %s defeated at tick %d." % [spawn_id, server_tick])


## Slice 033: in addition to existing telemetry, tells every connected peer to
## (re)spawn a cosmetic representation for the respawned monster at its new
## position — mirrors the peer-connect replication above but triggered by the
## respawn event rather than a new connection. The death/despawn side of this
## lifecycle is already covered by the existing COMBAT_EVENT_DEATH broadcast
## (_on_player_state_combat_event_emitted), which client/monster.gd reacts to
## directly, so no separate "monster removed" RPC is added here.
func _on_monster_respawned(spawn_id: String, position: Vector3, server_tick: int) -> void:
	print("Monster %s respawned at %s (tick %d)." % [spawn_id, position, server_tick])
	var network_client: Node = root.get_node_or_null("NetworkClient")
	if network_client == null:
		return
	for receiving_peer_id: int in _player_states.keys():
		network_client.rpc_id(receiving_peer_id, "receive_monster_spawn", spawn_id, position)


## Relays one peer's authoritative ActionResolution back to that same peer
## only — an action's acceptance/rejection is meaningful solely to the
## Player who submitted the intent, matching how receive_authoritative_position
## above is peer-scoped rather than broadcast.
func _on_player_state_action_resolved(peer_id: int, resolution: Object) -> void:
	var network_client: Node = root.get_node_or_null("NetworkClient")
	if network_client == null:
		return
	network_client.rpc_id(
		peer_id,
		"receive_action_resolution",
		resolution.sequence,
		resolution.result,
		resolution.rejection_reason,
		resolution.server_tick
	)


## Broadcasts a confirmed CombatEvent.HIT to every connected peer (including
## the attacker) so each client's target_dummy.gd can render the same
## authoritative feedback, regardless of which peer's swing produced it.
## Slice 029: a HIT against a living monster's target_id also routes the
## authoritative damage application through ServerMonsterManager — the sole
## owner of monster mutation, per CLAUDE.md's single-owner rule; this
## ServerPlayerState-originated signal never touches monster state itself.
## When that application defeats the monster, broadcasts a second,
## attacker-attributed CombatEvent.DEATH over the same existing channel so
## Slice 030's client rendering can react without a parallel event path.
func _on_player_state_combat_event_emitted(_peer_id: int, combat_event: Object) -> void:
	_broadcast_combat_event(combat_event)

	if combat_event.kind != CombatContractsScript.COMBAT_EVENT_HIT or _monster_manager == null:
		return

	var died: bool = _monster_manager.receive_player_hit(combat_event.target_id, combat_event.attacker_peer_id, combat_event.server_tick)
	if died:
		var death_event: Object = CombatContractsScript.CombatEvent.new(
			CombatContractsScript.COMBAT_EVENT_DEATH,
			combat_event.attacker_peer_id,
			combat_event.target_id,
			combat_event.impact_position,
			combat_event.server_tick
		)
		print("Monster %s defeated by peer %d at tick %d." % [combat_event.target_id, combat_event.attacker_peer_id, combat_event.server_tick])
		_broadcast_combat_event(death_event)


## Shared broadcast helper for both CombatEvent.HIT and CombatEvent.DEATH, so
## both reuse the exact same receive_combat_event channel rather than a
## parallel one.
func _broadcast_combat_event(combat_event: Object) -> void:
	var network_client: Node = root.get_node_or_null("NetworkClient")
	if network_client == null:
		return
	for receiving_peer_id: int in _player_states.keys():
		network_client.rpc_id(
			receiving_peer_id,
			"receive_combat_event",
			combat_event.kind,
			combat_event.attacker_peer_id,
			combat_event.target_id,
			combat_event.impact_position,
			combat_event.server_tick
		)


## Broadcasts a melee swing's already-accepted phase timing/facing to every
## connected peer, including the attacker (whose own client/player.gd already
## predicted the same timing locally and simply ignores this redundant echo —
## see receive_melee_swing_started's docstring). Lets every other peer's
## RemotePlayer render the same cosmetic strike-line indicator the attacker
## sees, without granting any peer a trusted hit outcome — that remains
## exclusively _on_player_state_combat_event_emitted's job.
func _on_player_state_melee_swing_started(peer_id: int, windup_ticks: int, active_ticks: int, facing: Vector3) -> void:
	var network_client: Node = root.get_node_or_null("NetworkClient")
	if network_client == null:
		return
	for receiving_peer_id: int in _player_states.keys():
		network_client.rpc_id(receiving_peer_id, "receive_melee_swing_started", peer_id, windup_ticks, active_ticks, facing)
