extends GutTest

const SqliteStoreScript: Script = preload("res://server/sqlite_store.gd")
const AccountCharacterRepositoryScript: Script = preload("res://server/account_character_repository.gd")
const SessionRegistryScript: Script = preload("res://server/session_registry.gd")
const CharacterServiceScript: Script = preload("res://server/character_service.gd")
const AssertionIssuerScript: Script = preload("res://server/assertion_issuer.gd")
const AssertionValidatorScript: Script = preload("res://server/assertion_validator.gd")
const WorldEntryTicketServiceScript: Script = preload("res://server/world_entry_ticket_service.gd")
const SessionAssertionScript: Script = preload("res://shared/session_assertion.gd")

const SECRET: String = "0f1e2d3c4b5a69788796a5b4c3d2e1f00f1e2d3c4b5a69788796a5b4c3d2e1f0"
const ISSUER: String = "project0-nakama"
const AUDIENCE: String = "project0-game"

var _relative_path: String = ""
var _store: SqliteStore = null
var _repo: AccountCharacterRepository = null
var _sessions: SessionRegistry = null
var _characters: CharacterService = null
var _tickets: WorldEntryTicketService = null


func before_each() -> void:
	_relative_path = "test_world_entry_ticket_%d_%d.db" % [Time.get_ticks_usec(), randi()]
	_store = SqliteStoreScript.new()
	_store.open(_relative_path)
	_repo = AccountCharacterRepositoryScript.new(_store)
	_repo.ensure_schema()
	_sessions = SessionRegistryScript.new()
	_characters = CharacterServiceScript.new(_repo, _sessions)
	_tickets = _make_ticket_service(_sessions, _characters)


func after_each() -> void:
	if _store.is_open():
		_store.close()
	if is_instance_valid(_characters):
		_characters.free()
	_delete_user_file(_relative_path)
	_delete_user_file(_relative_path + "-wal")
	_delete_user_file(_relative_path + "-shm")
	_delete_user_file(_relative_path + "-journal")


func _delete_user_file(relative_path: String) -> void:
	var abs_path: String = ProjectSettings.globalize_path("user://%s" % relative_path)
	if FileAccess.file_exists(abs_path):
		DirAccess.remove_absolute(abs_path)


func _make_ticket_service(sessions: SessionRegistry, characters: CharacterService, audience: String = AUDIENCE) -> WorldEntryTicketService:
	return WorldEntryTicketServiceScript.new(
		AssertionIssuerScript.new(SECRET, ISSUER, AUDIENCE),
		AssertionValidatorScript.new(SECRET, ISSUER, audience),
		sessions,
		characters
	)


func _bind_nakama_account_with_character(peer_id: int, user_id: String, character_name: String) -> CharacterRecord:
	var bound: Dictionary = _characters.bind_nakama_account_session(peer_id, user_id, "%s@example.test" % user_id)
	assert_eq(bound["outcome"], "ok", "Nakama bind succeeds: %s" % bound.get("detail", ""))
	var created: Dictionary = _characters.create_character(peer_id, character_name, {"hair": "silver"})
	assert_eq(created["outcome"], "ok", "Character create succeeds: %s" % created.get("detail", ""))
	var character: CharacterRecord = created["character"]
	var selected: Dictionary = _characters.select_character(peer_id, character.character_id)
	assert_eq(selected["outcome"], "ok", "Character select succeeds: %s" % selected.get("detail", ""))
	return character


func test_issue_requires_selected_character() -> void:
	var bound: Dictionary = _characters.bind_nakama_account_session(1, "nakama-user-1", "hero@example.test")
	assert_eq(bound["outcome"], "ok")
	var result: Dictionary = _tickets.issue(1, 1000, 60)
	assert_eq(result["outcome"], WorldEntryTicketServiceScript.REASON_NO_CHARACTER)


func test_issue_ticket_carries_character_claims() -> void:
	var character: CharacterRecord = _bind_nakama_account_with_character(1, "nakama-user-1", "NakamaHero")
	var issued: Dictionary = _tickets.issue(1, 1000, 60)
	assert_eq(issued["outcome"], "ok")

	var validator: AssertionValidator = AssertionValidatorScript.new(SECRET, ISSUER, AUDIENCE)
	var validated: Dictionary = validator.validate(issued["ticket"], 1001)
	assert_eq(validated["outcome"], "ok")
	var claims: Dictionary = validated["claims"]
	assert_eq(claims[SessionAssertionScript.KEY_ACCOUNT_ID], "nakama-user-1")
	assert_eq(claims[SessionAssertionScript.KEY_CHARACTER_ID], character.character_id)
	assert_eq(claims[SessionAssertionScript.KEY_CHARACTER_NAME], "NakamaHero")
	assert_eq(claims[SessionAssertionScript.KEY_EXPIRES_AT], 1060)


func test_consume_valid_ticket_binds_session_snapshot_once() -> void:
	var character: CharacterRecord = _bind_nakama_account_with_character(1, "nakama-user-1", "NakamaHero")
	var issued: Dictionary = _tickets.issue(1, 1000, 60)

	var game_sessions: SessionRegistry = SessionRegistryScript.new()
	var game_characters: CharacterService = CharacterServiceScript.new(_repo, game_sessions)
	var game_tickets: WorldEntryTicketService = _make_ticket_service(game_sessions, game_characters)
	var consumed: Dictionary = game_tickets.consume(7, issued["ticket"], 1001)
	assert_eq(consumed["outcome"], "ok")
	assert_eq(game_sessions.get_session(7).get("account_id", ""), "nakama-user-1")
	assert_eq(game_sessions.get_selected_character(7), character.character_id)
	assert_eq(game_sessions.get_selected_character_snapshot(7).get("display_name", ""), "NakamaHero")

	var replayed: Dictionary = game_tickets.consume(8, issued["ticket"], 1002)
	assert_eq(replayed["outcome"], WorldEntryTicketServiceScript.REASON_REPLAYED)
	assert_false(game_sessions.is_authenticated(8))
	game_characters.free()


func test_consume_rejects_expired_and_wrong_audience_without_binding() -> void:
	_bind_nakama_account_with_character(1, "nakama-user-1", "NakamaHero")
	var issued: Dictionary = _tickets.issue(1, 1000, 60)

	var expired_sessions: SessionRegistry = SessionRegistryScript.new()
	var expired_characters: CharacterService = CharacterServiceScript.new(_repo, expired_sessions)
	var expired_service: WorldEntryTicketService = _make_ticket_service(expired_sessions, expired_characters)
	var expired: Dictionary = expired_service.consume(7, issued["ticket"], 2000)
	assert_eq(expired["outcome"], SessionAssertionScript.REASON_EXPIRED)
	assert_false(expired_sessions.is_authenticated(7))
	expired_characters.free()

	var wrong_sessions: SessionRegistry = SessionRegistryScript.new()
	var wrong_characters: CharacterService = CharacterServiceScript.new(_repo, wrong_sessions)
	var wrong_service: WorldEntryTicketService = _make_ticket_service(wrong_sessions, wrong_characters, "other-game")
	var wrong: Dictionary = wrong_service.consume(8, issued["ticket"], 1001)
	assert_eq(wrong["outcome"], SessionAssertionScript.REASON_WRONG_AUDIENCE)
	assert_false(wrong_sessions.is_authenticated(8))
	wrong_characters.free()


func test_invalidate_marks_ticket_as_replayed() -> void:
	_bind_nakama_account_with_character(1, "nakama-user-1", "NakamaHero")
	var issued: Dictionary = _tickets.issue(1, 1000, 60)
	_tickets.invalidate(issued["ticket"])
	var consumed: Dictionary = _tickets.consume(7, issued["ticket"], 1001)
	assert_eq(consumed["outcome"], WorldEntryTicketServiceScript.REASON_REPLAYED)
	assert_false(_sessions.is_authenticated(7))