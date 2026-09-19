extends RefCounted
class_name WorldEntryTicketService
## Slice 169: server-only world-entry ticket contract for Nakama sessions.
## Wraps the existing signed SessionAssertion format with v1-specific rules:
## selected Character required, short TTL supplied by caller, and one-time
## consume/invalidate tracking in this service instance.

const SessionAssertionScript: Script = preload("res://shared/session_assertion.gd")

const OUTCOME_OK: String = "ok"
const REASON_UNAVAILABLE: String = "unavailable"
const REASON_NO_SESSION: String = "no_session"
const REASON_NO_CHARACTER: String = "no_character"
const REASON_REPLAYED: String = "replayed"

var _issuer: Object = null
var _validator: Object = null
var _sessions: SessionRegistry = null
var _characters: CharacterService = null
var _consumed_tokens: Dictionary = {}


func _init(issuer: Object, validator: Object, sessions: SessionRegistry, characters: CharacterService) -> void:
	_issuer = issuer
	_validator = validator
	_sessions = sessions
	_characters = characters


func issue(peer_id: int, now_unix: int, ttl_seconds: int) -> Dictionary:
	if _issuer == null:
		return {"outcome": REASON_UNAVAILABLE}
	if ttl_seconds <= 0:
		return {"outcome": SessionAssertionScript.REASON_INVALID_CLAIMS}
	if not _sessions.is_authenticated(peer_id):
		return {"outcome": REASON_NO_SESSION}

	var selected: Dictionary = _characters.get_selected_character(peer_id)
	if selected.get("outcome", "") != OUTCOME_OK:
		return {"outcome": REASON_NO_CHARACTER}

	var session: Dictionary = _sessions.get_session(peer_id)
	var character: CharacterRecord = selected["character"]
	var token: String = _issuer.issue(
		String(session["session_token"]),
		String(session["account_id"]),
		character.character_id,
		now_unix,
		ttl_seconds,
		character.display_name,
		character.cosmetic
	)
	return {"outcome": OUTCOME_OK, "ticket": token}


func consume(peer_id: int, ticket: String, now_unix: int) -> Dictionary:
	if _validator == null:
		return {"outcome": REASON_UNAVAILABLE}
	if _consumed_tokens.has(ticket):
		return {"outcome": REASON_REPLAYED}

	var result: Dictionary = _validator.validate(ticket, now_unix)
	if result["outcome"] != OUTCOME_OK:
		return {"outcome": result["outcome"]}

	var claims: Dictionary = result["claims"]
	var character_id: String = String(claims[SessionAssertionScript.KEY_CHARACTER_ID])
	if character_id.is_empty():
		return {"outcome": REASON_NO_CHARACTER}

	_consumed_tokens[ticket] = true
	_sessions.bind(peer_id, String(claims[SessionAssertionScript.KEY_ACCOUNT_ID]), "")
	_sessions.set_selected_character_snapshot(
		peer_id,
		character_id,
		String(claims.get(SessionAssertionScript.KEY_CHARACTER_NAME, "")),
		claims.get(SessionAssertionScript.KEY_CHARACTER_COSMETIC, {})
	)
	return {"outcome": OUTCOME_OK, "claims": claims}


func invalidate(ticket: String) -> void:
	if not ticket.is_empty():
		_consumed_tokens[ticket] = true