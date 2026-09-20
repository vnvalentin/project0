## Slice 044: Account login/register screen controller.
## Manages username/password input, calls NetworkClient auth RPCs,
## listens to auth_result_received signal, and transitions to character_gate.tscn
## on successful authentication.
extends Control

const NetworkConfigScript: Script = preload("res://shared/network_config.gd")
## Slice 093: the client's HTTPS seam to the enrollment service, used for the
## WAN login flow (client_https_login_enabled). Null in the LAN ENet path.
const EnrollmentHttpClientScript: Script = preload("res://client/enrollment_http_client.gd")
const NakamaHttpClientScript: Script = preload("res://client/nakama_http_client.gd")
const REMOTE_SERVER_HOST: String = "192.69.180.236"
const LAN_SERVER_HOST: String = "192.168.1.254"

@onready var username_input = $VBoxContainer/UsernameInput
@onready var password_input = $VBoxContainer/PasswordInput
@onready var settings_panel = $VBoxContainer/SettingsPanel
@onready var remote_server_checkbox = $VBoxContainer/RemoteServerCheckBox
@onready var host_input = $VBoxContainer/SettingsPanel/SettingsBox/HostInput
@onready var game_port_input = $VBoxContainer/SettingsPanel/SettingsBox/GamePortInput
@onready var login_mode_option = $VBoxContainer/SettingsPanel/SettingsBox/LoginModeOption
@onready var settings_button = $VBoxContainer/SettingsButton
@onready var status_label = $VBoxContainer/StatusLabel
@onready var login_button = $VBoxContainer/ButtonContainer/LoginButton
@onready var register_button = $VBoxContainer/ButtonContainer/RegisterButton

## The queued auth request ("login"/"register") to send once the ENet
## connection is established; empty when no request is in flight. The cached
## password is dropped the moment the request is sent.
var _pending_action: String = ""
var _pending_username: String = ""
var _pending_password: String = ""

## Slice 093: the HTTPS enrollment client instance, created only in the WAN flow.
var _http_client: Object = null
var _nakama_client: Object = null
const SETTINGS_PATH: String = "user://project0-client-settings.cfg"

func _ready() -> void:
	# Connect to NetworkClient auth signals
	NetworkClient.auth_result_received.connect(_on_auth_result)
	NetworkClient.connection_status_changed.connect(_on_connection_status)
	
	# Login/Register stay enabled; a request disables them until it resolves.
	
	# Default host input to the resolved target (allows override)
	_load_settings()
	game_port_input.text = str(NetworkConfigScript.resolve_server_port())
	login_mode_option.select(0 if NetworkConfigScript.client_https_login_enabled() else 1)
	remote_server_checkbox.button_pressed = remote_server_checkbox.button_pressed
	_on_remote_server_toggled(remote_server_checkbox.button_pressed)
	settings_panel.visible = false
	settings_button.pressed.connect(_on_settings_pressed)
	remote_server_checkbox.toggled.connect(_on_remote_server_toggled)
	
	# Slice 093: in the WAN flow authentication happens over HTTPS; registration
	# is not exposed on the public enrollment surface yet (DT-010), so log into an
	# existing account only.
	if NetworkConfigScript.client_nakama_login_enabled():
		_nakama_client = NakamaHttpClientScript.new()
		add_child(_nakama_client)
		register_button.disabled = false
		register_button.tooltip_text = "Click to register a Nakama account."
	elif NetworkConfigScript.client_https_login_enabled():
		_http_client = EnrollmentHttpClientScript.new()
		add_child(_http_client)
		register_button.disabled = false
		register_button.tooltip_text = "Click to register an account."

func _on_login_pressed() -> void:
	if not _apply_settings():
		return
	var username = username_input.text.strip_edges()
	var password = password_input.text
	var host = host_input.text.strip_edges()
	
	if not _validate_input(username, password):
		return
	
	# Store target host in PlayerIdentity for gameplay to inherit
	PlayerIdentity.target_host = host if not host.is_empty() else NetworkConfigScript.resolve_client_target_host()
	
	if NetworkConfigScript.client_nakama_login_enabled():
		await _perform_nakama_auth(username, password, false)
		return

	# Slice 093: WAN flow authenticates over HTTPS, not the ENet login connection.
	if NetworkConfigScript.client_https_login_enabled():
		await _perform_https_login(username, password)
		return
	
	status_label.text = "Status: Connecting..."
	login_button.disabled = true
	register_button.disabled = true
	
	# The login screen owns opening the connection; queue the request so it
	# fires once connected (submit_login is a no-op until the handshake ends).
	_pending_action = "login"
	_pending_username = username
	_pending_password = password
	if NetworkClient.status.begins_with("connected"):
		_fire_pending_auth()
	else:
		_connect_for_auth()

## Slice 093: logs in over HTTPS via the enrollment service, stores the returned
## account assertion, and transitions to Character selection. Fail-closed: any
## bounded transport/HTTP failure re-enables login with a readable reason and
## mints nothing.
func _perform_https_login(username: String, password: String) -> void:
	status_label.text = "Status: Logging in..."
	login_button.disabled = true
	var base_url: String = EnrollmentHttpClientScript.resolve_base_url()
	var result: Dictionary = await _http_client.login(base_url, username, password)
	if result["outcome"] == EnrollmentHttpClientScript.OUTCOME_OK:
		PlayerIdentity.username = username
		PlayerIdentity.account_assertion = String(result["assertion"])
		status_label.text = "Status: Login successful! Loading characters..."
		await get_tree().create_timer(0.3).timeout
		get_tree().change_scene_to_file("res://client/character_gate.tscn")
	else:
		status_label.text = "Status: Login failed (%s)" % _https_failure_reason(result)
		login_button.disabled = false


func _perform_nakama_auth(username: String, password: String, create: bool) -> void:
	status_label.text = "Status: Registering..." if create else "Status: Logging in..."
	login_button.disabled = true
	register_button.disabled = true
	var base_url: String = NetworkConfigScript.resolve_nakama_base_url()
	var server_key: String = NetworkConfigScript.resolve_nakama_server_key()
	var result: Dictionary = await _nakama_client.register(base_url, server_key, username, password) if create else await _nakama_client.login(base_url, server_key, username, password)
	if result["outcome"] == NakamaHttpClientScript.OUTCOME_OK:
		PlayerIdentity.account_id = String(result["user_id"])
		PlayerIdentity.nakama_user_id = String(result["user_id"])
		PlayerIdentity.username = String(result["username"])
		PlayerIdentity.nakama_auth_token = String(result["auth_token"])
		PlayerIdentity.nakama_refresh_token = String(result["refresh_token"])
		status_label.text = "Status: Login successful! Loading characters..."
		await get_tree().create_timer(0.3).timeout
		get_tree().change_scene_to_file("res://client/character_gate.tscn")
	else:
		var action: String = "Registration" if create else "Login"
		status_label.text = "Status: %s failed (%s)" % [action, _nakama_failure_reason(result)]
		login_button.disabled = false
		register_button.disabled = false


func _nakama_failure_reason(result: Dictionary) -> String:
	var outcome: String = String(result.get("outcome", "error"))
	if outcome == NakamaHttpClientScript.OUTCOME_HTTP_ERROR and int(result.get("status", 0)) == 401:
		return "invalid username or password"
	if outcome == NakamaHttpClientScript.OUTCOME_CONFIG_ERROR:
		return "nakama not configured"
	return outcome

## Slice 093: maps a bounded EnrollmentHttpClient failure result to a short,
## input-free status string (never echoes the caller's credentials).
func _https_failure_reason(result: Dictionary) -> String:
	var outcome: String = String(result.get("outcome", "error"))
	if outcome == EnrollmentHttpClientScript.OUTCOME_HTTP_ERROR and int(result.get("status", 0)) == 401:
		return "invalid username or password"
	return outcome

func _on_register_pressed() -> void:
	if not _apply_settings():
		return
	var username = username_input.text.strip_edges()
	var password = password_input.text
	var host = host_input.text.strip_edges()
	
	if NetworkConfigScript.client_nakama_login_enabled():
		if not _validate_input(username, password):
			return
		PlayerIdentity.target_host = host if not host.is_empty() else NetworkConfigScript.resolve_client_target_host()
		await _perform_nakama_auth(username, password, true)
		return

	# Slice 093: no public HTTPS registration surface exists yet (DT-010).
	if NetworkConfigScript.client_https_login_enabled():
		await _perform_https_register(username, password)
		return
	
	if not _validate_input(username, password):
		return
	
	status_label.text = "Status: Connecting..."
	login_button.disabled = true
	register_button.disabled = true
	
	# Store target host in PlayerIdentity for gameplay to inherit
	PlayerIdentity.target_host = host if not host.is_empty() else NetworkConfigScript.resolve_client_target_host()
	
	# The login screen owns opening the connection; queue the request so it
	# fires once connected (submit_register is a no-op until the handshake ends).
	_pending_action = "register"
	_pending_username = username
	_pending_password = password
	if NetworkClient.status.begins_with("connected"):
		_fire_pending_auth()
	else:
		_connect_for_auth()


func _perform_https_register(username: String, password: String) -> void:
	status_label.text = "Status: Registering..."
	login_button.disabled = true
	register_button.disabled = true
	var result: Dictionary = await _http_client.register(EnrollmentHttpClientScript.resolve_base_url(), username, password)
	if result["outcome"] == EnrollmentHttpClientScript.OUTCOME_OK:
		status_label.text = "Status: Registration successful! Logging in..."
		await _perform_https_login(username, password)
	else:
		status_label.text = "Status: Registration failed (%s)" % _https_failure_reason(result)
		login_button.disabled = false
		register_button.disabled = false

## Opens the auth connection to the login endpoint when the client login split is
## enabled (PROJECT0_CLIENT_LOGIN_SPLIT=1), else to the game port as before.
func _connect_for_auth() -> void:
	var port: int = NetworkConfigScript.resolve_login_port() if NetworkConfigScript.client_login_split_enabled() else NetworkConfigScript.resolve_server_port()
	NetworkClient.connect_to_server(PlayerIdentity.target_host, port)

## Sends the queued register/login RPC, then drops the cached password.
func _fire_pending_auth() -> void:
	if _pending_action == "login":
		status_label.text = "Status: Logging in..."
		NetworkClient.submit_login(_pending_username, _pending_password)
	elif _pending_action == "register":
		status_label.text = "Status: Registering..."
		NetworkClient.submit_register(_pending_username, _pending_password)
	_pending_action = ""
	_pending_password = ""

func _on_auth_result(outcome: String, account_id: String, username: String) -> void:
	if outcome == "ok":
		# Successful auth — store account identity and transition to character selection
		PlayerIdentity.account_id = account_id
		PlayerIdentity.username = username
		status_label.text = "Status: Authentication successful! Loading characters..."
		
		# Transition to character_gate.tscn
		await get_tree().create_timer(0.5).timeout
		get_tree().change_scene_to_file("res://client/character_gate.tscn")
	else:
		# Authentication failed
		status_label.text = "Status: Login failed (%s)" % outcome
		login_button.disabled = false
		register_button.disabled = false

func _on_connection_status(status_str: String) -> void:
	status_label.text = "Status: " + status_str
	if status_str.begins_with("connected"):
		if _pending_action != "":
			_fire_pending_auth()
	elif status_str.begins_with("failed") or status_str == "disconnected":
		# The connection attempt ended without success; let the player retry.
		_pending_action = ""
		_pending_password = ""
		login_button.disabled = false
		register_button.disabled = false

func _validate_input(username: String, password: String) -> bool:
	if username.length() < 4 or username.length() > 20:
		status_label.text = "Status: Username must be 4-20 characters"
		return false
	
	if password.length() < 6:
		status_label.text = "Status: Password must be at least 6 characters"
		return false
	
	return true


func _on_settings_pressed() -> void:
	settings_panel.visible = not settings_panel.visible


func _apply_settings() -> bool:
	var host: String = host_input.text.strip_edges()
	var port_text: String = game_port_input.text.strip_edges()
	var port: int = port_text.to_int() if port_text.is_valid_int() else 0
	if host.is_empty():
		status_label.text = "Status: Enter a server host"
		return false
	if port < 1 or port > 65535:
		status_label.text = "Status: Port must be 1-65535"
		return false
	remote_server_checkbox.button_pressed = login_mode_option.selected == 0
	PlayerIdentity.target_host = host
	OS.set_environment(NetworkConfigScript.SERVER_PORT_ENV_VAR, str(port))
	OS.set_environment(NetworkConfigScript.CLIENT_HTTPS_LOGIN_ENV_VAR, "1" if remote_server_checkbox.button_pressed else "0")
	OS.set_environment(NetworkConfigScript.CLIENT_LOGIN_SPLIT_ENV_VAR, "0" if remote_server_checkbox.button_pressed else "1")
	OS.set_environment(NetworkConfigScript.TARGET_HOST_ENV_VAR, host)
	if not remote_server_checkbox.button_pressed:
		PlayerIdentity.target_host = "192.168.1.254"
		OS.set_environment(NetworkConfigScript.TARGET_HOST_ENV_VAR, "192.168.1.254")
	_save_settings()
	return true


func _on_remote_server_toggled(enabled: bool) -> void:
	login_mode_option.select(0 if enabled else 1)
	host_input.text = REMOTE_SERVER_HOST if enabled else LAN_SERVER_HOST


func _load_settings() -> void:
	host_input.text = REMOTE_SERVER_HOST
	remote_server_checkbox.button_pressed = true
	var settings := ConfigFile.new()
	if settings.load(SETTINGS_PATH) != OK:
		return
	remote_server_checkbox.button_pressed = bool(settings.get_value("connection", "remote_enabled", true))


func _save_settings() -> void:
	var settings := ConfigFile.new()
	settings.set_value("connection", "remote_host", host_input.text.strip_edges())
	settings.set_value("connection", "remote_enabled", remote_server_checkbox.button_pressed)
	settings.save(SETTINGS_PATH)
