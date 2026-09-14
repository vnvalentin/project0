extends Node
## Autoload singleton holding the current session's local identity in memory
## only. Never persisted to disk; cleared on process exit. See CONTEXT.md's
## Account/Character terms and docs/adr/0001.

## Slice 044: the authenticated Account and selected Character for this session,
## set by the login/character screens (client/account_gate.gd). Passwords are
## never stored here — only the AccountHandle fields the server returned.
var target_host: String = ""
var account_id: String = ""
var username: String = ""
var selected_character_id: String = ""
var selected_character: Dictionary = {}
## Kept as the selected Character's display name for any legacy reader.
var display_name: String = ""


func clear_session() -> void:
	account_id = ""
	username = ""
	clear_selected_character()


func clear_selected_character() -> void:
	selected_character_id = ""
	selected_character = {}
	display_name = ""
