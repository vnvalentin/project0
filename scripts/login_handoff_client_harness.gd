extends SceneTree
## Slice 073 test-only client harness: a real OS process that performs the full
## login->game handoff through the production seams and writes its observable
## public-seam state to a JSON file for scripts/test_login_handoff_e2e.gd (the
## orchestrator) to poll. It connects to the standalone login server, registers,
## creates and selects a Character, requests a signed assertion, disconnects,
## connects to the game server, and presents the assertion. It has no assertions
## of its own — all pass/fail decisions live in the orchestrator, which reads
## only this file (NetworkClient.status and the relay signals a real client
## exposes). Godot 4.3 allows only one MultiplayerAPI peer per SceneTree, so the
## handoff is sequential: disconnect from login before connecting to game.
##
## CLI args (after `--`):
##   --state-file=<path>   required; where to write JSON state.
##   --login-port=<n>      required; the login server's UDP port.
##   --game-port=<n>       required; the game server's UDP port.
##   --username=<s>        optional; account username (default handoff-user).
##   --password=<s>        optional; account password (default handoff-pass).

const NetworkConfigScript: Script = preload("res://shared/network_config.gd")

const HOST: String = "127.0.0.1"
const STEP_TIMEOUT_MS: int = 20000

var _state_file_path: String = ""
var _login_port: int = 0
var _game_port: int = 0
var _username: String = "handoff-user"
var _password: String = "handoff-pass"

var _network_client: Node = null
var _gameplay_instance: Node = null

# Captured public-seam outcomes (written to the state file).
var _state: Dictionary = {
	"phase": "starting",
	"login_connected": false,
	"registered": false,
	"character_selected": false,
	"assertion_received": false,
	"game_connected": false,
	"session_established": "",
	"world_entry": "",
	"world_character_name": "",
	"error": "",
}

# Per-step signal captures.
var _auth_outcome: String = ""
var _char_op: String = ""
var _char_outcome: String = ""
var _char_id: String = ""
var _assertion_outcome: String = ""
var _assertion_token: String = ""
var _session_outcome: String = ""
var _world_outcome: String = ""
var _world_character_name: String = ""
var _handoff_done: bool = false
var _handoff_outcome: String = ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_parse_args()
	if _state_file_path.is_empty() or _login_port == 0 or _game_port == 0:
		push_error("login_handoff_client_harness: --state-file=, --login-port=, --game-port= are required")
		quit(1)
		return

	_network_client = root.get_node("NetworkClient")
	_gameplay_instance = load("res://client/gameplay.tscn").instantiate()
	root.add_child(_gameplay_instance)
	current_scene = _gameplay_instance
	await process_frame

	_network_client.auth_result_received.connect(_on_auth_result)
	_network_client.character_result_received.connect(_on_character_result)
	_network_client.assertion_result_received.connect(_on_assertion_result)
	_network_client.session_established_received.connect(_on_session_established)
	_network_client.world_entry_received.connect(_on_world_entry)

	await _handoff()

	# Keep the process alive (still writing state) until the orchestrator reads
	# the terminal state and kills it, so the state file is never truncated mid-run.
	while true:
		await process_frame
		_write_state()


func _handoff() -> void:
	# --- Phase 1: the login process ---
	_set_phase("connect_login")
	_network_client.connect_to_server(HOST, _login_port)
	if not await _until(func() -> bool: return String(_network_client.status).begins_with("connected")):
		return _fail("login connect timeout")
	_state["login_connected"] = true

	_set_phase("register")
	_auth_outcome = ""
	_network_client.submit_register(_username, _password)
	if not await _until(func() -> bool: return _auth_outcome != ""):
		return _fail("register timeout")
	if _auth_outcome != "ok":
		return _fail("register rejected: %s" % _auth_outcome)
	_state["registered"] = true

	_set_phase("create_character")
	_char_op = ""
	_char_outcome = ""
	_network_client.submit_create_character("Handoff Hero", {})
	if not await _until(func() -> bool: return _char_op == "create" and _char_outcome != ""):
		return _fail("create character timeout")
	if _char_outcome != "ok" or _char_id.is_empty():
		return _fail("create character rejected: %s" % _char_outcome)

	_set_phase("select_character")
	_char_op = ""
	_char_outcome = ""
	_network_client.submit_select_character(_char_id)
	if not await _until(func() -> bool: return _char_op == "select" and _char_outcome != ""):
		return _fail("select character timeout")
	if _char_outcome != "ok":
		return _fail("select character rejected: %s" % _char_outcome)
	_state["character_selected"] = true

	# --- Phase 2: production login->game handoff seam ---
	_set_phase("handoff")
	_network_client.login_to_game_handoff_finished.connect(_on_handoff_finished)
	_network_client.perform_login_to_game_handoff(HOST, _game_port)
	if not await _until(func() -> bool: return _handoff_done):
		return _fail("handoff timeout")
	if _handoff_outcome != "ok":
		return _fail("handoff outcome: %s" % _handoff_outcome)
	_set_phase("done")
	_write_state()


## Polls `predicate` each process frame until it is true or STEP_TIMEOUT_MS
## (wall-clock) elapses. Writes state each poll so the orchestrator always sees
## fresh progress. Returns whether the predicate became true.
func _until(predicate: Callable) -> bool:
	var deadline: int = Time.get_ticks_msec() + STEP_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		_write_state()
		await process_frame
	return false


func _on_auth_result(outcome: String, _account_id: String, _username: String) -> void:
	_auth_outcome = outcome


func _on_character_result(operation: String, outcome: String, characters: Array) -> void:
	_char_op = operation
	_char_outcome = outcome
	if outcome == "ok" and characters.size() > 0 and characters[0] is Dictionary:
		_char_id = String((characters[0] as Dictionary).get("character_id", ""))


func _on_assertion_result(outcome: String, assertion: String) -> void:
	_assertion_outcome = outcome
	_assertion_token = assertion
	if outcome == "ok" and not assertion.is_empty():
		_state["assertion_received"] = true


func _on_session_established(outcome: String) -> void:
	_session_outcome = outcome
	# Reaching this means the game connection is up (present runs on it).
	_state["game_connected"] = true
	_state["session_established"] = outcome


func _on_world_entry(outcome: String, character: Dictionary) -> void:
	_world_outcome = outcome
	_world_character_name = String(character.get("display_name", ""))
	_state["world_entry"] = outcome
	_state["world_character_name"] = _world_character_name


func _on_handoff_finished(outcome: String, _character: Dictionary) -> void:
	_handoff_outcome = outcome
	_handoff_done = true


func _set_phase(phase: String) -> void:
	_state["phase"] = phase
	_write_state()


func _fail(reason: String) -> void:
	_state["error"] = reason
	_set_phase("failed")


func _write_state() -> void:
	_state["status"] = String(_network_client.status) if _network_client != null else ""
	var file: FileAccess = FileAccess.open(_state_file_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_state))
		file.close()


func _parse_args() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--state-file="):
			_state_file_path = argument.substr("--state-file=".length())
		elif argument.begins_with("--login-port="):
			_login_port = argument.substr("--login-port=".length()).to_int()
		elif argument.begins_with("--game-port="):
			_game_port = argument.substr("--game-port=".length()).to_int()
		elif argument.begins_with("--username="):
			_username = argument.substr("--username=".length())
		elif argument.begins_with("--password="):
			_password = argument.substr("--password=".length())
