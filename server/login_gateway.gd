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
## Slice 085: the SessionRegistry for all session ops (bind/query/clear). Shared
## with AuthService on the login process; provided directly on the game server,
## which builds no AuthService (no register/login/PBKDF2 in the game process).
var _sessions: Object = null
# Slice 060: optional assertion seams (Slice 059 issuer/validator), injected by
# server_main. When set, the gateway can mint session assertions and establish a
# game-server session from a validated one — the mechanism a future
# out-of-process login service drives across the wire.
var _issuer: Object = null
var _validator: Object = null
var _nakama_authorized_peers: Dictionary = {}
var _journey_registry: Object = null

const OUTCOME_OK: String = "ok"
const REASON_NO_SESSION: String = "no_session"
const REASON_NO_CHARACTER: String = "no_character"
const REASON_UNAVAILABLE: String = "unavailable"
## Slice 076: returned by the account-authority operations when this gateway runs
## in assertion-only mode (the game server in a split deployment). Accounts live
## on the login process; the game server accepts only the assertion path.
const REASON_ACCOUNT_AUTHORITY_DISABLED: String = "account_authority_disabled"

# Slice 076: when false, register/login/Character-CRUD are refused (the game
# server is not an accounts authority). The assertion path is always available.
var _account_authority_enabled: bool = true


func _init(auth_service: Object, character_service: Object, session_registry: Object = null) -> void:
	_auth = auth_service
	_characters = character_service
	if session_registry != null:
		_sessions = session_registry
	elif auth_service != null:
		_sessions = auth_service.get_session_registry()
	# No AuthService => this gateway is not an accounts authority (assertion-only).
	_account_authority_enabled = auth_service != null


## Slice 076: toggles whether this gateway acts as an accounts authority. The
## login process leaves it enabled; the game server disables it in assertion-only
## mode so a client can only establish a session by presenting a signed assertion.
func set_account_authority_enabled(enabled: bool) -> void:
	_account_authority_enabled = enabled


## Account authentication (delegates to AuthService; coroutine — PBKDF2 runs
## off-thread inside AuthService, never on the main tick).
func register(peer_id: int, username: String, password: String) -> Dictionary:
	if not _account_authority_enabled:
		return {"outcome": REASON_ACCOUNT_AUTHORITY_DISABLED}
	return await _auth.register(peer_id, username, password)


func login(peer_id: int, username: String, password: String) -> Dictionary:
	if not _account_authority_enabled:
		return {"outcome": REASON_ACCOUNT_AUTHORITY_DISABLED}
	return await _auth.login(peer_id, username, password)


## Game-server-local session state (per the login-boundary decision, the game
## server keeps its own per-peer session binding).
func get_session_epoch(peer_id: int) -> int:
	return _sessions.get_session_epoch(peer_id)


func is_authenticated(peer_id: int) -> bool:
	return _sessions.is_authenticated(peer_id)


## Public seam (Slice 171). Returns only presentation-safe identity fields for
## server-authored presence; session tokens and credential material never leave
## the SessionRegistry.
func get_presence_identity(peer_id: int) -> Dictionary:
	if not _sessions.is_authenticated(peer_id):
		return {}
	var session: Dictionary = _sessions.get_session(peer_id)
	return {
		"account_id": String(session.get("account_id", "")),
		"character_id": _sessions.get_selected_character(peer_id),
	}


## Public seam (Slice 175). Binds only the bounded identity result returned by
## the server-side Nakama validator; no client identity field reaches this call.
func bind_validated_nakama_session(peer_id: int, validated: Dictionary) -> Dictionary:
	var result: Dictionary = _characters.bind_validated_nakama_session(peer_id, validated)
	if result.get("outcome", "") == OUTCOME_OK:
		_nakama_authorized_peers[peer_id] = true
	return result


func clear_session(peer_id: int) -> void:
	_sessions.clear(peer_id)
	_nakama_authorized_peers.erase(peer_id)


## Character operations (delegate to CharacterService, which derives the account
## from the peer's session — the client never supplies an account_id). Refused in
## assertion-only mode; the client performs these on the login process.
func list_characters(peer_id: int) -> Dictionary:
	if not _account_authority_enabled and not _nakama_authorized_peers.has(peer_id):
		return {"outcome": REASON_ACCOUNT_AUTHORITY_DISABLED}
	return _characters.list_characters(peer_id)


func create_character(peer_id: int, character_name, cosmetic) -> Dictionary:
	if not _account_authority_enabled and not _nakama_authorized_peers.has(peer_id):
		return {"outcome": REASON_ACCOUNT_AUTHORITY_DISABLED}
	return _characters.create_character(peer_id, character_name, cosmetic)


func select_character(peer_id: int, character_id) -> Dictionary:
	if not _account_authority_enabled and not _nakama_authorized_peers.has(peer_id):
		return {"outcome": REASON_ACCOUNT_AUTHORITY_DISABLED}
	return _characters.select_character(peer_id, character_id)


func delete_character(peer_id: int, character_id) -> Dictionary:
	if not _account_authority_enabled and not _nakama_authorized_peers.has(peer_id):
		return {"outcome": REASON_ACCOUNT_AUTHORITY_DISABLED}
	return _characters.delete_character(peer_id, character_id)


## Resolves the peer's selected Character for world entry. Always available (even
## in assertion-only mode) — it reads the session (snapshot from a validated
## assertion, or the DB in the in-process path), not the accounts authority.
func get_selected_character(peer_id: int) -> Dictionary:
	var result: Dictionary = _characters.get_selected_character(peer_id)
	if result.get("outcome", "") != OUTCOME_OK or _journey_registry == null:
		return result
	var record: Object = result["character"]
	var journey: Dictionary = _journey_registry.enter(record.character_id, peer_id, int(Time.get_unix_time_from_system()))
	if journey.get("outcome", "") != OUTCOME_OK:
		return {"outcome": journey.get("outcome", "journey_rejected")}
	result["journey_id"] = String(journey["journey_id"])
	result["journey"] = journey.get("journey", {}).duplicate(true)
	return result


func set_journey_registry(registry: Object) -> void:
	_journey_registry = registry


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
	var sessions: Object = _sessions
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
	var sessions: Object = _sessions
	if not sessions.is_authenticated(peer_id):
		return {"outcome": REASON_NO_SESSION}
	var character_id: String = sessions.get_selected_character(peer_id)
	if character_id.is_empty():
		return {"outcome": REASON_NO_CHARACTER}
	var session: Dictionary = sessions.get_session(peer_id)
	# Slice 075: carry the selected Character's presentation snapshot (from the
	# login-side DB) inside the signed assertion so the game server can bind a
	# Player without its own DB holding the record.
	var character_name: String = ""
	var character_cosmetic: Dictionary = {}
	var selected: Dictionary = _characters.get_selected_character(peer_id)
	if selected.get("outcome", "") == OUTCOME_OK:
		var record: Object = selected["character"]
		character_name = String(record.display_name)
		character_cosmetic = record.cosmetic
	var token: String = _issuer.issue(String(session["session_token"]), String(session["account_id"]), character_id, now_unix, ttl_seconds, character_name, character_cosmetic)
	return {"outcome": OUTCOME_OK, "assertion": token}


## Slice 089: validates an assertion WITHOUT binding any session — a pure
## signature/claims check for the enrollment service's loopback delegator
## (server/login_loopback_http_endpoint.gd, POST /internal/validate-assertion),
## which needs the account identity to key peer provisioning but has no gameplay
## session. Unlike establish_session_from_assertion, this never touches the
## SessionRegistry. Fail-closed: unavailable when no validator is wired.
func validate_assertion(token: String, now_unix: int) -> Dictionary:
	if _validator == null:
		return {"outcome": REASON_UNAVAILABLE}
	return _validator.validate(token, now_unix)


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
	var sessions: Object = _sessions
	sessions.bind(peer_id, String(claims[SessionAssertionScript.KEY_ACCOUNT_ID]), "")
	var character_id: String = String(claims[SessionAssertionScript.KEY_CHARACTER_ID])
	if not character_id.is_empty():
		# Slice 075: store the signed Character snapshot so world entry can bind a
		# Player from it (the game server's DB holds no such record).
		sessions.set_selected_character_snapshot(
			peer_id,
			character_id,
			String(claims.get(SessionAssertionScript.KEY_CHARACTER_NAME, "")),
			claims.get(SessionAssertionScript.KEY_CHARACTER_COSMETIC, {})
		)
	return {"outcome": OUTCOME_OK, "claims": claims}
