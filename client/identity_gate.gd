extends Control
## Local identity gate: the player enters a display name before gameplay
## starts. No network handshake, no persistence — see docs/adr/0001.

const GAMEPLAY_SCENE_PATH: String = "res://client/gameplay.tscn"

@export var gameplay_scene_path: String = GAMEPLAY_SCENE_PATH

@onready var _name_input: LineEdit = $CenterContainer/VBoxContainer/NameInput
@onready var _server_host_input: LineEdit = $CenterContainer/VBoxContainer/ServerHostInput
@onready var _enter_button: Button = $CenterContainer/VBoxContainer/EnterButton
@onready var _error_label: Label = $CenterContainer/VBoxContainer/ErrorLabel

const NetworkConfigScript: Script = preload("res://shared/network_config.gd")


func _ready() -> void:
	_error_label.text = ""
	_server_host_input.text = NetworkConfigScript.resolve_client_target_host()
	_enter_button.pressed.connect(_on_enter_pressed)


## Public seam: validates the entered display name and, if non-empty,
## transitions to the gameplay scene. Rejects empty/whitespace-only names.
func _on_enter_pressed() -> void:
	var display_name: String = _name_input.text.strip_edges()
	if display_name.is_empty():
		_error_label.text = "Enter a name to continue."
		return

	PlayerIdentity.display_name = display_name
	PlayerIdentity.target_host = _server_host_input.text.strip_edges()
	get_tree().change_scene_to_file(gameplay_scene_path)
