extends GutTest
## Headless public-seam test for Slice 042's server-only Character CRUD
## dispatch (server/character_service.gd), exercised directly against a
## temporary user:// SQLite database through the Slice 038/039/040
## SqliteStore/AccountCharacterRepository/SessionRegistry seams (all consumed
## unmodified). Mirrors tests/integration/test_account_auth_session.gd's
## per-test temporary-database setup/teardown and its style of calling the
## service directly with a bare peer_id int, matching how
## server_main.gd's RPC dispatch would call it after resolving
## multiplayer.get_remote_sender_id(). Covers the acceptance scenarios from
## .scratch/player-accounts/handoff-042-character-crud-rpc.md.
##
## The authorization core under test throughout: the client/caller NEVER
## supplies an account_id; CharacterService derives it from the peer's
## SessionRegistry session, so a peer authenticated as one account can never
## list/select/delete a Character owned by a different account, even when it
## knows that other account's character_id.

const SqliteStoreScript: Script = preload("res://server/sqlite_store.gd")
const AccountCharacterRepositoryScript: Script = preload("res://server/account_character_repository.gd")
const SessionRegistryScript: Script = preload("res://server/session_registry.gd")
const CharacterServiceScript: Script = preload("res://server/character_service.gd")
const CharacterRecordScript: Script = preload("res://shared/character_record.gd")

var _relative_path: String = ""
var _store: SqliteStore = null
var _repo: AccountCharacterRepository = null
var _sessions: SessionRegistry = null
var _service: CharacterService = null


func before_each() -> void:
	_relative_path = "test_character_crud_rpc_%d_%d.db" % [Time.get_ticks_usec(), randi()]
	_store = SqliteStoreScript.new()
	_store.open(_relative_path)
	_repo = AccountCharacterRepositoryScript.new(_store)
	_repo.ensure_schema()
	_sessions = SessionRegistryScript.new()
	_service = CharacterServiceScript.new(_repo, _sessions)


func after_each() -> void:
	if _store.is_open():
		_store.close()
	if is_instance_valid(_service):
		_service.free()
	_delete_user_file(_relative_path)
	_delete_user_file(_relative_path + "-wal")
	_delete_user_file(_relative_path + "-shm")
	_delete_user_file(_relative_path + "-journal")


func _delete_user_file(relative_path: String) -> void:
	var abs_path: String = ProjectSettings.globalize_path("user://%s" % relative_path)
	if FileAccess.file_exists(abs_path):
		DirAccess.remove_absolute(abs_path)


## Creates a real account in the repository (CharacterService.create_character
## requires the account row to exist — characters.account_id is a NOT NULL
## foreign key) and binds an authenticated session for `peer_id` to its
## server-generated id, mirroring how AuthService binds a session after a
## real register/login. Returns the account_id so scenarios can assert on it.
func _bind_account(peer_id: int, username: String) -> String:
	var created: Dictionary = _repo.create_account(username, "salt-%s" % username, "hash-%s" % username, 100000)
	var account_id: String = created["account"].account_id
	_sessions.bind(peer_id, account_id, username)
	return account_id


# Scenario 1: unauthenticated peer -> NOT_AUTHENTICATED on every op, no side effect.
func test_unauthenticated_peer_is_rejected_on_every_operation_with_no_side_effect() -> void:
	var list_result: Dictionary = _service.list_characters(1)
	assert_eq(list_result["outcome"], "NOT_AUTHENTICATED")

	var create_result: Dictionary = _service.create_character(1, "Rowan", {})
	assert_eq(create_result["outcome"], "NOT_AUTHENTICATED")

	var select_result: Dictionary = _service.select_character(1, "some-character-id")
	assert_eq(select_result["outcome"], "NOT_AUTHENTICATED")

	var delete_result: Dictionary = _service.delete_character(1, "some-character-id")
	assert_eq(delete_result["outcome"], "NOT_AUTHENTICATED")

	# No side effect: nothing was persisted for any account.
	var lookup: Dictionary = _repo.list_characters("nonexistent-account")
	assert_eq(lookup["outcome"], "ok")
	assert_eq((lookup["characters"] as Array).size(), 0)


# Scenario 2: create persists under the session account; list returns exactly
# that account's live Characters.
func test_create_persists_under_session_account_and_list_returns_exactly_those() -> void:
	var account_a_id: String = _bind_account(1, "alice")

	var create_result: Dictionary = _service.create_character(1, "Rowan", {"hair": "brown"})
	assert_eq(create_result["outcome"], "ok", "create succeeds: %s" % create_result.get("detail", ""))
	var created: CharacterRecord = create_result["character"]
	assert_eq(created.account_id, account_a_id, "the server derived account_id from the session, not the client")

	var list_result: Dictionary = _service.list_characters(1)
	assert_eq(list_result["outcome"], "ok")
	var characters: Array = list_result["characters"]
	assert_eq(characters.size(), 1)
	assert_eq((characters[0] as CharacterRecord).character_id, created.character_id)


# Scenario 3 (authorization core): account A cannot select/delete account B's
# Character even when it knows B's character_id.
func test_account_scoping_prevents_cross_account_select_and_delete() -> void:
	_bind_account(1, "alice")
	_bind_account(2, "bob")

	var b_create: Dictionary = _service.create_character(2, "Bram", {})
	assert_eq(b_create["outcome"], "ok")
	var b_character_id: String = (b_create["character"] as CharacterRecord).character_id

	var a_select_b: Dictionary = _service.select_character(1, b_character_id)
	assert_true(
		a_select_b["outcome"] == CharacterRecordScript.REJECT_NOT_OWNER or a_select_b["outcome"] == CharacterRecordScript.REJECT_NO_SUCH_CHARACTER,
		"A cannot select B's character: got %s" % a_select_b["outcome"]
	)

	var a_delete_b: Dictionary = _service.delete_character(1, b_character_id)
	assert_true(
		a_delete_b["outcome"] == CharacterRecordScript.REJECT_NOT_OWNER or a_delete_b["outcome"] == CharacterRecordScript.REJECT_NO_SUCH_CHARACTER,
		"A cannot delete B's character: got %s" % a_delete_b["outcome"]
	)

	# B's character is untouched: still present and not deleted.
	var b_list: Dictionary = _service.list_characters(2)
	assert_eq((b_list["characters"] as Array).size(), 1, "B's character was not deleted by A's rejected attempt")


# Scenario 4: cap, name-taken, and name-invalid are all surfaced over the
# service seam.
func test_character_cap_name_taken_and_name_invalid_are_enforced() -> void:
	_bind_account(1, "alice")

	for i: int in range(CharacterRecordScript.MAX_CHARACTERS_PER_ACCOUNT):
		var result: Dictionary = _service.create_character(1, "Hero%d" % i, {})
		assert_eq(result["outcome"], "ok", "character %d should be within the cap" % i)

	var over_cap: Dictionary = _service.create_character(1, "OneTooMany", {})
	assert_eq(over_cap["outcome"], CharacterRecordScript.REJECT_CHARACTER_CAP_REACHED)

	_bind_account(2, "bob")
	var name_taken: Dictionary = _service.create_character(2, "Hero0", {})
	assert_eq(name_taken["outcome"], CharacterRecordScript.REJECT_NAME_TAKEN)

	var name_invalid: Dictionary = _service.create_character(2, "ab", {})
	assert_eq(name_invalid["outcome"], CharacterRecordScript.REJECT_NAME_INVALID)


# Scenario 5: select records selected_character_id on the session and
# refreshes last_played_at.
func test_select_records_selected_character_id_on_session_and_refreshes_last_played_at() -> void:
	_bind_account(1, "alice")
	var create_result: Dictionary = _service.create_character(1, "Rowan", {})
	var character: CharacterRecord = create_result["character"]
	var original_last_played_at: int = character.last_played_at

	# Deterministically wait until the whole-second clock advances past the
	# creation time so the refreshed last_played_at is reliably newer. A fixed
	# real-time timer intermittently under-waits in headless GUT, leaving both
	# timestamps in the same integer second (a flaky assert_gt).
	while (Time.get_unix_time_from_system() as int) <= original_last_played_at:
		await get_tree().process_frame

	var select_result: Dictionary = _service.select_character(1, character.character_id)
	assert_eq(select_result["outcome"], "ok", "select succeeds: %s" % select_result.get("detail", ""))
	var selected: CharacterRecord = select_result["character"]
	assert_eq(selected.character_id, character.character_id)
	assert_gt(selected.last_played_at, original_last_played_at, "last_played_at was refreshed")

	assert_eq(_sessions.get_session(1).get("selected_character_id", ""), character.character_id, "the session records the selection")
	assert_eq(_sessions.get_selected_character(1), character.character_id)


# CharacterRecord.to_wire_dict() round-trip covered in tests/unit/test_character_record.gd
# (scenario 6). Here we confirm the service returns real CharacterRecord
# instances whose to_wire_dict() output matches what server_main.gd's
# character_result RPC would send.
func test_created_character_serializes_to_a_client_safe_wire_dict() -> void:
	var account_a_id: String = _bind_account(1, "alice")
	var create_result: Dictionary = _service.create_character(1, "Rowan", {"hair": "brown"})
	var character: CharacterRecord = create_result["character"]
	var wire: Dictionary = character.to_wire_dict()
	assert_eq(wire["character_id"], character.character_id)
	assert_eq(wire["account_id"], account_a_id)
	assert_eq(wire["display_name"], "Rowan")
	assert_false(wire.has("pbkdf2_hash"), "wire dict never carries credential material")
	assert_false(wire.has("pbkdf2_salt"), "wire dict never carries credential material")


func test_delete_soft_deletes_owned_character_and_rejects_already_deleted() -> void:
	_bind_account(1, "alice")
	var create_result: Dictionary = _service.create_character(1, "Rowan", {})
	var character_id: String = (create_result["character"] as CharacterRecord).character_id

	var delete_result: Dictionary = _service.delete_character(1, character_id)
	assert_eq(delete_result["outcome"], "ok", "delete succeeds: %s" % delete_result.get("detail", ""))

	var list_result: Dictionary = _service.list_characters(1)
	assert_eq((list_result["characters"] as Array).size(), 0, "a soft-deleted character no longer appears in list")

	var second_delete: Dictionary = _service.delete_character(1, character_id)
	assert_eq(second_delete["outcome"], CharacterRecordScript.REJECT_ALREADY_DELETED)


func test_select_and_delete_unknown_character_id_reports_no_such_character() -> void:
	_bind_account(1, "alice")

	var select_result: Dictionary = _service.select_character(1, "does-not-exist")
	assert_eq(select_result["outcome"], CharacterRecordScript.REJECT_NO_SUCH_CHARACTER)

	var delete_result: Dictionary = _service.delete_character(1, "does-not-exist")
	assert_eq(delete_result["outcome"], CharacterRecordScript.REJECT_NO_SUCH_CHARACTER)


# Slice 043 world entry: get_selected_character requires an authenticated
# session AND a prior selection, then returns the selected CharacterRecord.
func test_get_selected_character_requires_auth_and_a_selection() -> void:
	var unauth: Dictionary = _service.get_selected_character(1)
	assert_eq(unauth["outcome"], "NOT_AUTHENTICATED", "unauthenticated peer cannot enter the world")

	_bind_account(1, "alice")
	var no_selection: Dictionary = _service.get_selected_character(1)
	assert_eq(no_selection["outcome"], "NO_CHARACTER_SELECTED", "an authenticated peer with no selection cannot enter the world")

	var created: Dictionary = _service.create_character(1, "Rowan", {"hair": "brown"})
	var character_id: String = (created["character"] as CharacterRecord).character_id
	_service.select_character(1, character_id)

	var selected: Dictionary = _service.get_selected_character(1)
	assert_eq(selected["outcome"], "ok", "a selected Character resolves for world entry: %s" % selected.get("detail", ""))
	assert_eq((selected["character"] as CharacterRecord).character_id, character_id)
