extends SceneTree
## Slice 073 headless e2e: proves the client login->game handoff over real ENet
## across TWO separate server processes. Spawns the unmodified production
## server/login_server_main.gd and server/server_main.gd (two OS processes that
## share one PROJECT0_ASSERTION_SECRET but SEPARATE accounts DBs) plus one
## scripts/login_handoff_client_harness.gd, then polls the harness's public-seam
## state file to assert the game server established the client's session purely
## from the login-minted assertion. This orchestrator makes no network
## connection; all pass/fail decisions come from the state file (the same public
## seam a real client exposes), matching scripts/test_multi_peer_replication.gd.
##
## Run with:
##   godot --headless --path . -s scripts/test_login_handoff_e2e.gd
## Exits 0 and prints "ALL PASS" only if every assertion below holds.

# High ephemeral ports so a running dev/native server (9999) never collides.
const LOGIN_PORT: int = 24998
const GAME_PORT: int = 24999
# Fixed shared HMAC secret both servers load, so the login issuer and the game
# validator agree. Test-only value; never a production secret.
const SHARED_SECRET: String = "0f1e2d3c4b5a69788796a5b4c3d2e1f00f1e2d3c4b5a69788796a5b4c3d2e1f0"
const LOGIN_DB: String = "test_handoff_login.db"
const GAME_DB: String = "test_handoff_game.db"
const READY_TIMEOUT_MS: int = 40000
const HANDOFF_TIMEOUT_MS: int = 40000

var _failures: int = 0
var _login_pid: int = -1
var _game_pid: int = -1
var _client_pid: int = -1
var _state_file: String = ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_login_game_handoff()
	_cleanup()
	if _failures == 0:
		print("ALL PASS")
		quit(0)
	else:
		push_error("%d assertion(s) failed" % _failures)
		quit(1)


func _assert(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
	else:
		_failures += 1
		push_error("FAIL: %s" % message)


func _test_login_game_handoff() -> void:
	var godot: String = OS.get_executable_path()
	var project_path: String = ProjectSettings.globalize_path("res://")
	_state_file = project_path.path_join(".test_login_handoff_state.json")

	# Clean stale artifacts so readiness/handoff checks never see a prior run.
	_remove_user_file("health.json")
	_remove_user_file("login_health.json")
	for path: String in [_state_file]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

	# Both servers inherit these; each reads only the vars it needs. The shared
	# secret makes the login issuer and game validator agree; the DB paths keep
	# their accounts stores separate (the point of the split).
	OS.set_environment("PROJECT0_ASSERTION_SECRET", SHARED_SECRET)
	OS.set_environment("PROJECT0_LOGIN_ACCOUNTS_DB_PATH", LOGIN_DB)
	OS.set_environment("PROJECT0_ACCOUNTS_DB_PATH", GAME_DB)

	_login_pid = OS.create_process(godot, [
		"--headless", "--path", project_path,
		"-s", "server/login_server_main.gd",
		"--", "--login-port=%d" % LOGIN_PORT, "--server-bind-address=127.0.0.1",
	])
	_assert(_login_pid != -1, "login server process starts")

	_game_pid = OS.create_process(godot, [
		"--headless", "--path", project_path,
		"-s", "server/server_main.gd",
		"--", "--server-bind-address=127.0.0.1", "--server-port=%d" % GAME_PORT,
	])
	_assert(_game_pid != -1, "game server process starts")

	var login_ready: bool = await _wait_for_health("login_health.json", READY_TIMEOUT_MS)
	var game_ready: bool = await _wait_for_health("health.json", READY_TIMEOUT_MS)
	_assert(login_ready, "login server reports healthy")
	_assert(game_ready, "game server reports healthy")
	if not (login_ready and game_ready):
		return

	_client_pid = OS.create_process(godot, [
		"--headless", "--path", project_path,
		"-s", "scripts/login_handoff_client_harness.gd",
		"--", "--state-file=%s" % _state_file,
		"--login-port=%d" % LOGIN_PORT, "--game-port=%d" % GAME_PORT,
	])
	_assert(_client_pid != -1, "client harness process starts")

	# Poll until the client finishes world entry (or fails).
	var state: Dictionary = await _wait_for_state(func(s: Dictionary) -> bool:
		return String(s.get("world_entry", "")) != "" or String(s.get("phase", "")) == "failed"
	, HANDOFF_TIMEOUT_MS)

	_assert(bool(state.get("login_connected", false)), "client connects to the login process")
	_assert(bool(state.get("registered", false)), "client registers on the login process")
	_assert(bool(state.get("character_selected", false)), "client creates and selects a Character on the login process")
	_assert(bool(state.get("assertion_received", false)), "client receives a signed assertion from the login process")
	_assert(bool(state.get("game_connected", false)), "client connects to the game process after the login handoff")
	_assert(String(state.get("session_established", "")) == "ok", "the game process establishes the session from the login assertion (no shared DB); outcome=%s error=%s" % [state.get("session_established", ""), state.get("error", "")])
	_assert(String(state.get("world_entry", "")) == "ok", "the client enters the world as its asserted Character (no shared DB); outcome=%s error=%s" % [state.get("world_entry", ""), state.get("error", "")])
	_assert(String(state.get("world_character_name", "")) == "Handoff Hero", "the bound Player is the Character named on the login process; got=%s" % [state.get("world_character_name", "")])


func _wait_for_health(user_file: String, timeout_ms: int) -> bool:
	var abs_path: String = ProjectSettings.globalize_path("user://%s" % user_file)
	var deadline: int = Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if FileAccess.file_exists(abs_path):
			var text: String = FileAccess.get_file_as_string(abs_path)
			var parsed: Variant = JSON.parse_string(text)
			if parsed is Dictionary and String((parsed as Dictionary).get("status", "")) == "healthy":
				return true
		await process_frame
	return false


func _wait_for_state(predicate: Callable, timeout_ms: int) -> Dictionary:
	var state: Dictionary = {}
	var deadline: int = Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		state = _read_state()
		if not state.is_empty() and predicate.call(state):
			return state
		await process_frame
	return state


func _read_state() -> Dictionary:
	if not FileAccess.file_exists(_state_file):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_state_file))
	return parsed if parsed is Dictionary else {}


func _remove_user_file(name: String) -> void:
	var abs_path: String = ProjectSettings.globalize_path("user://%s" % name)
	if FileAccess.file_exists(abs_path):
		DirAccess.remove_absolute(abs_path)


func _cleanup() -> void:
	for pid: int in [_client_pid, _login_pid, _game_pid]:
		if pid != -1 and OS.is_process_running(pid):
			OS.kill(pid)
	if not _state_file.is_empty() and FileAccess.file_exists(_state_file):
		DirAccess.remove_absolute(_state_file)
	for name: String in [LOGIN_DB, GAME_DB, LOGIN_DB + "-wal", LOGIN_DB + "-shm", GAME_DB + "-wal", GAME_DB + "-shm", "health.json", "login_health.json"]:
		_remove_user_file(name)
