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

const SessionAssertionScript: Script = preload("res://shared/session_assertion.gd")

var _auth: Object = null
var _characters: Object = null
# Slice 060: optional assertion seams (Slice 059 issuer/validator), injected by
# server_main. When set, the gateway can mint session assertions and establish a
# game-server session from a validated one — the mechanism a future
# out-of-process login service drives across the wire.
var _issuer: Object = null
var _validator: Object = null

const OUTCOME_OK: String = "ok"
const REASON_NO_SESSION: String = "no_session"
const REASON_NO_CHARACTER: String = "no_character"
const REASON_UNAVAILABLE: String = "unavailable"


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


## Slice 060: inject the Slice 059 assertion seams (issuer + validator).
func set_assertion_seams(issuer: Object, validator: Object) -> void:
	_issuer = issuer
	_validator = validator


## Mints an account-only session assertion for a peer's currently-bound session.
## now_unix/ttl_seconds are caller-supplied so issuance is deterministic and
## testable. Fail-closed: unavailable when no issuer is wired, no_session when
## the peer holds no authenticated session.
func issue_account_assertion(peer_id: int, now_unix: int, ttl_seconds: int) -> Dictionary:
	if _issuer == null:
		return {"outcome": REASON_UNAVAILABLE}
	var sessions: Object = _auth.get_session_registry()
	if not sessions.is_authenticated(peer_id):
		return {"outcome": REASON_NO_SESSION}
	var session: Dictionary = sessions.get_session(peer_id)
	var token: String = _issuer.issue(String(session["session_token"]), String(session["account_id"]), "", now_unix, ttl_seconds)
	return {"outcome": OUTCOME_OK, "assertion": token}


## Mints a refreshed selected-Character session assertion. Requires the peer to
## have selected a Character (else no_character).
func issue_character_assertion(peer_id: int, now_unix: int, ttl_seconds: int) -> Dictionary:
	if _issuer == null:
		return {"outcome": REASON_UNAVAILABLE}
	var sessions: Object = _auth.get_session_registry()
	if not sessions.is_authenticated(peer_id):
		return {"outcome": REASON_NO_SESSION}
	var character_id: String = sessions.get_selected_character(peer_id)
	if character_id.is_empty():
		return {"outcome": REASON_NO_CHARACTER}
	var session: Dictionary = sessions.get_session(peer_id)
	var token: String = _issuer.issue(String(session["session_token"]), String(session["account_id"]), character_id, now_unix, ttl_seconds)
	return {"outcome": OUTCOME_OK, "assertion": token}


## Establishes (binds) a game-server session for `peer_id` purely from a
## validated assertion — how the game server trusts the login authority without
## sharing a database. Fail-closed: binds a session only after the validator
## accepts the token; otherwise returns the bounded rejection and binds nothing.
func establish_session_from_assertion(peer_id: int, token: String, now_unix: int) -> Dictionary:
	if _validator == null:
		return {"outcome": REASON_UNAVAILABLE}
	var result: Dictionary = _validator.validate(token, now_unix)
	if result["outcome"] != OUTCOME_OK:
		return {"outcome": result["outcome"]}
	var claims: Dictionary = result["claims"]
	var sessions: Object = _auth.get_session_registry()
	sessions.bind(peer_id, String(claims[SessionAssertionScript.KEY_ACCOUNT_ID]), "")
	var character_id: String = String(claims[SessionAssertionScript.KEY_CHARACTER_ID])
	if not character_id.is_empty():
		sessions.set_selected_character(peer_id, character_id)
	return {"outcome": OUTCOME_OK, "claims": claims}
