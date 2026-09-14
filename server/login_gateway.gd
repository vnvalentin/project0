extends Node
class_name LoginGateway
## Slice 058: the in-process login interface (seam) for the container-platform
## login-boundary decision (.scratch/container-platform/issues/02-account-login-service-boundary.md).
## A thin facade composing the existing AuthService (register/login/session) and
## CharacterService (Character CRUD + selected-Character resolution) behind ONE
## narrow interface, so the RPC dispatch talks to a single login collaborator.
## Pure delegation — no behavior change. A future out-of-process login service
## (signed assertions over private HTTPS, Slices 059-060) will satisfy this same
## interface, replacing only this facade's internals.
##
## Server-only per CLAUDE.md: shared/ and client/ never construct it; the client
## reaches it only through the existing server-side RPC receivers.

var _auth: Object = null
var _characters: Object = null


func _init(auth_service: Object, character_service: Object) -> void:
	_auth = auth_service
	_characters = character_service


## Account authentication (delegates to AuthService; coroutine — PBKDF2 runs
## off-thread inside AuthService, never on the main tick).
func register(peer_id: int, username: String, password: String) -> Dictionary:
	return await _auth.register(peer_id, username, password)


func login(peer_id: int, username: String, password: String) -> Dictionary:
	return await _auth.login(peer_id, username, password)


## Game-server-local session state (per the login-boundary decision, the game
## server keeps its own per-peer session binding).
func is_authenticated(peer_id: int) -> bool:
	return _auth.is_authenticated(peer_id)


func clear_session(peer_id: int) -> void:
	_auth.clear_session(peer_id)


## Character operations (delegate to CharacterService, which derives the account
## from the peer's session — the client never supplies an account_id).
func list_characters(peer_id: int) -> Dictionary:
	return _characters.list_characters(peer_id)


func create_character(peer_id: int, character_name, cosmetic) -> Dictionary:
	return _characters.create_character(peer_id, character_name, cosmetic)


func select_character(peer_id: int, character_id) -> Dictionary:
	return _characters.select_character(peer_id, character_id)


func delete_character(peer_id: int, character_id) -> Dictionary:
	return _characters.delete_character(peer_id, character_id)


func get_selected_character(peer_id: int) -> Dictionary:
	return _characters.get_selected_character(peer_id)
