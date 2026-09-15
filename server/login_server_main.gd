extends SceneTree
## Slice 068: standalone login-server process — the first out-of-process step of
## the container-platform login-boundary decision
## (.scratch/container-platform/issues/02-account-login-service-boundary.md). It
## boots ONLY the login authority (AuthService + CharacterService + LoginGateway
## + the Slice 059/060 assertion seams, via the shared LoginRuntime) against its
## own accounts database, and hosts the existing register/login/Character RPC
## surface on a dedicated login port — no town, monsters, Canon, or gameplay.
##
## Run with:
##   godot --headless --path . -s server/login_server_main.gd
## Optional environment:
##   PROJECT0_LOGIN_ACCOUNTS_DB_PATH (default login_accounts.db, under user://)
##   PROJECT0_LOGIN_PORT (default 9998; distinct from the game server's 9999)
##   PROJECT0_SERVER_BIND_ADDRESS (default 127.0.0.1)
##   PROJECT0_ASSERTION_SECRET (hex; ephemeral per-boot key when unset)
##   PROJECT0_HEALTH_FILE (default user://login_health.json)
##
## The register/login/Character RPC receivers live on the NetworkClient autoload
## (client/network_client.gd), which is present server-side exactly as in
## server/server_main.gd; they resolve /root/LoginGateway, which this process
## provides. Client cutover and dropping the game server's in-process login are
## later sub-slices — this process runs beside the unchanged game server.

const NetworkConfigScript: Script = preload("res://shared/network_config.gd")
const SqliteStoreScript: Script = preload("res://server/sqlite_store.gd")
const AccountCharacterRepositoryScript: Script = preload("res://server/account_character_repository.gd")
const LoginRuntimeScript: Script = preload("res://server/login_runtime.gd")
const ServerHealthScript: Script = preload("res://server/server_health.gd")
const HealthReporterScript: Script = preload("res://server/health_reporter.gd")

const DEFAULT_LOGIN_ACCOUNTS_DB_PATH: String = "login_accounts.db"
const DEFAULT_LOGIN_HEALTH_FILE: String = "user://login_health.json"
const MAX_LOGIN_PEERS: int = 64
const APP_SCHEMA_VERSION: int = 1
const HEALTH_REFRESH_FRAMES: int = 30

var _store: SqliteStore = null
var _repository: Object = null
var _login_gateway: Object = null
var _peer: ENetMultiplayerPeer
var _connected_peers: Dictionary = {}

var _health_file_path: String = ""
var _health_tick_rate: int = ServerHealthScript.DEFAULT_TICK_RATE
var _health_status: String = ServerHealthScript.STATUS_STARTING
var _boot_ticks_ms: int = 0


func _initialize() -> void:
	call_deferred("_start_login_server")


func _start_login_server() -> void:
	_health_file_path = _resolve_health_file_path()
	_health_tick_rate = ServerHealthScript.resolve_tick_rate(OS.get_environment("PROJECT0_TICK_RATE"))
	_boot_ticks_ms = Time.get_ticks_msec()
	_write_health(ServerHealthScript.STATUS_STARTING)

	# Fail closed on a DB-open/schema failure, matching server_main.gd's boot: a
	# login authority that cannot open its accounts store must never run.
	var db_path: String = OS.get_environment("PROJECT0_LOGIN_ACCOUNTS_DB_PATH").strip_edges()
	if db_path.is_empty():
		db_path = DEFAULT_LOGIN_ACCOUNTS_DB_PATH
	_store = SqliteStoreScript.new()
	var open_result: Dictionary = _store.open(db_path)
	if open_result["outcome"] != SqliteStoreScript.OUTCOME_OK:
		push_error("Refusing to start login server: accounts database failed to open: %s — %s" % [open_result["outcome"], open_result["detail"]])
		quit(1)
		return
	_repository = AccountCharacterRepositoryScript.new(_store)
	var schema_result: Dictionary = _repository.ensure_schema()
	if schema_result["outcome"] != "ok":
		push_error("Refusing to start login server: accounts schema failed to initialize: %s — %s" % [schema_result["outcome"], schema_result["detail"]])
		quit(1)
		return

	var services: Dictionary = LoginRuntimeScript.build_services(_repository, root, LoginRuntimeScript.resolve_assertion_secret())
	_login_gateway = services["gateway"]
	print("Login accounts database ready at user://%s (schema ensured)." % db_path)

	var bind_address: String = NetworkConfigScript.resolve_server_bind_address()
	var login_port: int = NetworkConfigScript.resolve_login_port()
	_peer = ENetMultiplayerPeer.new()
	_peer.set_bind_ip(bind_address)
	var listen_error: Error = _peer.create_server(login_port, MAX_LOGIN_PEERS, 0, 0, 0)
	if listen_error != OK:
		push_error("Login server failed to listen on %s:%d: %s" % [bind_address, login_port, listen_error])
		quit(1)
		return
	root.multiplayer.multiplayer_peer = _peer
	root.multiplayer.peer_connected.connect(_on_peer_connected)
	root.multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	physics_frame.connect(_on_physics_frame)
	print("Login server listening on %s:%d" % [bind_address, login_port])
	_write_health(ServerHealthScript.STATUS_HEALTHY)
	if bind_address != NetworkConfigScript.SERVER_ADDRESS:
		print("WARNING: login server bound to a non-localhost address. It accepts unauthenticated connections from any host that can reach %s:%d. Only do this on a trusted local network." % [bind_address, login_port])


func _resolve_health_file_path() -> String:
	var raw: String = OS.get_environment("PROJECT0_HEALTH_FILE").strip_edges()
	if raw.is_empty():
		return DEFAULT_LOGIN_HEALTH_FILE
	return raw


func _on_peer_connected(peer_id: int) -> void:
	_connected_peers[peer_id] = true
	print("Login peer connected: %d" % peer_id)


## Clear the disconnecting peer's session so a reconnecting peer never inherits a
## prior authenticated session (mirrors the game server's disconnect cleanup).
func _on_peer_disconnected(peer_id: int) -> void:
	_connected_peers.erase(peer_id)
	if _login_gateway != null:
		_login_gateway.clear_session(peer_id)
	print("Login peer disconnected: %d" % peer_id)


func _on_physics_frame() -> void:
	if _health_status == ServerHealthScript.STATUS_HEALTHY and Engine.get_physics_frames() % HEALTH_REFRESH_FRAMES == 0:
		_write_health(ServerHealthScript.STATUS_HEALTHY)


## Best-effort runtime health file (reuses the Slice 067 ServerHealth contract),
## so the login process gets the same liveness signal as the game server.
func _write_health(status: String) -> void:
	if _health_file_path.is_empty():
		return
	_health_status = status
	var uptime_seconds: float = float(maxi(0, Time.get_ticks_msec() - _boot_ticks_ms)) / 1000.0
	var built: Dictionary = ServerHealthScript.build_snapshot({
		"status": status,
		"tick_rate": _health_tick_rate,
		"uptime_seconds": uptime_seconds,
		"server_tick": int(Engine.get_physics_frames()),
		"connected_peers": _connected_peers.size(),
		"max_peers": MAX_LOGIN_PEERS,
		"app_schema_version": APP_SCHEMA_VERSION,
		"timestamp": int(Time.get_unix_time_from_system()),
	})
	if built["outcome"] != ServerHealthScript.OUTCOME_OK:
		push_warning("Login health snapshot rejected: %s" % built.get("detail", ""))
		return
	var written: Dictionary = HealthReporterScript.write_snapshot(_health_file_path, built["snapshot"])
	if written["outcome"] != HealthReporterScript.OUTCOME_OK:
		push_warning("Login health file write failed: %s" % written.get("detail", ""))


func _finalize() -> void:
	_write_health(ServerHealthScript.STATUS_STOPPING)
