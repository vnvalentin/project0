## Slice 044: Character select/create screen controller.
## Manages character list, create/select/delete operations, and transitions
## to gameplay.tscn on successful world-entry.
extends Control

const NetworkConfigScript: Script = preload("res://shared/network_config.gd")
## Slice 093: the client's HTTPS seam to the enrollment service for the WAN
## Character flow (list/create/select over HTTPS, then present the returned
## Character assertion to the game server through the tunnel).
const EnrollmentHttpClientScript: Script = preload("res://client/enrollment_http_client.gd")

@onready var status_label = $VBoxContainer/StatusLabel
@onready var character_list = $VBoxContainer/CharacterList
@onready var select_button = $VBoxContainer/ButtonContainer/SelectButton
@onready var create_button = $VBoxContainer/ButtonContainer/CreateButton
@onready var delete_button = $VBoxContainer/ButtonContainer/DeleteButton
@onready var create_dialog = $CreateCharacterDialog
@onready var name_input = $CreateCharacterDialog/VBoxContainer2/NameInput

var _characters: Array = []
## Slice 078: true while the login->game handoff is reconnecting, so the transient
## login disconnect does not surface as a "connection lost" alarm.
var _handing_off: bool = false
## Slice 093: true when this session runs the HTTPS (WAN) Character flow; the
## enrollment client instance is created only then.
var _https: bool = false
var _nakama: bool = false
var _nakama_presented: bool = false
var _http_client: Object = null

func _ready() -> void:
	# Connect to NetworkClient signals
	NetworkClient.character_result_received.connect(_on_character_result)
	NetworkClient.world_entry_received.connect(_on_world_entry_result)
	NetworkClient.login_to_game_handoff_finished.connect(_on_handoff_finished)
	NetworkClient.connection_status_changed.connect(_on_connection_status)
	
	# Connect UI signals
	character_list.item_selected.connect(_on_character_selected)
	
	# Immediately request character list
	status_label.text = "Status: Loading characters..."
	_nakama = NetworkConfigScript.client_nakama_login_enabled()
	if _nakama:
		await _connect_nakama_game()
		return
	_https = NetworkConfigScript.client_https_login_enabled()
	if _https:
		_http_client = EnrollmentHttpClientScript.new()
		add_child(_http_client)
		await _https_reload_characters()
	else:
		NetworkClient.submit_list_characters()


func _connect_nakama_game() -> void:
	NetworkClient.nakama_session_established_received.connect(_on_nakama_session_established, CONNECT_ONE_SHOT)
	NetworkClient.connect_to_server(PlayerIdentity.target_host, NetworkConfigScript.resolve_server_port())
	status_label.text = "Status: Connecting to game..."


func _on_nakama_session_established(outcome: String) -> void:
	if outcome != "ok":
		status_label.text = "Status: Nakama session failed (%s)" % outcome
		return
	status_label.text = "Status: Loading characters..."
	NetworkClient.submit_list_characters()

## Slice 093: (re)loads the account's Characters over HTTPS using the account
## assertion obtained at login. Fail-closed: a bounded failure shows a readable
## status and disables creation rather than leaving a stale roster.
func _https_reload_characters() -> void:
	var base_url: String = EnrollmentHttpClientScript.resolve_base_url()
	var result: Dictionary = await _http_client.list_characters(base_url, PlayerIdentity.account_assertion)
	if result["outcome"] == EnrollmentHttpClientScript.OUTCOME_OK:
		_characters = result["characters"]
		_refresh_character_list()
		status_label.text = "Status: Ready (%d characters)" % _characters.size()
	else:
		status_label.text = "Status: Failed to load characters (%s)" % String(result["outcome"])
		create_button.disabled = true

func _on_character_result(operation: String, outcome: String, characters: Array) -> void:
	match operation:
		"list":
			_handle_list_result(outcome, characters)
		"create":
			_handle_create_result(outcome)
		"select":
			_handle_select_result(outcome)
		"delete":
			_handle_delete_result(outcome)

func _handle_list_result(outcome: String, characters: Array) -> void:
	if outcome == "ok":
		_characters = characters
		_refresh_character_list()
		status_label.text = "Status: Ready (%d characters)" % characters.size()
	else:
		status_label.text = "Status: Failed to load characters (%s)" % outcome
		create_button.disabled = true

func _handle_create_result(outcome: String) -> void:
	if outcome == "ok":
		status_label.text = "Status: Character created! Reloading..."
		# Refresh the list to show the new character
		await get_tree().create_timer(0.3).timeout
		NetworkClient.submit_list_characters()
	else:
		status_label.text = "Status: Create failed (%s)" % outcome

func _handle_select_result(outcome: String) -> void:
	if outcome == "ok":
		status_label.text = "Status: Character selected! Entering world..."
		# Now attempt to enter the world with this character
		await get_tree().create_timer(0.3).timeout
		if _nakama:
			_handing_off = true
			NetworkClient.submit_enter_world()
		elif NetworkConfigScript.client_login_split_enabled():
			# Hand off to the game process: request assertion, reconnect, present,
			# enter world. Success flows through _on_world_entry_result below.
			_handing_off = true
			status_label.text = "Status: Entering world (login handoff)..."
			NetworkClient.perform_login_to_game_handoff(PlayerIdentity.target_host, NetworkConfigScript.resolve_server_port())
		else:
			NetworkClient.submit_enter_world()
	else:
		status_label.text = "Status: Select failed (%s)" % outcome

func _handle_delete_result(outcome: String) -> void:
	if outcome == "ok":
		status_label.text = "Status: Character deleted! Reloading..."
		# Refresh the list
		await get_tree().create_timer(0.3).timeout
		NetworkClient.submit_list_characters()
	else:
		status_label.text = "Status: Delete failed (%s)" % outcome

func _on_world_entry_result(outcome: String, character_dict: Dictionary) -> void:
	if outcome == "ok":
		# Successfully entered the world — store character and transition to gameplay
		PlayerIdentity.selected_character_id = character_dict.get("character_id", "")
		PlayerIdentity.selected_character = character_dict
		PlayerIdentity.display_name = character_dict.get("display_name", "Character")
		
		status_label.text = "Status: World entry successful! Loading gameplay..."
		await get_tree().create_timer(0.5).timeout
		get_tree().change_scene_to_file("res://client/gameplay.tscn")
	else:
		status_label.text = "Status: World entry failed (%s)" % outcome

func _on_connection_status(status_str: String) -> void:
	# Keep connection status visible
	if _handing_off:
		return
	if _nakama and status_str.begins_with("connected") and not _nakama_presented:
		_nakama_presented = true
		NetworkClient.submit_nakama_session(PlayerIdentity.nakama_auth_token)
		return
	if not status_str.begins_with("connected"):
		status_label.text = "Status: Connection lost (%s)" % status_str


## Slice 078: terminal outcome of the login->game handoff. On success,
## _on_world_entry_result already transitioned into gameplay; report failures.
func _on_handoff_finished(outcome: String, _character: Dictionary) -> void:
	_handing_off = false
	if outcome != "ok":
		status_label.text = "Status: World entry failed (%s)" % outcome

func _on_character_selected(index: int) -> void:
	select_button.disabled = false
	delete_button.disabled = false

func _on_select_pressed() -> void:
	var index = character_list.get_selected_items()
	if index.is_empty():
		status_label.text = "Status: Please select a character"
		return
	
	var selected_char = _characters[index[0]]
	var character_id = selected_char.get("character_id", "")
	
	select_button.disabled = true
	status_label.text = "Status: Selecting character..."
	if _nakama:
		NetworkClient.submit_select_character(character_id)
	elif _https:
		await _https_select_and_enter(character_id)
	else:
		NetworkClient.submit_select_character(character_id)

## Slice 093: selects the Character over HTTPS to obtain its signed assertion,
## then presents that assertion to the game server (through the tunnel) for world
## entry. Success/failure flows through _on_handoff_finished / _on_world_entry_result,
## exactly like the ENet login handoff. Fail-closed: an HTTPS select failure
## re-enables selection and never opens a game connection.
func _https_select_and_enter(character_id: String) -> void:
	var base_url: String = EnrollmentHttpClientScript.resolve_base_url()
	var result: Dictionary = await _http_client.select_character(base_url, PlayerIdentity.account_assertion, character_id)
	if result["outcome"] != EnrollmentHttpClientScript.OUTCOME_OK:
		status_label.text = "Status: Select failed (%s)" % String(result["outcome"])
		select_button.disabled = false
		return
	PlayerIdentity.character_assertion = String(result["assertion"])
	PlayerIdentity.selected_character_id = character_id
	_handing_off = true
	status_label.text = "Status: Entering world (tunnel)..."
	NetworkClient.perform_https_world_entry(PlayerIdentity.target_host, NetworkConfigScript.resolve_server_port(), PlayerIdentity.character_assertion)

func _on_create_pressed() -> void:
	name_input.text = ""
	create_dialog.popup_centered()

func _on_create_dialog_ok() -> void:
	var name = name_input.text.strip_edges()
	
	if name.is_empty() or name.length() < 1 or name.length() > 20:
		status_label.text = "Status: Name must be 1-20 characters"
		return
	
	create_button.disabled = true
	status_label.text = "Status: Creating character..."
	
	# For now, pass an empty cosmetic dict (to be extended later)
	var cosmetic = {}
	if _https:
		await _https_create_character(name, cosmetic)
	else:
		NetworkClient.submit_create_character(name, cosmetic)

## Slice 093: creates a Character over HTTPS, then reloads the roster. Fail-closed:
## a bounded failure re-enables creation with a readable status.
func _https_create_character(name: String, cosmetic: Dictionary) -> void:
	var base_url: String = EnrollmentHttpClientScript.resolve_base_url()
	var result: Dictionary = await _http_client.create_character(base_url, PlayerIdentity.account_assertion, name, cosmetic)
	if result["outcome"] == EnrollmentHttpClientScript.OUTCOME_OK:
		status_label.text = "Status: Character created! Reloading..."
		await get_tree().create_timer(0.3).timeout
		await _https_reload_characters()
	else:
		status_label.text = "Status: Create failed (%s)" % String(result["outcome"])
		create_button.disabled = false

func _on_delete_pressed() -> void:
	var index = character_list.get_selected_items()
	if index.is_empty():
		status_label.text = "Status: Please select a character to delete"
		return
	
	var selected_char = _characters[index[0]]
	var character_id = selected_char.get("character_id", "")
	var name = selected_char.get("display_name", "Unknown")
	
	# Confirm deletion
	var confirm = ConfirmationDialog.new()
	confirm.title = "Confirm Deletion"
	confirm.dialog_text = "Delete '%s'? This cannot be undone." % name
	add_child(confirm)
	confirm.popup_centered()
	
	await confirm.confirmed
	delete_button.disabled = true
	status_label.text = "Status: Deleting character..."
	if _https:
		await _https_delete_character(character_id)
	else:
		NetworkClient.submit_delete_character(character_id)
	
	confirm.queue_free()

## Slice 093: deletes a Character over HTTPS, then reloads the roster. Fail-closed:
## a bounded failure re-enables deletion with a readable status.
func _https_delete_character(character_id: String) -> void:
	var base_url: String = EnrollmentHttpClientScript.resolve_base_url()
	var result: Dictionary = await _http_client.delete_character(base_url, PlayerIdentity.account_assertion, character_id)
	if result["outcome"] == EnrollmentHttpClientScript.OUTCOME_OK:
		status_label.text = "Status: Character deleted! Reloading..."
		await get_tree().create_timer(0.3).timeout
		await _https_reload_characters()
	else:
		status_label.text = "Status: Delete failed (%s)" % String(result["outcome"])
		delete_button.disabled = false

func _refresh_character_list() -> void:
	character_list.clear()
	select_button.disabled = true
	delete_button.disabled = true
	
	for char in _characters:
		var display_name = char.get("display_name", "Unknown")
		var char_id = char.get("character_id", "")
		character_list.add_item("%s (%s)" % [display_name, char_id.substr(0, 8)])
