extends Node
class_name CharacterService
## Slice 042: server-only, session-gated Character CRUD dispatch (see
## .scratch/player-accounts/handoff-042-character-crud-rpc.md and
## docs/slices/042-character-crud-rpc.md). Wraps the Slice 039
## AccountCharacterRepository (consumed unmodified) and the Slice 040
## SessionRegistry (consumed unmodified, shared with AuthService via
## server_main.gd so both see one session state). Mirrors AuthService's
## dispatch style: every method takes a bare `peer_id`, resolves the peer's
## session, and returns a bounded result Dictionary — never raises.
##
## AUTHORIZATION CORE (CLAUDE.md's "server owns outcomes" / this slice's
## non-negotiable safety invariant): every method below derives `account_id`
## from the caller's authenticated SessionRegistry entry. The client/caller
## NEVER supplies an account_id — a peer authenticated as account A cannot
## list/select/delete a Character owned by account B merely by knowing B's
## character_id, because the repository's ownership check is always run
## against A's own session account, never a client-supplied one. Every method
## requires an authenticated session before touching the repository; an
## unauthenticated call has no side effect.

const CharacterRecordScript: Script = preload("res://shared/character_record.gd")
const SessionRegistryScript: Script = preload("res://server/session_registry.gd")

const OUTCOME_OK: String = "ok"
const REJECT_NOT_AUTHENTICATED: String = "NOT_AUTHENTICATED"
const REJECT_NO_CHARACTER_SELECTED: String = "NO_CHARACTER_SELECTED"

var _repository: AccountCharacterRepository = null
var _sessions: SessionRegistry = null


## Public seam. `sessions` must be the SAME SessionRegistry instance AuthService
## uses (server_main.gd wires both), so a session bound by register/login is
## visible here without a second session store.
func _init(repository: AccountCharacterRepository, sessions: SessionRegistry) -> void:
	_repository = repository
	_sessions = sessions


## Public seam. Lists `peer_id`'s own session account's live Characters as
## CharacterRecord DTOs. Returns:
##   {"outcome": OUTCOME_OK, "characters": CharacterRecord[]}
##   {"outcome": REJECT_NOT_AUTHENTICATED, "detail": String}
func list_characters(peer_id: int) -> Dictionary:
	var account_id: String = _require_session_account(peer_id)
	if account_id.is_empty():
		return _reject_unauthenticated(peer_id)
	return _repository.list_characters(account_id)


## Public seam. Creates a Character under `peer_id`'s own session account.
## Returns:
##   {"outcome": OUTCOME_OK, "character": CharacterRecord}
##   {"outcome": CharacterRecord.REJECT_NAME_INVALID / REJECT_NAME_TAKEN / REJECT_CHARACTER_CAP_REACHED, "detail": String}
##   {"outcome": REJECT_NOT_AUTHENTICATED, "detail": String}
func create_character(peer_id: int, name: Variant, cosmetic: Variant) -> Dictionary:
	var account_id: String = _require_session_account(peer_id)
	if account_id.is_empty():
		return _reject_unauthenticated(peer_id)
	return _repository.create_character(account_id, name, cosmetic)


## Public seam. Selects `character_id` on behalf of `peer_id`'s own session
## account — ownership is enforced by the repository against that session
## account, never a client-supplied one. On success, also records the
## selection on the session (consumed by a future Slice 6 world-entry seam;
## not itself instantiating a Player here) and refreshes `last_played_at` via
## the repository. Returns:
##   {"outcome": OUTCOME_OK, "character": CharacterRecord}
##   {"outcome": CharacterRecord.REJECT_NOT_OWNER / REJECT_NO_SUCH_CHARACTER, "detail": String}
##   {"outcome": REJECT_NOT_AUTHENTICATED, "detail": String}
func select_character(peer_id: int, character_id: Variant) -> Dictionary:
	var account_id: String = _require_session_account(peer_id)
	if account_id.is_empty():
		return _reject_unauthenticated(peer_id)

	var result: Dictionary = _repository.select_character(account_id, character_id)
	if result["outcome"] == OUTCOME_OK:
		_sessions.set_selected_character(peer_id, (result["character"] as CharacterRecord).character_id)
	return result


## Public seam. Soft-deletes `character_id` on behalf of `peer_id`'s own
## session account — ownership enforced against that session account only.
## Returns:
##   {"outcome": OUTCOME_OK, "detail": String}
##   {"outcome": CharacterRecord.REJECT_NOT_OWNER / REJECT_NO_SUCH_CHARACTER / REJECT_ALREADY_DELETED, "detail": String}
##   {"outcome": REJECT_NOT_AUTHENTICATED, "detail": String}
func delete_character(peer_id: int, character_id: Variant) -> Dictionary:
	var account_id: String = _require_session_account(peer_id)
	if account_id.is_empty():
		return _reject_unauthenticated(peer_id)
	return _repository.soft_delete_character(account_id, character_id)


## Public seam (Slice 043 world entry). Returns the CharacterRecord the peer
## has selected on its session (Slice 042 recorded it via select_character) so
## the server can instantiate the Player as that Character. Derives everything
## from the session — the client never names the account or the character here.
## Returns:
##   {"outcome": OUTCOME_OK, "character": CharacterRecord}
##   {"outcome": REJECT_NOT_AUTHENTICATED, "detail": String}
##   {"outcome": REJECT_NO_CHARACTER_SELECTED, "detail": String}
##   {"outcome": CharacterRecord.REJECT_NO_SUCH_CHARACTER, "detail": String}
func get_selected_character(peer_id: int) -> Dictionary:
	var account_id: String = _require_session_account(peer_id)
	if account_id.is_empty():
		return _reject_unauthenticated(peer_id)
	# Slice 075: an assertion-established session carries a signed Character
	# snapshot; bind from it directly, since the game server's DB has no such
	# record. The in-process login path has no snapshot and resolves via the DB.
	var snapshot: Dictionary = _sessions.get_selected_character_snapshot(peer_id)
	if not snapshot.is_empty():
		return {"outcome": OUTCOME_OK, "character": _record_from_snapshot(account_id, snapshot)}
	var selected_id: String = _sessions.get_selected_character(peer_id)
	if selected_id.is_empty():
		return {"outcome": REJECT_NO_CHARACTER_SELECTED, "detail": "Peer %d has not selected a Character." % peer_id}
	var list_result: Dictionary = _repository.list_characters(account_id)
	for record: Object in list_result.get("characters", []):
		if (record as CharacterRecord).character_id == selected_id:
			return {"outcome": OUTCOME_OK, "character": record}
	return {"outcome": CharacterRecordScript.REJECT_NO_SUCH_CHARACTER, "detail": "Selected Character %s is no longer available." % selected_id}


## Slice 075: builds a CharacterRecord from the session's signed snapshot
## (identity + presentation only; created/last-played are unknown to the game
## server and are not needed to bind a Player).
func _record_from_snapshot(account_id: String, snapshot: Dictionary) -> CharacterRecord:
	return CharacterRecordScript.new(
		String(snapshot.get("character_id", "")),
		account_id,
		String(snapshot.get("display_name", "")),
		snapshot.get("cosmetic", {}),
		0,
		0
	)


## Returns the session's account_id, or an empty String if `peer_id` holds no
## authenticated session. Empty String is never a valid account_id (the
## repository always generates non-empty ids), so callers can treat the empty
## return as an unambiguous "not authenticated" signal.
func _require_session_account(peer_id: int) -> String:
	if not _sessions.is_authenticated(peer_id):
		return ""
	return String(_sessions.get_session(peer_id).get("account_id", ""))


func _reject_unauthenticated(peer_id: int) -> Dictionary:
	return {
		"outcome": REJECT_NOT_AUTHENTICATED,
		"detail": "Peer %d holds no authenticated session." % peer_id,
	}
