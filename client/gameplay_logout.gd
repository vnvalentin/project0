extends Button

const NetworkConfigScript: Script = preload("res://shared/network_config.gd")

func _ready() -> void:
	pressed.connect(_on_logout_pressed)

func _on_logout_pressed() -> void:
	PlayerIdentity.clear_selected_character()
	# Split topology: the account session lived on the login process, which the
	# world handoff already disconnected from, so the Character list is not
	# available on the game connection. Drop the game link and return to the
	# login screen to re-authenticate. Combined mode keeps one authenticated
	# connection, so it returns straight to Character selection.
	if NetworkConfigScript.client_login_split_enabled():
		NetworkClient.disconnect_from_server()
	get_tree().change_scene_to_file(_logout_target_scene())

## Public seam: the scene logout returns to, split-aware. Login screen under the
## split (re-auth required on the login process); Character screen in combined
## mode (the single authenticated connection persists).
func _logout_target_scene() -> String:
	if NetworkConfigScript.client_login_split_enabled():
		return "res://client/account_gate.tscn"
	return "res://client/character_gate.tscn"
