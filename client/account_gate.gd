## Slice 044: Account login/register screen controller.
## Manages username/password input, calls NetworkClient auth RPCs,
## listens to auth_result_received signal, and transitions to character_gate.tscn
## on successful authentication.
extends Control

const NetworkConfigScript: Script = preload("res://shared/network_config.gd")

@onready var username_input = $VBoxContainer/UsernameInput
@onready var password_input = $VBoxContainer/PasswordInput
@onready var host_input = $VBoxContainer/HostInput
@onready var status_label = $VBoxContainer/StatusLabel
@onready var login_button = $VBoxContainer/ButtonContainer/LoginButton
@onready var register_button = $VBoxContainer/ButtonContainer/RegisterButton

## The queued auth request ("login"/"register") to send once the ENet
## connection is established; empty when no request is in flight. The cached
## password is dropped the moment the request is sent.
var _pending_action: String = ""
var _pending_username: String = ""
var _pending_password: String = ""

func _ready() -> void:
	# Connect to NetworkClient auth signals
	NetworkClient.auth_result_received.connect(_on_auth_result)
	NetworkClient.connection_status_changed.connect(_on_connection_status)
	
	# Login/Register stay enabled; a request disables them until it resolves.
	
	# Default host input to the resolved target (allows override)
	var resolved_host = NetworkConfigScript.resolve_client_target_host()
	host_input.text = resolved_host

func _on_login_pressed() -> void:
	var username = username_input.text.strip_edges()
	var password = password_input.text
	var host = host_input.text.strip_edges()
	
	if not _validate_input(username, password):
		return
	
	status_label.text = "Status: Connecting..."
	login_button.disabled = true
	register_button.disabled = true
	
	# Store target host in PlayerIdentity for gameplay to inherit
	PlayerIdentity.target_host = host if not host.is_empty() else NetworkConfigScript.resolve_client_target_host()
	
	# The login screen owns opening the connection; queue the request so it
	# fires once connected (submit_login is a no-op until the handshake ends).
	_pending_action = "login"
	_pending_username = username
	_pending_password = password
	if NetworkClient.status.begins_with("connected"):
		_fire_pending_auth()
	else:
		_connect_for_auth()

func _on_register_pressed() -> void:
	var username = username_input.text.strip_edges()
	var password = password_input.text
	var host = host_input.text.strip_edges()
	
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
