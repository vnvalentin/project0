## Slice 044: Character select/create screen controller.
## Manages character list, create/select/delete operations, and transitions
## to gameplay.tscn on successful world-entry.
extends Control

@onready var status_label = $VBoxContainer/StatusLabel
@onready var character_list = $VBoxContainer/CharacterList
@onready var select_button = $VBoxContainer/ButtonContainer/SelectButton
@onready var create_button = $VBoxContainer/ButtonContainer/CreateButton
@onready var delete_button = $VBoxContainer/ButtonContainer/DeleteButton
@onready var create_dialog = $CreateCharacterDialog
@onready var name_input = $CreateCharacterDialog/VBoxContainer2/NameInput

var _characters: Array = []

func _ready() -> void:
	# Connect to NetworkClient signals
	NetworkClient.character_result_received.connect(_on_character_result)
	NetworkClient.world_entry_received.connect(_on_world_entry_result)
	NetworkClient.connection_status_changed.connect(_on_connection_status)
	
	# Connect UI signals
	character_list.item_selected.connect(_on_character_selected)
	create_dialog.confirmed.connect(_on_create_dialog_ok)
	
	# Immediately request character list
	status_label.text = "Status: Loading characters..."
	NetworkClient.submit_list_characters()

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
	if not status_str.begins_with("connected"):
		status_label.text = "Status: Connection lost (%s)" % status_str

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
	NetworkClient.submit_select_character(character_id)

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
	NetworkClient.submit_create_character(name, cosmetic)

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
	
	var confirmed = await confirm.confirmed
	if confirmed:
		delete_button.disabled = true
		status_label.text = "Status: Deleting character..."
		NetworkClient.submit_delete_character(character_id)
	
	confirm.queue_free()

func _refresh_character_list() -> void:
	character_list.clear()
	select_button.disabled = true
	delete_button.disabled = true
	
	for char in _characters:
		var display_name = char.get("display_name", "Unknown")
		var char_id = char.get("character_id", "")
		character_list.add_item("%s (%s)" % [display_name, char_id.substr(0, 8)])
