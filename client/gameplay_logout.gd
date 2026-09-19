extends Button

const NetworkConfigScript: Script = preload("res://shared/network_config.gd")

func _ready() -> void:
	pressed.connect(_on_logout_pressed)
	text = "Character Select"

func _on_logout_pressed() -> void:
	PlayerIdentity.clear_selected_character()
	# Combined mode keeps one authenticated connection, so it returns straight to
	# Character selection. Under the split the account session lived on the login
	# process, which the world handoff disconnected from — re-establish it from
	# the resume token (Slice 087) so the Character list loads, falling back to
	# the login screen if the token is missing or expired.
	if not NetworkConfigScript.client_login_split_enabled():
		get_tree().change_scene_to_file("res://client/character_gate.tscn")
		return
	disabled = true
	NetworkClient.return_to_character_select_finished.connect(_on_return_finished, CONNECT_ONE_SHOT)
	NetworkClient.perform_return_to_character_select(PlayerIdentity.target_host, NetworkConfigScript.resolve_login_port())

func _on_return_finished(outcome: String) -> void:
	get_tree().change_scene_to_file(_return_target_scene(outcome))

## Public seam: where the split return lands — the Character list when the login
## session was re-established from the resume token, else the login screen to
## re-authenticate.
func _return_target_scene(outcome: String) -> String:
	if outcome == "ok":
		return "res://client/character_gate.tscn"
	return "res://client/account_gate.tscn"
