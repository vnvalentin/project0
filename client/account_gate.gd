## Slice 044: Account login/register screen controller.
## Manages username/password input, calls NetworkClient auth RPCs,
## listens to auth_result_received signal, and transitions to character_gate.tscn
## on successful authentication.
extends Control

@onready var username_input = $VBoxContainer/UsernameInput
@onready var password_input = $VBoxContainer/PasswordInput
@onready var host_input = $VBoxContainer/HostInput
@onready var status_label = $VBoxContainer/StatusLabel
@onready var login_button = $VBoxContainer/ButtonContainer/LoginButton
@onready var register_button = $VBoxContainer/ButtonContainer/RegisterButton

func _ready() -> void:
	# Connect to NetworkClient auth signals
	NetworkClient.auth_result_received.connect(_on_auth_result)
	NetworkClient.connection_status_changed.connect(_on_connection_status)
	
	# Enable/disable buttons based on connection status
	_update_button_states()
	
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
	
	# Open connection if not already connected, then submit login
	if not NetworkClient.status.begins_with("connected"):
		NetworkClient.connect_to_server(PlayerIdentity.target_host)
	
	# Submit login RPC (handled asynchronously)
	NetworkClient.submit_login(username, password)

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
	
	# Open connection if not already connected, then submit register
	if not NetworkClient.status.begins_with("connected"):
		NetworkClient.connect_to_server(PlayerIdentity.target_host)
	
	# Submit register RPC (handled asynchronously)
	NetworkClient.submit_register(username, password)

func _on_auth_result(outcome: String, account_id: String, username: String) -> void:
	if outcome == "OK":
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
	_update_button_states()

func _update_button_states() -> void:
	var is_connected = NetworkClient.status.begins_with("connected")
	login_button.disabled = not is_connected
	register_button.disabled = not is_connected

func _validate_input(username: String, password: String) -> bool:
	if username.length() < 4 or username.length() > 20:
		status_label.text = "Status: Username must be 4-20 characters"
		return false
	
	if password.length() < 6:
		status_label.text = "Status: Password must be at least 6 characters"
		return false
	
	return true
