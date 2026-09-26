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
const ServerPlayerStateScript: Script = preload("res://server/admitted_player_state.gd")
const StartingTownHubFixtureScript: Script = preload("res://server/starting_town_hub_fixture.gd")
const HouseAllocatorScript: Script = preload("res://server/house_allocator.gd")
const ServerMonsterManagerScript: Script = preload("res://server/server_monster_manager.gd")
const ServerTownNpcManagerScript: Script = preload("res://server/server_town_npc_manager.gd")
const MonsterContractsScript: Script = preload("res://shared/monster_contracts.gd")
const SectorCollisionMapScript: Script = preload("res://shared/sector_collision_map.gd")
const CombatContractsScript: Script = preload("res://shared/combat_contracts.gd")
const VersionHandshakeScript: Script = preload("res://shared/version_handshake.gd")
const SqliteStoreScript: Script = preload("res://server/sqlite_store.gd")
const AccountCharacterRepositoryScript: Script = preload("res://server/account_character_repository.gd")
const CanonRepositoryScript: Script = preload("res://server/canon_repository.gd")
const CanonMutationRepositoryScript: Script = preload("res://server/canon_mutation_repository.gd")
const CanonMutationServiceScript: Script = preload("res://server/canon_mutation_service.gd")
const CanonSectorResolverScript: Script = preload("res://shared/canon_sector_resolver.gd")
const ProvisionalSectorGeneratorScript: Script = preload("res://server/provisional_sector_generator.gd")
const SectorBoundaryDetectorScript: Script = preload("res://server/sector_boundary_detector.gd")
const CanonGenerationCoordinatorScript: Script = preload("res://server/canon_generation_coordinator.gd")
const SectorArchetypeAdmissionScript: Script = preload("res://server/sector_archetype_admission.gd")
const LoginRuntimeScript: Script = preload("res://server/login_runtime.gd")
const NakamaSessionValidatorScript: Script = preload("res://server/nakama_session_validator.gd")
const WorldEntryTicketServiceScript: Script = preload("res://server/world_entry_ticket_service.gd")
const NakamaGameplayBridgeScript: Script = preload("res://server/nakama_gameplay_bridge.gd")
const NakamaGameplayRelayScript: Script = preload("res://server/nakama_gameplay_relay.gd")
const AssertionValidatorScript: Script = preload("res://server/assertion_validator.gd")
const OperatorControlServiceScript: Script = preload("res://server/operator_control_service.gd")
const OperatorControlAdapterScript: Script = preload("res://server/operator_control_adapter.gd")
const OperatorControlHttpEndpointScript: Script = preload("res://server/operator_control_http_endpoint.gd")
const ServerHealthScript: Script = preload("res://server/server_health.gd")
const HealthReporterScript: Script = preload("res://server/health_reporter.gd")
const OpsSnapshotScript: Script = preload("res://server/ops_snapshot.gd")
const NakamaPresenceScript: Script = preload("res://shared/nakama_presence.gd")
const TelemetrySinkScript: Script = preload("res://server/telemetry_sink.gd")
const TelemetryRateLimiterScript: Script = preload("res://server/telemetry_rate_limiter.gd")
const TelemetryIngestServiceScript: Script = preload("res://server/telemetry_ingest_service.gd")
const TelemetryEventScript: Script = preload("res://shared/telemetry_event.gd")
const JitTraceContextScript: Script = preload("res://shared/jit_trace_context.gd")
const JitPresentationAckTrackerScript: Script = preload("res://server/jit_presentation_ack_tracker.gd")
const JourneyRegistryScript: Script = preload("res://server/journey_registry.gd")
const JourneyRepositoryScript: Script = preload("res://server/journey_repository.gd")

## Slice 067: the app schema version reported in the runtime health snapshot.
const APP_SCHEMA_VERSION: int = 1

## Slice 067: physics-frame stride between health-file refreshes (~0.5 s at the
## default 60 Hz physics step). The container HEALTHCHECK interval is 15 s, so a
## sub-second refresh keeps the file well within its staleness window.
const HEALTH_REFRESH_FRAMES: int = 30

# Slice 068: the login authority's assertion issuer/audience identifiers now live
# on LoginRuntime (LoginRuntime.ASSERTION_ISSUER_ID / ASSERTION_AUDIENCE), shared
# by the game server and the standalone login process.
const TownLayoutProviderScript: Script = preload("res://server/town_layout_provider.gd")
const LocalLLMClientScript: Script = preload("res://shared/local_llm_client.gd")
const SectorBlueprintSchemaScript: Script = preload("res://shared/sector_blueprint_schema.gd")

## Slice 040: the accounts/characters database file, opened at server boot
## under user:// (never a shipped res:// asset — see SqliteStore's own rule).
## A relative path so multiple concurrently running server instances (e.g.
## local dev + CI) can each pass a distinct PROJECT0_ACCOUNTS_DB_PATH without
## colliding on one file.
const DEFAULT_ACCOUNTS_DB_PATH: String = "accounts.db"

## Slice 079: opt-in dedicated Canon database. Unset (default) keeps the Slice
## 045 behavior where Canon shares the accounts SQLite handle. When set, Canon
## opens its own store at this path so a split deployment's game server owns only
## Canon and never touches the accounts file. Backward compatible: no migration,
## no data movement, existing combined deployments are untouched.
const CANON_DB_PATH_ENV_VAR: String = "PROJECT0_CANON_DB_PATH"

## Maximum concurrently connected peers supported on this server instance.
## Additional connection attempts beyond this limit are rejected (see
## _on_peer_connected below).
const MAX_REPLICATED_PEERS: int = 10
const JOURNEY_CHECKPOINT_INTERVAL_MSEC: int = 10_000
const JOURNEY_CHECKPOINT_DISTANCE_UNITS: float = 1.0

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

## Slice 146: peers that have connected but not yet passed the version gate,
## keyed by peer id. They hold an ENet slot and nothing else — no world, no
## Player, no replication — until their handshake is accepted.
var _pending_version_gate: Dictionary = {}

## Slice 146: the server-owned version gate, resolved once before the socket
## binds. The server refuses to start when the requirement is unusable.
var _required_client_version: String = ""
var _update_manifest_base_url: String = ""

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

## Slice 131: the live town-NPC population runtime (server_town_npc_manager.gd),
## staffing the town's fixed anchors and driven each physics frame like monsters.
var _town_npc_manager: Object = null
var _town_npc_tick: int = 0

## Slice 040: the shared server-owned SQLite handle and the Account/Character
## repository/auth dispatch built on top of it. Opened/wired during
## _start_server() before the socket opens; a DB-open failure refuses to
## start the server (fail-closed, matching the existing hub-fixture check).
var _accounts_store: SqliteStore = null
var _account_repository: Object = null
var _character_service: Object = null
var _login_gateway: Object = null
var _nakama_session_validator: Node = null
var _world_entry_tickets: Object = null
var _journey_registry: Object = null
var _journey_repository: Object = null
var _last_journey_checkpoint_msec_by_peer: Dictionary = {}
var _last_journey_checkpoint_position_by_peer: Dictionary = {}
var _nakama_gameplay_bridge: Object = null
var _nakama_gameplay_relay: Node = null
var _operator_control_endpoint: Node = null
var _operator_control_service: Object = null
var _canon_repository: Object = null
var _canon_mutation_repository: Object = null
var _canon_mutation_service: Object = null
## Slice 079: only opened when PROJECT0_CANON_DB_PATH is set; otherwise Canon
## reuses _accounts_store and this stays null.
var _canon_store: SqliteStore = null
var _provisional_sector_generator: Node = null
var _sector_boundary_detector: Object = null
var _canon_generation_coordinator: Object = null
var _sector_ingress_positions: Dictionary = {}
var _jit_peer_by_sector: Dictionary = {}
var _jit_root_trace_by_sector: Dictionary = {}
var _jit_commit_trace_by_sector: Dictionary = {}
var _jit_presentation_ack_tracker: Object = JitPresentationAckTrackerScript.new()
var _frontier_versions: Dictionary = {}
var _frontier_bindings: Dictionary = {}
var _frontier_town_tiles: Dictionary = {}
const FRONTIER_PREPARATION_RETRY_MSEC: int = 1000
var _frontier_prepared_at_by_peer: Dictionary = {}
var _frontier_ack_limiter: Object = TelemetryRateLimiterScript.new()

## Slice 162 (telemetry map #282): the dedicated telemetry database and its
## per-peer rate limiter. Best-effort, non-fatal: unlike accounts/Canon,
## telemetry is diagnostic infrastructure and must never block the core game
## server from booting or running. A DB-open failure logs an operator-facing
## error and leaves `_telemetry_sink` null; every subsequent emit attempt is
## then a silent no-op rather than a crash.
var _telemetry_store: SqliteStore = null
var _telemetry_sink: Object = null
var _telemetry_rate_limiter: Object = null
var _telemetry_ingest: Object = null

## Fixed simulation delta used to drive monster chase movement each physics
## frame (the SceneTree physics_frame signal carries no delta). DT-013: derived
## from the authoritative tick rate, not a hardcoded 1/60 — a constant delta
## would scale monster speed with any rate change.
var _monster_tick_delta: float = 1.0 / float(ServerHealthScript.DEFAULT_TICK_RATE)


## Slice 067: runtime health-file state. The path and the resolved (reported)
## tick rate are read from the environment once at boot; the status transitions
## starting -> healthy -> stopping over the server's life. Snapshot inputs are
## authoritative runtime values, never client-supplied.
var _health_file_path: String = ""
var _ops_snapshot_file_path: String = ""
var _server_version: String = ""
var _health_tick_rate: int = ServerHealthScript.DEFAULT_TICK_RATE
var _health_status: String = ServerHealthScript.STATUS_STARTING
var _boot_ticks_ms: int = 0


func _initialize() -> void:
	call_deferred("_start_server")


## Public seam: starts listening and wires connection signals. Deferred past
## _initialize() because SceneTree.root's multiplayer API is not yet attached
## when _initialize() runs.
func _start_server() -> void:
	# Slice 067: begin publishing the runtime health file before any slow boot
	# work (e.g. the opt-in LLM-at-boot town) so an orchestrator sees `starting`
	# immediately. Path and reported tick rate come from the environment once.
	_health_file_path = HealthReporterScript.resolve_health_file_path(OS.get_environment("PROJECT0_HEALTH_FILE"))
	_ops_snapshot_file_path = HealthReporterScript.resolve_health_file_path(OS.get_environment("PROJECT0_OPS_SNAPSHOT_FILE"))
	_server_version = OS.get_environment("PROJECT0_SERVER_VERSION").strip_edges()
	if _server_version.is_empty():
		_server_version = "development"
	_health_tick_rate = ServerHealthScript.resolve_tick_rate(OS.get_environment("PROJECT0_TICK_RATE"))
	# DT-013: ServerHealth resolves the contracted rate but Slice 055 deferred
	# applying it, so the server ran at Godot's 60 Hz default while advertising
	# 30. Drive the engine from the same resolved value the health snapshot
	# reports so the advertised and actual authoritative tick cannot diverge.
	Engine.physics_ticks_per_second = _health_tick_rate
	_monster_tick_delta = 1.0 / float(_health_tick_rate)
	_boot_ticks_ms = Time.get_ticks_msec()
	_write_health(ServerHealthScript.STATUS_STARTING)

	# Slice 016: materialize the starting town hub fixture before opening a
	# socket. It is static data, so validation is synchronous and cheap; a
	# fixture that fails its own schema is a programming error, so fail closed
	# (refuse to start) rather than silently degrading to an empty world.
	var hub: Dictionary = StartingTownHubFixtureScript.materialize(StartingTownHubFixtureScript.blueprint())
	if not hub["ok"]:
		push_error("Refusing to start: starting town hub fixture failed validation: %s — %s" % [hub["outcome"], hub["detail"]])
		quit(1)
		return
	var fixture_blueprint: Dictionary = hub["blueprint"]
	print("Starting town hub fixture validated: %d structures." % (fixture_blueprint["structures"] as Array).size())

	# Slice 052: default-off opt-in. When PROJECT0_LLM_TOWN_AT_BOOT=1, await the
	# LLM-proposed/server-guaranteed town (Slice 026's TownLayoutProvider) before
	# opening the socket; on any transport/timeout/invalid-output failure it
	# falls back to the validated fixture above, so boot can never yield an
	# unusable town. _start_server() already runs deferred from _initialize(),
	# so this await only delays when the socket opens, not SceneTree
	# responsiveness. Accepted tradeoff: opt-in boot latency bounded by
	# LocalLLMClient's configured request timeout (see the slice doc).
	_starting_town_hub_blueprint = fixture_blueprint
	if TownLayoutProviderScript.llm_at_boot_enabled():
		var llm_client: Node = LocalLLMClientScript.new()
		llm_client.name = "BootTownLLMClient"
		llm_client.configure_from_env()
		root.add_child(llm_client)
		var boot_town: Dictionary = await TownLayoutProviderScript.resolve_boot_town(true, llm_client, fixture_blueprint)
		_starting_town_hub_blueprint = boot_town["blueprint"]
		print("LLM-at-boot town: source=%s outcome=%s." % [boot_town["source"], boot_town["outcome"]])
		llm_client.queue_free()

	# Slice 030: build the server-side collision map (solid walls + building
	# footprints) from the validated hub, injected into each peer below.
	_town_collision = SectorCollisionMapScript.new(_starting_town_hub_blueprint)
	print("Town collision map ready: %d solid cells." % _town_collision.blocked_count())

	# Slice 019: build the house pool from the validated hub so each peer can be
	# assigned a unique house on connect.
	_house_allocator = HouseAllocatorScript.new(HouseAllocatorScript.house_ids_from_blueprint(_starting_town_hub_blueprint))
	print("Starting town house pool ready: %d houses." % _house_allocator.pool_size())

	# Slice 022: spawn monsters from the hub's spawn points (authored outside the
	# town wall) and drive their AI each physics frame. Slice 053: the exclusion
	# half-extent is derived from the actual validated town's tile bounds
	# (rather than a hard-coded constant) so any town size keeps monsters just
	# outside its walls.
	var exclusion_half_extent: float = ServerMonsterManagerScript.town_exclusion_half_extent(_starting_town_hub_blueprint)
	print("Monster exclusion half-extent derived from town: %.1f yd." % exclusion_half_extent)
	_monster_manager = ServerMonsterManagerScript.new(_starting_town_hub_blueprint.get("spawn_points", []), int(Time.get_ticks_usec()), ServerMonsterManagerScript.RESPAWN_COOLDOWN_TICKS, exclusion_half_extent)
	_monster_manager.monster_died.connect(_on_monster_died)
	_monster_manager.monster_respawned.connect(_on_monster_respawned)
	_monster_manager.player_hit.connect(_on_monster_player_hit)
	physics_frame.connect(_on_physics_frame)
	print("Spawned %d monsters outside the town." % _monster_manager.monster_count())

	# Slice 131: staff the town's fixed anchors with live town NPCs, driven each
	# physics frame. Anchors are a first-cut fixed set inside the town center; a
	# later slice can derive them from the town blueprint's structures.
	_town_npc_manager = ServerTownNpcManagerScript.new(_default_town_anchor_defs(), int(Time.get_ticks_usec()))
	_town_npc_manager.npc_spawned.connect(_on_town_npc_spawned)
	_town_npc_manager.npc_removed.connect(_on_town_npc_removed)
	print("Staffed %d town NPCs across %d anchors." % [_town_npc_manager.npc_count(), _town_npc_manager.anchor_count()])

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
	_journey_repository = JourneyRepositoryScript.new(_accounts_store)
	var journey_schema_result: Dictionary = _journey_repository.ensure_schema()
	if journey_schema_result["outcome"] != JourneyRepositoryScript.OUTCOME_OK:
		push_error("Refusing to start: journey schema failed to initialize: %s — %s" % [journey_schema_result["outcome"], journey_schema_result["detail"]])
		quit(1)
		return
	# Slice 045: Canon shares the one server-owned SQLite handle with accounts.
	# The validated hub is canonicalized before the socket opens, so every peer
	# sees a world record that survives a server restart.
	# Slice 079: when PROJECT0_CANON_DB_PATH is set, Canon opens its own store so
	# a split deployment isolates the world record from the accounts file. Unset
	# preserves the Slice 045 shared-handle default (no migration).
	var canon_store: SqliteStore = _accounts_store
	var canon_db_path: String = OS.get_environment(CANON_DB_PATH_ENV_VAR).strip_edges()
	if not canon_db_path.is_empty():
		_canon_store = SqliteStoreScript.new()
		var canon_open_result: Dictionary = _canon_store.open(canon_db_path)
		if canon_open_result["outcome"] != SqliteStoreScript.OUTCOME_OK:
			push_error("Refusing to start: Canon database failed to open: %s — %s" % [canon_open_result["outcome"], canon_open_result["detail"]])
			quit(1)
			return
		canon_store = _canon_store
	_canon_repository = CanonRepositoryScript.new(canon_store)
	var canon_schema_result: Dictionary = _canon_repository.ensure_schema()
	if canon_schema_result["outcome"] != "ok":
		push_error("Refusing to start: Canon schema failed to initialize: %s — %s" % [canon_schema_result["outcome"], canon_schema_result["detail"]])
		quit(1)
		return
	# Slice 080: one-time Canon migration for the combined→split transition. On
	# the first boot with a dedicated (empty) canon store, copy any existing
	# Canon out of the shared accounts store so a previously-combined world is
	# not lost. Source rows are never deleted; a re-boot finds the dest non-empty
	# and skips. Unset (shared handle) never migrates.
	if not canon_db_path.is_empty():
		var dest_records: Dictionary = _canon_repository.list_all_records()
		if dest_records["outcome"] == CanonRepositoryScript.OUTCOME_OK and (dest_records["records"] as Array).is_empty():
			var source_canon: Object = CanonRepositoryScript.new(_accounts_store)
			source_canon.ensure_schema()
			var source_records: Dictionary = source_canon.list_all_records()
			if source_records["outcome"] == CanonRepositoryScript.OUTCOME_OK:
				var migrated: int = 0
				for record: Dictionary in source_records["records"]:
					if _canon_repository.restore_record(record)["outcome"] == CanonRepositoryScript.OUTCOME_OK:
						migrated += 1
				if migrated > 0:
					print("Migrated %d Canon sector(s) from the accounts store into %s." % [migrated, canon_db_path])
	var canon_result: Dictionary = _canon_repository.canonicalize_blueprint(_starting_town_hub_blueprint)
	if canon_result["outcome"] != CanonRepositoryScript.OUTCOME_OK and canon_result["outcome"] != CanonRepositoryScript.OUTCOME_IDEMPOTENT:
		push_error("Refusing to start: starting town Canon failed: %s — %s" % [canon_result["outcome"], canon_result["detail"]])
		quit(1)
		return
	var canon_db_label: String = canon_db_path if not canon_db_path.is_empty() else ("shared:%s" % accounts_db_path)
	print("Starting town Canon ready: %s (canon db: %s)." % [canon_result["outcome"], canon_db_label])

	# Slice 050/097: the durable Canon mutation log and the server-authoritative
	# resolution service, on the same store as Canon. Fail closed on a schema
	# failure, matching the Canon boot checks above.
	_canon_mutation_repository = CanonMutationRepositoryScript.new(canon_store, _canon_repository)
	var mutation_schema: Dictionary = _canon_mutation_repository.ensure_schema()
	if mutation_schema["outcome"] != "ok":
		push_error("Refusing to start: Canon mutation schema failed: %s — %s" % [mutation_schema["outcome"], mutation_schema["detail"]])
		quit(1)
		return
	_canon_mutation_service = CanonMutationServiceScript.new(_canon_mutation_repository, Callable(self, "_current_server_tick"))
	# Slice 046: authoritative movement now drives non-blocking JIT requests for
	# unexplored sectors. The detector performs only cheap sector math and the
	# generator accepts work synchronously before awaiting Ollama in a deferred
	# coroutine.
	_provisional_sector_generator = ProvisionalSectorGeneratorScript.new()
	_provisional_sector_generator.name = "ProvisionalSectorGenerator"
	root.add_child(_provisional_sector_generator)
	_canon_generation_coordinator = CanonGenerationCoordinatorScript.new()
	_canon_generation_coordinator.set_canonicalize_callback(Callable(_canon_repository, "canonicalize_blueprint"))
	_provisional_sector_generator.provisional_sector_ready.connect(_on_provisional_sector_ready)
	_sector_boundary_detector = SectorBoundaryDetectorScript.new()
	_sector_boundary_detector.set_canon_lookup(Callable(_canon_repository, "get_canonical_sector"))
	_sector_boundary_detector.set_request_callback(Callable(self, "_request_sector_from_boundary"))
	_sector_boundary_detector.set_reload_callback(Callable(self, "_reload_sector_from_boundary"))
	# Slice 085: the game server builds an assertion-only login graph (no
	# AuthService, no register/login/PBKDF2 in this process). Accounts live only
	# on the standalone login process; a client enters the world by presenting a
	# signed assertion. The shared LoginRuntime wires the same assertion seams the
	# login process issues under.
	var login_services: Dictionary = LoginRuntimeScript.build_assertion_only_services(_account_repository, root, LoginRuntimeScript.resolve_assertion_secret(), LoginRuntimeScript.ASSERTION_ISSUER_ID, LoginRuntimeScript.ASSERTION_AUDIENCE)
	_character_service = login_services["characters"]
	_login_gateway = login_services["gateway"]
	_journey_registry = JourneyRegistryScript.new()
	_journey_registry.set_repository(_journey_repository)
	var journey_records: Dictionary = _journey_repository.load_all()
	if journey_records["outcome"] != JourneyRepositoryScript.OUTCOME_OK:
		push_error("Refusing to start: journey records failed to load: %s — %s" % [journey_records["outcome"], journey_records["detail"]])
		quit(1)
		return
	_journey_registry.restore_records(journey_records["records"])
	_journey_registry.evidence.connect(_on_journey_evidence)
	_login_gateway.set_journey_registry(_journey_registry)
	_nakama_session_validator = NakamaSessionValidatorScript.new()
	_nakama_session_validator.name = "NakamaSessionValidator"
	root.add_child(_nakama_session_validator)
	_world_entry_tickets = WorldEntryTicketServiceScript.new(
		login_services["issuer"], login_services["validator"], login_services["sessions"], _character_service
	)
	root.set_meta("world_entry_tickets", _world_entry_tickets)
	_nakama_gameplay_relay = NakamaGameplayRelayScript.new(null)
	_nakama_gameplay_relay.name = "NakamaGameplayRelay"
	_nakama_gameplay_bridge = NakamaGameplayBridgeScript.new(_nakama_gameplay_relay)
	_nakama_gameplay_relay.set_bridge(_nakama_gameplay_bridge)
	root.add_child(_nakama_gameplay_relay)
	_nakama_gameplay_relay.call_deferred("start_from_environment")
	var operator_validator: Object = AssertionValidatorScript.new(
		LoginRuntimeScript.resolve_assertion_secret(), "project0-console", "project0-console"
	)
	_operator_control_service = OperatorControlServiceScript.new()
	var operator_adapter: Object = OperatorControlAdapterScript.new(operator_validator, _operator_control_service)
	_operator_control_endpoint = OperatorControlHttpEndpointScript.new(operator_adapter)
	_operator_control_endpoint.name = "OperatorControlHttpEndpoint"
	root.add_child(_operator_control_endpoint)
	var operator_control_port: int = int(OS.get_environment("PROJECT0_OPERATOR_CONTROL_PORT")) if OS.get_environment("PROJECT0_OPERATOR_CONTROL_PORT").is_valid_int() else 8097
	var operator_control_bound_port: int = _operator_control_endpoint.start(operator_control_port)
	if operator_control_bound_port < 0:
		push_error("Operator control HTTP endpoint failed to bind internal port %d." % operator_control_port)
	else:
		print("Operator control HTTP endpoint listening on internal port %d." % operator_control_bound_port)
	print("Accounts database ready at user://%s (schema ensured); assertion-only game server (accounts live on the login process)." % accounts_db_path)

	# Slice 162 (telemetry map #282): open the dedicated telemetry database and
	# rate limiter. Best-effort — a failure here is operator-facing (Andon) and
	# never refuses server start, since telemetry is diagnostic infrastructure,
	# not durable game state.
	_telemetry_store = SqliteStoreScript.new()
	var telemetry_open_result: Dictionary = _telemetry_store.open(TelemetrySinkScript.resolve_db_path())
	if telemetry_open_result["outcome"] != SqliteStoreScript.OUTCOME_OK:
		push_error("Telemetry database failed to open (non-fatal): %s — %s" % [telemetry_open_result["outcome"], telemetry_open_result["detail"]])
		_telemetry_store = null
	else:
		var telemetry_sink: Object = TelemetrySinkScript.new(_telemetry_store)
		var telemetry_schema_result: Dictionary = telemetry_sink.ensure_schema()
		if telemetry_schema_result["outcome"] != TelemetrySinkScript.OUTCOME_OK:
			push_error("Telemetry schema failed to initialize (non-fatal): %s — %s" % [telemetry_schema_result["outcome"], telemetry_schema_result["detail"]])
			_telemetry_store.close()
			_telemetry_store = null
		else:
			_telemetry_sink = telemetry_sink
			print("Telemetry database ready at user://%s." % TelemetrySinkScript.resolve_db_path())
	_telemetry_rate_limiter = TelemetryRateLimiterScript.new()
	if _telemetry_sink != null:
		_telemetry_ingest = TelemetryIngestServiceScript.new(_telemetry_sink, _telemetry_rate_limiter)

	var bind_address: String = NetworkConfigScript.resolve_server_bind_address()
	var server_port: int = NetworkConfigScript.resolve_server_port()

	# Slice 146: resolve the version gate BEFORE binding. An unusable requirement
	# is an operator fault, and a server that cannot say what it serves must not
	# serve at all rather than refuse every client as "outdated".
	_required_client_version = VersionHandshakeScript.resolve_required_version()
	_update_manifest_base_url = VersionHandshakeScript.resolve_manifest_base_url()
	if _required_client_version.is_empty():
		push_error(
			"Refusing to start: %s is set to a malformed client build version."
			% VersionHandshakeScript.REQUIRED_VERSION_ENV_VAR
		)
		quit(1)
		return
	print("Version gate: requiring client build version %s." % _required_client_version)

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
	var mutation_network_client: Node = root.get_node_or_null("NetworkClient")
	if mutation_network_client != null:
		mutation_network_client.canon_mutation_intent_received.connect(_on_canon_mutation_intent)
		mutation_network_client.version_handshake_received.connect(_on_version_handshake_received)
		mutation_network_client.client_telemetry_batch_received.connect(_on_client_telemetry_batch_received)
	_spawn_target_dummies()
	print("Server listening on %s:%d" % [bind_address, server_port])
	# Slice 067: the tick loop is up and the socket is bound — report healthy.
	_write_health(ServerHealthScript.STATUS_HEALTHY)
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
	# Slice 146: connecting no longer admits. The peer gets no world, no Player,
	# and no replication until it passes the server-owned version gate.
	_emit_server_telemetry("connection.peer_connected", peer_id, {})
	_pending_version_gate[peer_id] = true


## Slice 146: decides one peer's version handshake, the first message a client
## sends and the gate every later RPC depends on. Fail-closed: only an ACCEPTED
## outcome admits, and a rejected peer is told why (so it can self-patch) and
## then disconnected. The disconnect is graceful so the reliable rejection is
## flushed before the socket closes.
func _on_version_handshake_received(peer_id: int, handshake: Dictionary) -> void:
	if not _pending_version_gate.has(peer_id):
		# Already admitted (or already refused): a resent handshake changes nothing.
		return
	var result: Dictionary = VersionHandshakeScript.evaluate(
		handshake, _required_client_version, _update_manifest_base_url
	)
	_pending_version_gate.erase(peer_id)
	if result["outcome"] != VersionHandshakeScript.OUTCOME_ACCEPTED:
		_emit_server_telemetry("connection.version_gate_rejected", peer_id, {
			"outcome": String(result["outcome"]),
			"detail": String(result["detail"]),
			"client_version": String(handshake.get("client_build_version", "")),
		})
		var network_client: Node = root.get_node_or_null("NetworkClient")
		if network_client != null:
			network_client.rpc_id(peer_id, "receive_version_handshake_rejected", result)
		root.multiplayer.multiplayer_peer.disconnect_peer(peer_id)
		return
	_emit_server_telemetry("connection.version_gate_passed", peer_id, {"client_version": String(handshake.get("client_build_version", ""))})
	_admit_peer(peer_id)


## Admits a peer that passed the version gate: replicates the world to it and
## gives it an authoritative Player. Previously the body of _on_peer_connected.
func _admit_peer(peer_id: int) -> void:
	var network_client: Node = root.get_node("NetworkClient")
	var start_position: Vector3 = _start_position_for_slot(_player_states.size())

	if _player_states.size() >= MAX_REPLICATED_PEERS:
		push_error("Rejecting peer %d: already at MAX_REPLICATED_PEERS (%d)" % [peer_id, MAX_REPLICATED_PEERS])
		root.multiplayer.multiplayer_peer.disconnect_peer(peer_id)
		return

	var player_state: Node = ServerPlayerStateScript.new()
	_player_states[peer_id] = player_state
	_configure_player_frontier(peer_id, player_state)

	# Slice 017: replicate the validated starting town hub to this peer before
	# spawning any Player, so the world exists before its occupants. All these
	# RPCs are reliable, so ordering is guaranteed.
	_present_frontier_sector(peer_id, String(_starting_town_hub_blueprint.get("sector_id", "")), _starting_town_hub_blueprint, start_position, {})
	print("Sent starting town hub blueprint to peer %d (sector_id=%s)." % [peer_id, _starting_town_hub_blueprint.get("sector_id", "")])

	network_client.rpc_id(peer_id, "spawn_own_player_representation")

	player_state.name = "ServerPlayerState_%d" % peer_id
	player_state.position_updated.connect(_on_player_state_position_updated)
	player_state.action_resolved.connect(_on_player_state_action_resolved)
	player_state.combat_event_emitted.connect(_on_player_state_combat_event_emitted)
	player_state.melee_swing_started.connect(_on_player_state_melee_swing_started)
	player_state.character_bound.connect(_on_player_state_character_bound)
	player_state.health_changed.connect(_on_player_state_health_changed)
	player_state.character_snapshot_ready.connect(_on_player_state_character_snapshot_ready)
	player_state.effective_mechanics_ready.connect(_on_player_state_effective_mechanics_ready)
	player_state.player_defeated.connect(_on_player_state_player_defeated)
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

	# Slice 019: assign this peer a unique house from the pool and tell only the
	# owning client. Fail closed (log) if the pool is somehow exhausted — this is
	# unreachable while the pool size matches MAX_REPLICATED_PEERS.
	var house_id: String = _house_allocator.assign(peer_id)
	if house_id.is_empty():
		push_error("Peer %d connected but no house slot is available (pool exhausted)." % peer_id)
		_emit_server_telemetry("connection.house_unavailable", peer_id, {"houses_free": _house_allocator.available_count()})
	else:
		_emit_server_telemetry("connection.house_assigned", peer_id, {"house_id": house_id, "houses_free_after": _house_allocator.available_count()})
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
		# Slice 086: if that peer already entered the world, replicate its bound
		# Character identity to the newly-connected peer. Reliable and ordered
		# after the spawn above, so the RemotePlayer node exists when it arrives.
		if not String(existing_state.character_display_name).is_empty():
			network_client.rpc_id(peer_id, "receive_remote_player_identity", existing_peer_id, existing_state.character_display_name, existing_state.character_cosmetic)

	# Slice 033: replicate every currently living monster to the new peer only
	# — existing peers already have a representation for each from their own
	# connect (or the initial spawn) and do not need it re-sent.
	if _monster_manager != null:
		var living: Dictionary = _monster_manager.living_targets()
		for target_id: String in living.keys():
			var monster: Object = living[target_id]
			network_client.rpc_id(peer_id, "receive_monster_spawn", target_id, monster.position)

	# Slice 131: replicate every live town NPC to the newly-connected peer only.
	if _town_npc_manager != null:
		for npc: Variant in _town_npc_manager.all_npcs():
			network_client.rpc_id(peer_id, "receive_town_npc_spawn", (npc as Object).npc_id, (npc as Object).position_at(_town_npc_tick))

	_broadcast_presence_snapshot()


## Called whenever a client peer disconnects. Removes that peer's
## ServerPlayerState entirely (Slice 007: no longer just unbinds a shared
## instance, since each peer now owns its own) and tells every remaining
## peer to despawn that departed peer's remote representation.
func _on_peer_disconnected(peer_id: int) -> void:
	# A peer can drop while still awaiting the version gate; it owns nothing else.
	_pending_version_gate.erase(peer_id)
	var disconnected_identity: Dictionary = _login_gateway.get_presence_identity(peer_id) if _login_gateway != null else {}
	var player_state: Node = _player_states.get(peer_id)
	if _journey_registry != null and player_state != null and not String(player_state.character_id).is_empty():
		_journey_registry.mark_disconnected(String(player_state.character_id), peer_id, int(Time.get_unix_time_from_system()))
	if _nakama_gameplay_relay != null:
		_nakama_gameplay_relay.unbind_world_entry(String(disconnected_identity.get("account_id", "")))
	# Slice 040: clear this peer's in-memory session, if any. Sessions are
	# never persisted, so a reconnecting peer always finds no session and must
	# fully re-authenticate — see server/session_registry.gd.
	if _login_gateway != null:
		_login_gateway.clear_session(peer_id)
	# Slice 019: free this peer's house back to the pool immediately (no
	# reconnect reservation).
	var had_house: bool = false
	if _house_allocator != null:
		had_house = not _house_allocator.assigned_house(peer_id).is_empty()
		_house_allocator.release(peer_id)
	_emit_server_telemetry("connection.peer_disconnected", peer_id, {
		"had_house": had_house,
		"houses_free_after": _house_allocator.available_count() if _house_allocator != null else 0,
	})
	if player_state != null:
		player_state.position_updated.disconnect(_on_player_state_position_updated)
		player_state.action_resolved.disconnect(_on_player_state_action_resolved)
		player_state.combat_event_emitted.disconnect(_on_player_state_combat_event_emitted)
		player_state.melee_swing_started.disconnect(_on_player_state_melee_swing_started)
		player_state.character_bound.disconnect(_on_player_state_character_bound)
		player_state.health_changed.disconnect(_on_player_state_health_changed)
		player_state.character_snapshot_ready.disconnect(_on_player_state_character_snapshot_ready)
		player_state.effective_mechanics_ready.disconnect(_on_player_state_effective_mechanics_ready)
		player_state.player_defeated.disconnect(_on_player_state_player_defeated)
		_player_states.erase(peer_id)
		player_state.queue_free()
	_last_journey_checkpoint_msec_by_peer.erase(peer_id)
	_last_journey_checkpoint_position_by_peer.erase(peer_id)
	if _sector_boundary_detector != null:
		_sector_boundary_detector.forget_peer(peer_id)
	_jit_presentation_ack_tracker.forget_peer(peer_id)
	_frontier_bindings.erase(peer_id)
	_frontier_prepared_at_by_peer.erase(peer_id)
	_frontier_ack_limiter.forget_peer(peer_id)
	for sector_id: String in _sector_ingress_positions.keys():
		var ingresses: Dictionary = _sector_ingress_positions[sector_id]
		ingresses.erase(peer_id)
	if _telemetry_rate_limiter != null:
		_telemetry_rate_limiter.forget_peer(peer_id)

	var network_client: Node = root.get_node_or_null("NetworkClient")
	if network_client == null:
		return
	_broadcast_presence_snapshot()
	for remaining_peer_id: int in _player_states.keys():
		network_client.rpc_id(remaining_peer_id, "despawn_remote_player_representation", peer_id)


## Slice 171: builds one server-authored snapshot for the single shared v1 world
## and sends it to every admitted peer after join/leave membership changes.
func _broadcast_presence_snapshot() -> void:
	var network_client: Node = root.get_node_or_null("NetworkClient")
	if network_client == null:
		return
	var entries: Array[Dictionary] = []
	for peer_id: int in _player_states.keys():
		var player_state: Node = _player_states[peer_id]
		var identity: Dictionary = _login_gateway.get_presence_identity(peer_id) if _login_gateway != null else {}
		var peer_entry: Dictionary = NakamaPresenceScript.bound_entry(peer_id, identity, String(player_state.character_display_name))
		if not peer_entry.is_empty():
			entries.append(peer_entry)
	var snapshot: Dictionary = NakamaPresenceScript.build(entries, true)
	for peer_id: int in _player_states.keys():
		network_client.rpc_id(peer_id, "receive_presence_snapshot", snapshot)


## Relays one peer's authoritative position to every other connected peer so
## each client's remote representation of that peer can be updated. Never
## sent back to the owning peer itself, which already receives its own
## authoritative position (plus sequence acknowledgement) directly from
## ServerPlayerState._physics_process via receive_authoritative_position.
func _on_player_state_position_updated(peer_id: int, updated_position: Vector3) -> void:
	if _sector_boundary_detector != null:
		_sector_boundary_detector.commit_position(peer_id, updated_position)
	var last_position: Vector3 = _last_journey_checkpoint_position_by_peer.get(peer_id, updated_position)
	if last_position.distance_squared_to(updated_position) >= JOURNEY_CHECKPOINT_DISTANCE_UNITS * JOURNEY_CHECKPOINT_DISTANCE_UNITS:
		_checkpoint_journey(peer_id, updated_position)
	var network_client: Node = root.get_node_or_null("NetworkClient")
	if network_client == null:
		return
	for other_peer_id: int in _player_states.keys():
		if other_peer_id == peer_id:
			continue
		network_client.rpc_id(other_peer_id, "receive_remote_player_position", peer_id, updated_position)


## Slice 086: replicates a peer's bound Character identity (display name +
## cosmetic) to every other connected peer when it enters the world, so each
## client can label that peer's remote representation as the selected Character.
## Identity only — never a trusted position or outcome.
func _on_player_state_character_bound(peer_id: int, display_name: String, cosmetic: Dictionary) -> void:
	var player_state: Node = _player_states.get(peer_id)
	if player_state != null:
		_configure_player_frontier(peer_id, player_state)
		_present_current_frontier(peer_id, player_state.position)
	var network_client: Node = root.get_node_or_null("NetworkClient")
	if network_client == null:
		return
	for other_peer_id: int in _player_states.keys():
		if other_peer_id == peer_id:
			continue
		network_client.rpc_id(other_peer_id, "receive_remote_player_identity", peer_id, display_name, cosmetic)
	_broadcast_presence_snapshot()


func _request_sector_from_boundary(peer_id: int, sector_id: String, position: Vector3, trace: Dictionary = {}) -> void:
	var generation_started_usec: int = int(trace.get("generation_started_usec", Time.get_ticks_usec()))
	if _provisional_sector_generator == null:
		return
	var sector_ingresses: Dictionary = _sector_ingress_positions.get(sector_id, {})
	sector_ingresses[peer_id] = position
	_sector_ingress_positions[sector_id] = sector_ingresses
	if _provisional_sector_generator.get_status(sector_id) == ProvisionalSectorGeneratorScript.STATUS_READY:
		var cached_result: Dictionary = _provisional_sector_generator.get_provisional_result(sector_id).duplicate(true)
		cached_result.erase("trace_spans")
		_jit_peer_by_sector[sector_id] = peer_id
		_on_provisional_sector_ready(sector_id, cached_result)
		return
	var starts_generation: bool = (
		_provisional_sector_generator.get_status(sector_id)
		== ProvisionalSectorGeneratorScript.STATUS_UNKNOWN
	)
	if not starts_generation and _jit_peer_by_sector.has(sector_id):
		return
	if starts_generation:
		_jit_peer_by_sector[sector_id] = peer_id
		_jit_root_trace_by_sector[sector_id] = trace.duplicate(true)
		_emit_jit_trace(trace, peer_id)
	var initiating_trace: Dictionary = _jit_root_trace_by_sector.get(sector_id, trace)
	initiating_trace["generation_started_usec"] = generation_started_usec
	var prompt: String = _sector_generation_prompt(sector_id)
	var selected_profile: String = _select_sector_profile(sector_id)
	var correlation_id: String = _provisional_sector_generator.request_provisional_sector(sector_id, prompt, selected_profile, initiating_trace)
	print("Requested provisional sector %s for peer %d (%s)." % [sector_id, peer_id, correlation_id])


static func _select_sector_profile(_sector_id: String) -> String:
	return SectorArchetypeAdmissionScript.PROFILE_WILDERNESS


## Gives the model the bounded candidate shape; the schema gate remains the
## authority for accepting generated content.
static func _sector_generation_prompt(sector_id: String) -> String:
	var bound: int = SectorBlueprintSchemaScript.MAX_COORDINATE_ABS
	return "\n".join([
		"Return ONLY one JSON object (no prose, no thinking) describing a sector blueprint.",
		"Required shape:",
		"- \"schema_version\": 3",
		"- \"sector_id\": \"%s\"" % sector_id,
		"- \"origin\": {\"x\": 0, \"y\": 0}",
		"- \"tiles\": 1..%d entries of {\"x\": int, \"y\": int, \"kind\": string}; x and y within -%d..%d;" % [
			SectorBlueprintSchemaScript.MAX_TILE_COUNT, bound, bound,
		],
		"  kind is one of %s." % ", ".join(SectorBlueprintSchemaScript.SUPPORTED_TILE_KINDS),
		"Output valid JSON only.",
	])


func _reload_sector_from_boundary(peer_id: int, sector_id: String, position: Vector3, trace: Dictionary = {}) -> void:
	if _canon_repository == null:
		return
	var canon_result: Dictionary = _canon_repository.get_canonical_sector(sector_id)
	if canon_result["outcome"] != CanonRepositoryScript.OUTCOME_OK:
		return
	_emit_jit_trace(trace, peer_id)
	var blueprint: Dictionary = canon_result["sector"]["blueprint"]
	_present_frontier_sector(peer_id, sector_id, blueprint, position, trace)
	print("CANON_SECTOR_RELOADED sector_id=%s peer_id=%d" % [sector_id, peer_id])


func _on_provisional_sector_ready(sector_id: String, result: Dictionary) -> void:
	if _canon_generation_coordinator == null:
		return
	var peer_id: int = int(_jit_peer_by_sector.get(sector_id, 0))
	for span: Dictionary in result.get("trace_spans", []):
		_emit_jit_trace(span, peer_id)
	var trace: Dictionary = result.get("trace_context", {})
	var commit_trace: Dictionary = JitTraceContextScript.child(trace, "canon_db_commit") if not trace.is_empty() else {}
	var finalization: Dictionary = _canon_generation_coordinator.accept_generation_result(
		sector_id,
		result.get("selected_profile", ""),
		result
	)
	if not commit_trace.is_empty():
		commit_trace["status"] = "OK" if finalization["outcome"] in [CanonGenerationCoordinatorScript.OUTCOME_CANONICALIZED, CanonGenerationCoordinatorScript.OUTCOME_IDEMPOTENT] else "ERROR"
		_emit_jit_trace(commit_trace, peer_id)
	if finalization["outcome"] == CanonGenerationCoordinatorScript.OUTCOME_IGNORED:
		print("Ignored provisional sector %s: %s" % [sector_id, finalization["detail"]])
	elif finalization["outcome"] == CanonGenerationCoordinatorScript.OUTCOME_CONFLICT:
		push_warning("Rejected conflicting provisional sector %s: %s" % [sector_id, finalization["detail"]])
	else:
		_jit_commit_trace_by_sector[sector_id] = commit_trace
		_on_canonical_sector_ready(sector_id, finalization["blueprint"])
	_jit_commit_trace_by_sector.erase(sector_id)
	_jit_root_trace_by_sector.erase(sector_id)
	_jit_peer_by_sector.erase(sector_id)


func _on_canonical_sector_ready(sector_id: String, blueprint: Dictionary) -> void:
	var commit_trace: Dictionary = _jit_commit_trace_by_sector.get(sector_id, {})
	var sector_ingresses: Dictionary = _sector_ingress_positions.get(sector_id, {})
	for peer_id: int in sector_ingresses.keys():
		var ingress: Vector3 = sector_ingresses.get(peer_id, Vector3.ZERO)
		_present_frontier_sector(peer_id, sector_id, blueprint, ingress, commit_trace)
	_sector_ingress_positions.erase(sector_id)
	print("Replicated canonical sector %s to %d connected peers." % [sector_id, _player_states.size()])


func _configure_player_frontier(peer_id: int, player_state: Node) -> void:
	_jit_presentation_ack_tracker.forget_peer(peer_id)
	_frontier_prepared_at_by_peer.erase(peer_id)
	if _sector_boundary_detector != null:
		_sector_boundary_detector.forget_peer(peer_id)
	for sector_id: String in _sector_ingress_positions.keys():
		var ingresses: Dictionary = _sector_ingress_positions[sector_id]
		ingresses.erase(peer_id)
	_frontier_bindings[peer_id] = {
		"connection": player_state.get_instance_id(),
		"character": String(player_state.character_id),
		"journey": _frontier_journey_id(peer_id, String(player_state.character_id)),
	}
	player_state.set_movement_admission(Callable(self, "_resolve_frontier_movement"))
	if _frontier_town_tiles.is_empty():
		for tile: Dictionary in _starting_town_hub_blueprint.get("tiles", []):
			_frontier_town_tiles[Vector2i(int(tile["x"]), int(tile["y"]))] = true


func _present_current_frontier(peer_id: int, position: Vector3) -> void:
	_prepare_frontier_position(peer_id, position)


func _frontier_now_msec() -> int:
	return Time.get_ticks_msec()


## Bound replay/ACK-loss recovery independently of physics ticks. This retries
## presentation/preparation, never the generator's single accepted LLM request.
func _prepare_frontier_position(peer_id: int, position: Vector3) -> void:
	var sector_id: String = _frontier_sector_at(position)
	var attempts: Dictionary = _frontier_prepared_at_by_peer.get(peer_id, {})
	if attempts.has(sector_id) and _frontier_now_msec() - int(attempts[sector_id]) < FRONTIER_PREPARATION_RETRY_MSEC:
		return
	_remember_frontier_preparation(peer_id, sector_id)
	if sector_id == String(_starting_town_hub_blueprint.get("sector_id", "")):
		_present_frontier_sector(peer_id, sector_id, _starting_town_hub_blueprint, position, {})
	elif _sector_boundary_detector != null:
		_sector_boundary_detector.forget_preparation(peer_id, sector_id)
		_sector_boundary_detector.prepare_position(peer_id, position)


func _remember_frontier_preparation(peer_id: int, sector_id: String) -> void:
	var attempts: Dictionary = _frontier_prepared_at_by_peer.get(peer_id, {})
	if not attempts.has(sector_id) and attempts.size() >= JitPresentationAckTrackerScript.MAX_PENDING_PER_PEER:
		attempts.erase(attempts.keys()[0])
	attempts[sector_id] = _frontier_now_msec()
	_frontier_prepared_at_by_peer[peer_id] = attempts


func _frontier_binding(peer_id: int, sector_id: String) -> Dictionary:
	var player_state: Node = _player_states.get(peer_id)
	var binding: Dictionary = _frontier_bindings.get(peer_id, {})
	if player_state == null:
		return {}
	if binding.get("connection") != player_state.get_instance_id() or binding.get("character") != String(player_state.character_id) or binding.get("journey") != _frontier_journey_id(peer_id, String(player_state.character_id)):
		_jit_presentation_ack_tracker.forget_peer(peer_id)
		return {}
	if not _frontier_versions.has(sector_id):
		return {}
	var context: Dictionary = binding.duplicate(true)
	context["presentation"] = _frontier_versions[sector_id]
	return context


func _frontier_journey_id(peer_id: int, character_id: String) -> String:
	return _journey_registry.active_journey_id(character_id, peer_id) if _journey_registry != null else ""


func _invalidate_frontier_sector(sector_id: String, clear_preparation: bool = true) -> void:
	_frontier_versions.erase(sector_id)
	for peer_id: int in _player_states.keys():
		_jit_presentation_ack_tracker.forget_presentation(peer_id, sector_id)
		if clear_preparation:
			var attempts: Dictionary = _frontier_prepared_at_by_peer.get(peer_id, {})
			attempts.erase(sector_id)
		if clear_preparation and _sector_boundary_detector != null:
			_sector_boundary_detector.forget_preparation(peer_id, sector_id)


func _frontier_sector_at(position: Vector3) -> String:
	if _frontier_town_tiles.has(Vector2i(floori(position.x + 0.5), floori(position.z + 0.5))):
		return String(_starting_town_hub_blueprint.get("sector_id", ""))
	return SectorBoundaryDetectorScript.sector_id_for_position(position)


func _frontier_position_ready(peer_id: int, position: Vector3) -> bool:
	var sector_id: String = _frontier_sector_at(position)
	return _jit_presentation_ack_tracker.is_ready(peer_id, sector_id, _frontier_binding(peer_id, sector_id))


func _resolve_frontier_movement(peer_id: int, current: Vector3, candidate: Vector3) -> Vector3:
	if _frontier_position_ready(peer_id, candidate):
		return candidate
	_prepare_frontier_position(peer_id, candidate)
	var along_x: Vector3 = Vector3(candidate.x, candidate.y, current.z)
	var along_z: Vector3 = Vector3(current.x, candidate.y, candidate.z)
	if _frontier_position_ready(peer_id, along_x):
		return along_x
	if _frontier_position_ready(peer_id, along_z):
		return along_z
	return Vector3(current.x, candidate.y, current.z)


func _present_frontier_sector(peer_id: int, sector_id: String, blueprint: Dictionary, ingress: Vector3, parent_trace: Dictionary) -> void:
	if not _player_states.has(peer_id) or not _frontier_bindings.has(peer_id):
		return
	if String(blueprint.get("sector_id", "")) != sector_id:
		return
	_remember_frontier_preparation(peer_id, sector_id)
	var effective: Dictionary = blueprint
	var revision: int = 0
	if _canon_mutation_repository != null:
		var listed: Dictionary = _canon_mutation_repository.list_mutations(sector_id)
		if listed.get("outcome") != "ok":
			# Revoke stale authority, but preserve the failed-attempt cooldown.
			_invalidate_frontier_sector(sector_id, false)
			return
		var mutations: Array = listed.get("mutations", [])
		effective = CanonSectorResolverScript.resolve_effective_blueprint(blueprint, mutations)
		if not mutations.is_empty():
			revision = int(mutations.back()["applied_revision"])
	_frontier_versions[sector_id] = "%d:%s" % [revision, JSON.stringify(effective).sha256_text()]
	var binding: Dictionary = _frontier_binding(peer_id, sector_id)
	if binding.is_empty():
		return
	var parent: Dictionary = parent_trace if not parent_trace.is_empty() else JitTraceContextScript.root(peer_id, sector_id)
	# Preserve the pending token on retry so slow/reordered ACKs remain valid.
	# A changed presentation/connection binding still requires a fresh token.
	var trace: Dictionary = _jit_presentation_ack_tracker.pending_trace(peer_id, sector_id, binding)
	if trace.is_empty():
		trace = _jit_presentation_ack_tracker.issue(peer_id, parent, binding)
	if _sector_boundary_detector != null:
		_sector_boundary_detector.remember_canon_trace(sector_id, trace)
	_send_sector_blueprint(peer_id, effective, ingress, trace)


func _send_sector_blueprint(peer_id: int, blueprint: Dictionary, ingress: Vector3, trace: Dictionary) -> void:
	var network_client: Node = root.get_node_or_null("NetworkClient")
	if network_client != null:
		network_client.rpc_id(peer_id, "receive_sector_blueprint", blueprint, ingress, trace)


## Slice 098 (P-013): replay the sector's durable mutation log onto its blueprint
## so peers render the effective (post-mutation) world. Falls back to the
## unchanged blueprint when the mutation store is unavailable or empty.
func _effective_blueprint_for(sector_id: String, blueprint: Dictionary) -> Dictionary:
	if _canon_mutation_repository == null or sector_id.is_empty():
		return blueprint
	var listed: Dictionary = _canon_mutation_repository.list_mutations(sector_id)
	if listed["outcome"] != CanonMutationRepositoryScript.OUTCOME_OK:
		return blueprint
	return CanonSectorResolverScript.resolve_effective_blueprint(blueprint, listed["mutations"])


## Slice 097 (P-013): resolve a client's Canon mutation intent authoritatively
## and return the resolution to that peer only. The actor is the peer's
## server-bound Character id; an unbound (unauthenticated) peer is rejected by
## the service. Never broadcast.
func _on_canon_mutation_intent(sender_peer_id: int, intent: Dictionary) -> void:
	if _canon_mutation_service == null:
		return
	var player_state: Node = _player_states.get(sender_peer_id)
	if player_state == null:
		return
	var resolution: Dictionary = _canon_mutation_service.resolve_intent(player_state.character_id, intent)
	if resolution.get("status") == CanonMutationServiceScript.STATUS_ACCEPTED and resolution.get("reason") == CanonMutationRepositoryScript.OUTCOME_OK:
		_invalidate_frontier_sector(String(intent.get("sector_id", "")))
	var network_client: Node = root.get_node_or_null("NetworkClient")
	if network_client == null:
		return
	network_client.rpc_id(sender_peer_id, "receive_canon_mutation_resolution", resolution)


## Server-owned monotonic tick used as the mutation event clock (Slice 097).
func _current_server_tick() -> int:
	return _monster_tick


## Slice 163 (telemetry map #282, decisions #285/#286): direct server-
## authored emission for events the server itself observes (connection
## lifecycle, combat outcomes), as opposed to TelemetryIngestService's
## untrusted-client-batch path. No rate limiting applies here — the server
## controls its own emission volume deterministically, once per real event.
## A telemetry-unavailable server (see boot wiring) makes this a silent
## no-op, never a crash or a blocked game loop.
func _emit_server_telemetry(event_type: String, peer_id: int, payload: Dictionary) -> void:
	if _telemetry_sink == null:
		return
	var character_id: String = ""
	var player_state: Node = _player_states.get(peer_id)
	if player_state != null:
		character_id = player_state.character_id
	var envelope: Dictionary = TelemetryEventScript.build(
		event_type, 1, int(Time.get_unix_time_from_system()), _current_server_tick(), peer_id, payload, "", character_id, ""
	)
	_telemetry_sink.emit(envelope)


func _emit_jit_trace(trace: Dictionary, peer_id: int) -> void:
	if trace.is_empty():
		return
	_emit_server_telemetry(String(trace.get("event_type", "")), peer_id, {
		"trace_id": String(trace.get("trace_id", "")),
		"span_id": String(trace.get("span_id", "")),
		"parent_span_id": trace.get("parent_span_id"),
		"sector_id": String(trace.get("sector_id", "")),
		"spatial_guid": String(trace.get("spatial_guid", "")),
		"timestamp_ms": int(trace.get("timestamp_ms", 0)),
		"duration_ms": float(trace.get("duration_ms", 0.0)),
		"status": String(trace.get("status", "")),
	})


## Slice 162 (telemetry map #282): the sole entry point for client-originated
## telemetry. Resolves this peer's server-known `character_id` (never trusted
## from the client) and the current wall-clock/tick, then forwards to
## TelemetryIngestService, which owns rate limiting, envelope construction,
## and the actual write. A telemetry-unavailable server (see boot wiring
## above) makes this a no-op — telemetry never blocks or disconnects a peer.
func _on_client_telemetry_batch_received(peer_id: int, events: Array, _client_sequence: int) -> void:
	if not _player_states.has(peer_id) or events.is_empty() or events.size() > int(TelemetryRateLimiterScript.CAPACITY):
		return
	if not _frontier_ack_limiter.try_consume(peer_id, events.size(), Time.get_ticks_msec() / 1000.0):
		return
	var character_id: String = ""
	var player_state: Node = _player_states.get(peer_id)
	if player_state != null:
		character_id = player_state.character_id
	var verified_events: Array[Dictionary] = _jit_presentation_ack_tracker.verified_events(peer_id, events)
	for event: Dictionary in verified_events:
		if event.get("event_type") != "client_presentation_ack":
			continue
		var sector_id: String = String(event["payload"].get("sector_id", ""))
		var presentation_trace: Dictionary = _jit_presentation_ack_tracker.confirm_ready(peer_id, event, _frontier_binding(peer_id, sector_id))
		if not presentation_trace.is_empty() and _sector_boundary_detector != null:
			_sector_boundary_detector.remember_canon_trace(
				sector_id,
				presentation_trace,
			)
	if _telemetry_ingest != null:
		_telemetry_ingest.ingest_batch(peer_id, verified_events, character_id, int(Time.get_unix_time_from_system()), _current_server_tick())
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
	if _journey_registry != null:
		_journey_registry.cleanup(int(Time.get_unix_time_from_system()))
	var now_msec: int = Time.get_ticks_msec()
	for peer_id: int in _player_states.keys():
		var player_state: Node = _player_states[peer_id]
		if String(player_state.character_id).is_empty():
			continue
		var last_checkpoint_msec: int = int(_last_journey_checkpoint_msec_by_peer.get(peer_id, 0))
		if last_checkpoint_msec == 0 or now_msec - last_checkpoint_msec >= JOURNEY_CHECKPOINT_INTERVAL_MSEC:
			_checkpoint_journey(peer_id, player_state.position)
	# Slice 067: refresh the runtime health file on a sub-second stride so a
	# frozen tick loop turns the container unhealthy even while the socket stays
	# bound. Runs regardless of monster state (health is independent of monsters).
	if _health_status == ServerHealthScript.STATUS_HEALTHY and Engine.get_physics_frames() % HEALTH_REFRESH_FRAMES == 0:
		_write_health(ServerHealthScript.STATUS_HEALTHY)
	if _monster_manager == null:
		return
	var player_positions: Array[Vector3] = []
	var player_peer_ids: Array[int] = []
	for peer_id: int in _player_states.keys():
		player_positions.append(_player_states[peer_id].position)
		player_peer_ids.append(peer_id)
	_monster_manager.advance_all(player_positions, _monster_tick_delta, _monster_tick, player_peer_ids)
	_monster_tick += 1
	_broadcast_monster_positions()
	if _town_npc_manager != null:
		_town_npc_manager.advance(player_positions, 1, _town_npc_tick)
		_town_npc_tick += 1
		_broadcast_town_npc_positions()


func _checkpoint_journey(peer_id: int, authoritative_position: Vector3) -> void:
	if _journey_registry == null or not _player_states.has(peer_id):
		return
	var player_state: Node = _player_states[peer_id]
	var character_id: String = String(player_state.character_id)
	if character_id.is_empty():
		return
	var sector_id: String = SectorBoundaryDetectorScript.sector_id_for_position(authoritative_position)
	var sector_revision: int = 0
	var sector_geometry_hash: String = ""
	if _canon_repository != null:
		var canon_result: Dictionary = _canon_repository.get_canonical_sector(sector_id)
		if canon_result.get("outcome", "") == "ok":
			var sector: Dictionary = canon_result.get("sector", {})
			sector_revision = int(sector.get("schema_version", 0))
			sector_geometry_hash = JSON.stringify(sector.get("blueprint", {})).md5_text()
	_journey_registry.checkpoint(
		character_id,
		authoritative_position,
		int(Time.get_unix_time_from_system()),
		sector_id,
		sector_revision,
		sector_geometry_hash
	)
	_last_journey_checkpoint_msec_by_peer[peer_id] = Time.get_ticks_msec()
	_last_journey_checkpoint_position_by_peer[peer_id] = authoritative_position


func _on_journey_evidence(kind: String, payload: Dictionary) -> void:
	var peer_id: int = int(payload.get("peer_id", 0))
	_emit_server_telemetry("journey.%s" % kind, peer_id, payload)


## Slice 067: builds an authoritative ServerHealth snapshot from current runtime
## state and writes it to the health file. Best-effort: an invalid snapshot or a
## write failure logs a warning and is dropped — it never blocks or crashes the
## tick loop. `status` drives the transition reported to the orchestrator.
func _write_health(status: String) -> void:
	if _health_file_path.is_empty():
		return
	_health_status = status
	var uptime_seconds: float = float(maxi(0, Time.get_ticks_msec() - _boot_ticks_ms)) / 1000.0
	var health_inputs: Dictionary = {
		"status": status,
		"tick_rate": _health_tick_rate,
		"uptime_seconds": uptime_seconds,
		"server_tick": int(Engine.get_physics_frames()),
		"connected_peers": _player_states.size(),
		"max_peers": MAX_REPLICATED_PEERS,
		"app_schema_version": APP_SCHEMA_VERSION,
		"timestamp": int(Time.get_unix_time_from_system()),
	}
	var built: Dictionary = ServerHealthScript.build_snapshot(health_inputs)
	if built["outcome"] != ServerHealthScript.OUTCOME_OK:
		push_warning("Health snapshot rejected: %s" % built.get("detail", ""))
		return
	var written: Dictionary = HealthReporterScript.write_snapshot(_health_file_path, built["snapshot"])
	if written["outcome"] != HealthReporterScript.OUTCOME_OK:
		push_warning("Health file write failed: %s" % written.get("detail", ""))
	_write_ops_snapshot(health_inputs)


func _write_ops_snapshot(health_inputs: Dictionary) -> void:
	if _ops_snapshot_file_path.is_empty():
		return
	var snapshot_inputs: Dictionary = health_inputs.duplicate()
	snapshot_inputs["server_id"] = OS.get_environment("PROJECT0_SERVER_ID").strip_edges()
	if String(snapshot_inputs["server_id"]).is_empty():
		snapshot_inputs["server_id"] = "project0-game"
	snapshot_inputs["server_type"] = OpsSnapshotScript.SERVER_TYPE_WORLD
	snapshot_inputs["server_version"] = _server_version
	snapshot_inputs["degraded_reason"] = _operator_control_service.degraded_reason() if _operator_control_service != null and _operator_control_service.is_degraded() else ""
	snapshot_inputs["extension"] = {
		"draining": _operator_control_service != null and _operator_control_service.is_draining(),
	}
	var built: Dictionary = OpsSnapshotScript.build(snapshot_inputs)
	if built["outcome"] != OpsSnapshotScript.OUTCOME_OK:
		push_warning("Ops snapshot rejected: %s" % built.get("detail", ""))
		return
	var written: Dictionary = HealthReporterScript.write_ops_snapshot(_ops_snapshot_file_path, built["snapshot"])
	if written["outcome"] != HealthReporterScript.OUTCOME_OK:
		push_warning("Ops snapshot write failed: %s" % written.get("detail", ""))


## Slice 067: on engine shutdown (e.g. SIGTERM -> graceful stop) publish a final
## `stopping` snapshot best-effort, so a container caught mid-drain reads
## `stopping` rather than a stale `healthy`.
func _finalize() -> void:
	_write_health(ServerHealthScript.STATUS_STOPPING)


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


## Slice 131: a first-cut fixed set of in-town anchors for the live town NPCs.
## Positions are inside the town center (players spawn near origin, monsters are
## excluded outside the walls). A later slice can derive anchors from the town
## blueprint's structures. Each NPC strolls a short daily route between stations.
func _default_town_anchor_defs() -> Array:
	return [
		{
			"anchor_id": "town_forge", "role": "smith", "home_position": Vector3(6, 1, 4),
			"desired_capacity": 1, "replacement_delay_ticks": 600,
			"routine_steps": [
				{"activity_id": "forge", "duration_ticks": 300},
				{"activity_id": "market", "duration_ticks": 300},
			],
			"activity_locations": {"forge": Vector3(6, 1, 4), "market": Vector3(-4, 1, 6)},
		},
		{
			"anchor_id": "town_market", "role": "vendor", "home_position": Vector3(-4, 1, 6),
			"desired_capacity": 1, "replacement_delay_ticks": 600,
			"routine_steps": [
				{"activity_id": "market", "duration_ticks": 240},
				{"activity_id": "tavern", "duration_ticks": 360},
			],
			"activity_locations": {"market": Vector3(-4, 1, 6), "tavern": Vector3(2, 1, -6)},
		},
	]


## Slice 131: broadcasts every live town NPC's authoritative route position to
## every connected peer each tick, mirroring _broadcast_monster_positions.
func _broadcast_town_npc_positions() -> void:
	var network_client: Node = root.get_node_or_null("NetworkClient")
	if network_client == null:
		return
	for npc: Variant in _town_npc_manager.all_npcs():
		var position: Vector3 = (npc as Object).position_at(_town_npc_tick)
		for receiving_peer_id: int in _player_states.keys():
			network_client.rpc_id(receiving_peer_id, "receive_town_npc_position", (npc as Object).npc_id, position)


## Slice 131: replicates a newly-staffed town NPC (initial fill is silent; this
## fires on a delayed replacement/promotion) to every connected peer.
func _on_town_npc_spawned(npc_id: String, _anchor_id: String, _source: String, _server_tick: int) -> void:
	var network_client: Node = root.get_node_or_null("NetworkClient")
	if network_client == null or _town_npc_manager == null:
		return
	var npc: Object = _town_npc_manager.find_npc(npc_id)
	if npc == null:
		return
	for receiving_peer_id: int in _player_states.keys():
		network_client.rpc_id(receiving_peer_id, "receive_town_npc_spawn", npc_id, npc.position_at(_town_npc_tick))


## Slice 131: tells every connected peer to despawn a town NPC that left the world.
func _on_town_npc_removed(npc_id: String, _anchor_id: String, _server_tick: int) -> void:
	var network_client: Node = root.get_node_or_null("NetworkClient")
	if network_client == null:
		return
	for receiving_peer_id: int in _player_states.keys():
		network_client.rpc_id(receiving_peer_id, "receive_town_npc_despawn", npc_id)


func _on_monster_died(_spawn_id: String, _server_tick: int) -> void:
	# Slice 164: no telemetry emit here — this signal is a direct consequence
	# of _on_player_state_combat_event_emitted's own receive_player_hit()
	# call below, which already emits combat.monster_defeated with the
	# attacker's peer_id. Emitting here too would double-write the same
	# death as two rows, one lacking attacker context.
	pass


## Slice 094: routes a monster's landed, telegraph-fair attack (surfaced by
## ServerMonsterManager.player_hit against the nearest player it was resolving
## against) to that peer's authoritative ServerPlayerState. The monster never
## touches player state directly — this is the single owner of that routing,
## mirroring how _on_player_state_combat_event_emitted is the sole route for a
## player hit reaching a monster. A no-op if the victim has since disconnected.
func _on_monster_player_hit(victim_peer_id: int, spawn_id: String, server_tick: int) -> void:
	var player_state: Node = _player_states.get(victim_peer_id)
	if player_state == null:
		return
	player_state.receive_monster_damage(MonsterContractsScript.DAMAGE_TO_PLAYER, server_tick)
	_emit_server_telemetry("combat.monster_hit_player", victim_peer_id, {"spawn_id": spawn_id, "damage": MonsterContractsScript.DAMAGE_TO_PLAYER})


## Slice 033: in addition to existing telemetry, tells every connected peer to
## (re)spawn a cosmetic representation for the respawned monster at its new
## position — mirrors the peer-connect replication above but triggered by the
## respawn event rather than a new connection. The death/despawn side of this
## lifecycle is already covered by the existing COMBAT_EVENT_DEATH broadcast
## (_on_player_state_combat_event_emitted), which client/monster.gd reacts to
## directly, so no separate "monster removed" RPC is added here.
func _on_monster_respawned(spawn_id: String, position: Vector3, server_tick: int) -> void:
	_emit_server_telemetry("combat.monster_respawned", -1, {"spawn_id": spawn_id, "position_x": position.x, "position_y": position.y, "position_z": position.z})
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


## Slice 094: replicates a Player's authoritative HP change to the owning
## client only (peer-scoped like receive_action_resolution) so its HUD can show
## current HP. Other peers do not need another peer's HP in this slice.
func _on_player_state_health_changed(peer_id: int, current_hp: int, max_hp: int, _server_tick: int) -> void:
	var network_client: Node = root.get_node_or_null("NetworkClient")
	if network_client == null:
		return
	network_client.rpc_id(peer_id, "receive_health_update", current_hp, max_hp)


## Slice 127: replicates a Player's presentation-safe Character snapshot to the
## owning client only (peer-scoped like the HP channel above) at world entry, so
## its HUD can show the vessel readout. Derived graph state only — never the raw
## stat numbers, which stay server-side.
func _on_player_state_character_snapshot_ready(peer_id: int, snapshot: Dictionary) -> void:
	var network_client: Node = root.get_node_or_null("NetworkClient")
	if network_client == null:
		return
	network_client.rpc_id(peer_id, "receive_character_snapshot", snapshot)


## Slice 142 (Phase 15 follow-on): replicates a Player's presentation-safe
## EffectiveMechanicsSnapshot to the owning client only (peer-scoped, exactly like
## the Character snapshot channel above) at world entry, so its HUD can show the
## mechanics readout. Derived graph + subsystem-safe summaries only — the raw
## effective numbers and tuning tables stay server-side.
func _on_player_state_effective_mechanics_ready(peer_id: int, snapshot: Dictionary) -> void:
	var network_client: Node = root.get_node_or_null("NetworkClient")
	if network_client == null:
		return
	network_client.rpc_id(peer_id, "receive_effective_mechanics", snapshot)


## Slice 094: tells the owning client its Player was defeated (then provisionally
## respawned at full HP; the reposition itself replicates through the normal
## authoritative-position channel) so its HUD can flash a brief cue.
func _on_player_state_player_defeated(peer_id: int, _server_tick: int) -> void:
	var network_client: Node = root.get_node_or_null("NetworkClient")
	if network_client == null:
		return
	_emit_server_telemetry("combat.player_defeated", peer_id, {})
	network_client.rpc_id(peer_id, "receive_player_defeated")


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
	_emit_server_telemetry("combat.hit", combat_event.attacker_peer_id, {"target_id": combat_event.target_id})

	var died: bool = _monster_manager.receive_player_hit(combat_event.target_id, combat_event.attacker_peer_id, combat_event.server_tick)
	if died:
		var death_event: Object = CombatContractsScript.CombatEvent.new(
			CombatContractsScript.COMBAT_EVENT_DEATH,
			combat_event.attacker_peer_id,
			combat_event.target_id,
			combat_event.impact_position,
			combat_event.server_tick
		)
		_emit_server_telemetry("combat.monster_defeated", combat_event.attacker_peer_id, {"target_id": combat_event.target_id})
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
	_emit_server_telemetry("combat.melee_swing_started", peer_id, {"windup_ticks": windup_ticks, "active_ticks": active_ticks})
	var network_client: Node = root.get_node_or_null("NetworkClient")
	if network_client == null:
		return
	for receiving_peer_id: int in _player_states.keys():
		network_client.rpc_id(receiving_peer_id, "receive_melee_swing_started", peer_id, windup_ticks, active_ticks, facing)
