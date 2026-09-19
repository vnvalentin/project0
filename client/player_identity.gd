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

## Slice 093: signed assertions obtained over the public HTTPS enrollment surface
## in the WAN/tunnel flow. account_assertion authorizes account-scoped Character
## CRUD on the enrollment service; character_assertion carries the signed Character
## snapshot presented to the game server for world entry. In-memory only, never
## persisted, and empty in the LAN ENet path (which never mints them client-side).
var account_assertion: String = ""
var character_assertion: String = ""

## Slice 167: Nakama auth/session identity for the new v1 path. The Nakama user
## id is also copied into account_id so existing Account-term readers continue
## to treat the authenticated account root as one opaque id. Tokens are in-memory
## only and are never persisted by this autoload.
var nakama_user_id: String = ""
var nakama_auth_token: String = ""
var nakama_refresh_token: String = ""


func clear_session() -> void:
	account_id = ""
	username = ""
	account_assertion = ""
	character_assertion = ""
	nakama_user_id = ""
	nakama_auth_token = ""
	nakama_refresh_token = ""
	clear_selected_character()


func clear_selected_character() -> void:
	selected_character_id = ""
	selected_character = {}
	display_name = ""
