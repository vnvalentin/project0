extends SceneTree
## Slice 181: headless two-process proof for the live Nakama gameplay bridge.

const NakamaHttpClientScript: Script = preload("res://client/nakama_http_client.gd")
const NetworkConfigScript: Script = preload("res://shared/network_config.gd")
const TIMEOUT_SECONDS: float = 30.0

var _role: String = ""
var _state_file: String = ""
var _token: String = ""
var _connection_status: String = "disconnected"
var _nakama_outcome: String = ""
var _character_operation: String = ""
var _character_outcome: String = ""
var _characters: Array = []
var _world_outcome: String = ""
var _world_character: Dictionary = {}
var _version_rejection: String = ""
var _state_count: int = 0
var _last_sequence: int = 0
var _match_id_present: bool = false
var _error_outcome: String = ""
var _outcomes: Array[String] = []
var _stage: String = "starting"
var _network_client: Node
var _player_identity: Node


func _initialize() -> void:
	_network_client = get_root().get_node("NetworkClient")
	_player_identity = get_root().get_node("PlayerIdentity")
	_network_client.connection_status_changed.connect(_on_connection_status)
	_network_client.nakama_session_established_received.connect(_on_nakama_session)
	_network_client.character_result_received.connect(_on_character_result)
	_network_client.world_entry_received.connect(_on_world_entry)
	_network_client.version_handshake_rejected.connect(_on_version_rejected)
	_network_client.authoritative_position_received.connect(_on_authoritative_position)
	call_deferred("_run_proof")


func _run_proof() -> void:
	var setup_error: String = _read_configuration()
	if not setup_error.is_empty():
		_fail(setup_error)
		_finish(1)
		return
	_set_stage("configuration_ready")

	_player_identity.nakama_auth_token = _token
	_player_identity.nakama_user_id = String(NakamaHttpClientScript.parse_jwt_payload(_token).get("uid", ""))
	if _player_identity.nakama_user_id.is_empty():
		_fail("token_missing_uid")
		_finish(1)
		return

	_network_client.connect_to_server(_game_host(), _game_port())
	_set_stage("connecting_to_game")
	if not await _wait_until(func() -> bool: return _connection_status == "connected" or not _version_rejection.is_empty()):
		_fail("connect_timeout")
		_finish(1)
		return
	if not _version_rejection.is_empty():
		_fail(_version_rejection)
		_finish(1)
		return
	_outcomes.append("connected_and_version_handshake_sent")
	_set_stage("version_accepted")

	_network_client.submit_nakama_session(_token)
	_set_stage("validating_nakama_session")
	if not await _wait_until(func() -> bool: return not _nakama_outcome.is_empty() or not _version_rejection.is_empty()):
		_fail("nakama_session_timeout")
		_finish(1)
		return
	if _nakama_outcome != "ok":
		_fail("nakama_session_%s" % _nakama_outcome)
		_finish(1)
		return
	_outcomes.append("nakama_session_established")
	_set_stage("nakama_session_established")

	_network_client.submit_list_characters()
	_set_stage("listing_characters")
	if not await _wait_until(func() -> bool: return _character_operation == "list"):
		_fail("character_list_timeout")
		_finish(1)
		return
	if _character_outcome != "ok":
		_fail("character_list_%s" % _character_outcome)
		_finish(1)
		return

	if _characters.is_empty():
		_network_client.submit_create_character(_proof_character_name(), {})
		_set_stage("creating_character")
		if not await _wait_until(func() -> bool: return _character_operation == "create"):
			_fail("character_create_timeout")
			_finish(1)
			return
		if _character_outcome != "ok" or _characters.is_empty():
			_fail("character_create_%s" % _character_outcome)
			_finish(1)
			return
		_outcomes.append("character_created")

	var character_id: String = String(_characters[0].get("character_id", ""))
	if character_id.is_empty():
		_fail("character_missing_id")
		_finish(1)
		return
	_player_identity.selected_character_id = character_id
	_network_client.submit_select_character(character_id)
	_set_stage("selecting_character")
	if not await _wait_until(func() -> bool: return _character_operation == "select"):
		_fail("character_select_timeout")
		_finish(1)
		return
	if _character_outcome != "ok":
		_fail("character_select_%s" % _character_outcome)
		_finish(1)
		return

	_network_client.submit_enter_world()
	_set_stage("entering_world")
	if not await _wait_until(func() -> bool: return not _world_outcome.is_empty()):
		_fail("world_entry_timeout")
		_finish(1)
		return
	if _world_outcome != "ok":
		_fail("world_entry_%s" % _world_outcome)
		_finish(1)
		return
	_match_id_present = not String(_world_character.get("nakama_match_id", "")).is_empty()
	if not _match_id_present:
		_fail("match_id_missing")
		_finish(1)
		return
	_outcomes.append("world_entry_submitted")
	_set_stage("world_entry_complete")

	# World entry starts the bridge asynchronously; this input is the first
	# bridge state request and the response is the authoritative proof signal.
	await process_frame
	var sequence: int = 1
	_network_client.submit_input_intent(Vector2(1.0, 0.0), sequence)
	_set_stage("waiting_for_authoritative_state")
	if not await _wait_until(func() -> bool: return _state_count > 0):
		_fail("authoritative_state_timeout")
		_finish(1)
		return
	if not _match_id_present or _state_count <= 0:
		_fail("authoritative_state_missing_binding")
		_finish(1)
		return
	_outcomes.append("authoritative_nakama_state_received")
	_set_stage("authoritative_state_received")
	_finish(0)


func _read_configuration() -> String:
	_role = _argument_value("--role=")
	if _role.is_empty():
		_role = OS.get_environment("PROJECT0_NAKAMA_PROOF_ROLE").strip_edges()
	_state_file = _argument_value("--state-file=")
	if _state_file.is_empty() and not _role.is_empty():
		_state_file = OS.get_environment("PROJECT0_NAKAMA_PROOF_STATE_FILE").strip_edges()
	if _state_file.is_empty() and (_role == "a" or _role == "b"):
		_state_file = "/data/nakama-proof-%s.json" % _role
	if _role != "a" and _role != "b":
		return "invalid_role"
	if _state_file.is_empty():
		return "missing_state_file"
	_token = OS.get_environment("PROJECT0_NAKAMA_AUTH_TOKEN_%s" % _role.to_upper()).strip_edges()
	if _token.is_empty():
		return "missing_nakama_auth_token"
	if OS.get_environment("PROJECT0_NAKAMA_SERVER_KEY").strip_edges().is_empty():
		return "missing_nakama_server_key"
	if OS.get_environment("PROJECT0_NAKAMA_URL").strip_edges().is_empty():
		return "missing_nakama_url"
	if OS.get_environment("PROJECT0_CLIENT_NAKAMA_GAMEPLAY").strip_edges() != "1":
		return "nakama_gameplay_disabled"
	if OS.get_environment("PROJECT0_CLIENT_NAKAMA_LOGIN").strip_edges() != "1":
		return "nakama_login_disabled"
	if OS.get_environment("PROJECT0_GAME_HOST").strip_edges().is_empty():
		return "missing_game_host"
	if OS.get_environment("PROJECT0_GAME_PORT").strip_edges().is_empty() or _game_port() <= 0 or _game_port() > 65535:
		return "missing_game_endpoint"
	return ""


func _game_host() -> String:
	var host: String = OS.get_environment("PROJECT0_GAME_HOST").strip_edges()
	return host if not host.is_empty() else NetworkConfigScript.resolve_client_target_host()


func _game_port() -> int:
	var value: String = OS.get_environment("PROJECT0_GAME_PORT").strip_edges()
	if value.is_empty():
		return NetworkConfigScript.resolve_server_port()
	return value.to_int() if value.is_valid_int() else 0


func _proof_character_name() -> String:
	var suffix: String = _player_identity.nakama_user_id.replace("-", "").substr(0, 8)
	var run_suffix: String = str(Time.get_ticks_usec()).substr(-8)
	return "L%s%s%s" % [_role, suffix, run_suffix]


func _argument_value(prefix: String) -> String:
	var arguments: PackedStringArray = OS.get_cmdline_args()
	arguments.append_array(OS.get_cmdline_user_args())
	for argument: String in arguments:
		if argument.begins_with(prefix):
			return argument.substr(prefix.length()).strip_edges()
	return ""


func _wait_until(condition: Callable) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(TIMEOUT_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await process_frame
	return false


func _on_connection_status(status: String) -> void:
	_connection_status = status


func _on_version_rejected(rejection: Dictionary) -> void:
	_version_rejection = String(rejection.get("outcome", "version_rejected"))


func _on_nakama_session(outcome: String) -> void:
	_nakama_outcome = outcome


func _on_character_result(operation: String, outcome: String, characters: Array) -> void:
	_character_operation = operation
	_character_outcome = outcome
	_characters = characters


func _on_world_entry(outcome: String, character: Dictionary) -> void:
	_world_outcome = outcome
	_world_character = character


func _on_authoritative_position(_position: Vector3, sequence: int) -> void:
	_state_count += 1
	_last_sequence = sequence


func _fail(outcome: String) -> void:
	_error_outcome = outcome
	_outcomes.append("failed")
	_write_state()


func _set_stage(stage: String) -> void:
	_stage = stage
	_write_state()


func _write_state() -> void:
	if _state_file.is_empty():
		return
	var file: FileAccess = FileAccess.open(_state_file, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"stage": _stage,
		"outcomes": _outcomes,
		"connection_status": _connection_status,
		"match_id_present": _match_id_present,
		"state_received": _state_count > 0,
		"last_sequence": _last_sequence,
		"error_outcome": _error_outcome,
	}))
	file.close()


func _finish(exit_code: int) -> void:
	if _network_client.status != "disconnected":
		_network_client.disconnect_from_server()
	_connection_status = _network_client.status
	var state: Dictionary = {
		"stage": _stage,
		"outcomes": _outcomes,
		"connection_status": _connection_status,
		"match_id_present": _match_id_present,
		"state_received": _state_count > 0,
		"last_sequence": _last_sequence,
		"error_outcome": _error_outcome,
	}
	var file: FileAccess = FileAccess.open(_state_file, FileAccess.WRITE)
	if file == null:
		push_error("could not write proof state file")
		quit(1)
		return
	file.store_string(JSON.stringify(state))
	file.close()
	quit(exit_code)