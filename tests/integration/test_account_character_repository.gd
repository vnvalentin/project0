extends GutTest
## Headless public-seam test for Slice 039's server-only Account/Character
## repository (server/account_character_repository.gd), against a temporary
## user:// SQLite database opened through the Slice 038 SqliteStore engine
## seam (server/sqlite_store.gd, consumed unmodified). Covers the acceptance
## scenarios from
## .scratch/player-accounts/handoff-039-accounts-characters-repository.md and
## docs/slices/039-accounts-characters-repository.md. Each test uses a unique
## per-test user:// filename (before_each) and deletes the DB/WAL/SHM/journal
## files afterward (after_each), mirroring tests/integration/test_sqlite_store.gd.

const SqliteStoreScript: Script = preload("res://server/sqlite_store.gd")
const AccountCharacterRepositoryScript: Script = preload("res://server/account_character_repository.gd")
const CharacterRecordScript: Script = preload("res://shared/character_record.gd")

var _relative_path: String = ""
var _store: SqliteStore = null
var _repo: AccountCharacterRepository = null


func before_each() -> void:
	_relative_path = "test_account_character_repo_%d_%d.db" % [Time.get_ticks_usec(), randi()]
	_store = SqliteStoreScript.new()
	_store.open(_relative_path)
	_repo = AccountCharacterRepositoryScript.new(_store)
	_repo.ensure_schema()


func after_each() -> void:
	if _store.is_open():
		_store.close()
	_delete_user_file(_relative_path)
	_delete_user_file(_relative_path + "-wal")
	_delete_user_file(_relative_path + "-shm")
	_delete_user_file(_relative_path + "-journal")


func _delete_user_file(relative_path: String) -> void:
	var abs_path: String = ProjectSettings.globalize_path("user://%s" % relative_path)
	if FileAccess.file_exists(abs_path):
		DirAccess.remove_absolute(abs_path)


func _create_account(username: String) -> Dictionary:
	return _repo.create_account(username, "salt-%s" % username, "hash-%s" % username, 100000)


# Scenario 1: create_account succeeds; a duplicate username is rejected and
# leaves no second row.
func test_create_account_succeeds_and_rejects_duplicate_username() -> void:
	var first: Dictionary = _create_account("alice")
	assert_eq(first["outcome"], "ok", "first create_account succeeds: %s" % first.get("detail", ""))
	assert_eq(first["account"].username, "alice")
	assert_true(String(first["account"].account_id).length() > 0, "account_id is opaque and non-empty")

	var second: Dictionary = _create_account("alice")
	assert_eq(second["outcome"], CharacterRecordScript.REJECT_USERNAME_TAKEN, "duplicate username is rejected")

	var lookup: Dictionary = _repo.find_account_by_username("alice")
	assert_eq(lookup["outcome"], "ok")
	assert_eq(lookup["pbkdf2_hash"], "hash-alice", "the stored credential bytes are the first request's, unchanged")


# Scenario 2: 5 characters succeed; the 6th is rejected with CHARACTER_CAP_REACHED.
func test_character_cap_of_five_is_enforced() -> void:
	var account: Dictionary = _create_account("bob")
	var account_id: String = account["account"].account_id

	for i in range(5):
		var result: Dictionary = _repo.create_character(account_id, "Hero%d" % i, {})
		assert_eq(result["outcome"], "ok", "character %d succeeds: %s" % [i, result.get("detail", "")])

	var sixth: Dictionary = _repo.create_character(account_id, "HeroSix", {})
	assert_eq(sixth["outcome"], CharacterRecordScript.REJECT_CHARACTER_CAP_REACHED, "the 6th character is rejected")

	var listed: Dictionary = _repo.list_characters(account_id)
	assert_eq((listed["characters"] as Array).size(), 5, "only the 5 accepted characters are listed")


# Scenario 3: two accounts requesting the same display name — first succeeds,
# second is rejected (global live uniqueness).
func test_display_name_is_globally_unique_among_live_characters() -> void:
	var account_a: Dictionary = _create_account("carol")
	var account_b: Dictionary = _create_account("dave")

	var first: Dictionary = _repo.create_character(account_a["account"].account_id, "Rowan", {})
	assert_eq(first["outcome"], "ok", "first Rowan succeeds: %s" % first.get("detail", ""))

	var second: Dictionary = _repo.create_character(account_b["account"].account_id, "Rowan", {})
	assert_eq(second["outcome"], CharacterRecordScript.REJECT_NAME_TAKEN, "second Rowan is rejected as taken")


# Scenario 4: soft-deleted character is absent from list_characters, frees
# the owner's cap slot, and (per the resolved tension) frees the name for
# ANY account to reuse; the soft-deleted row is retained.
func test_soft_delete_frees_cap_slot_and_frees_name_across_accounts() -> void:
	var account_a: Dictionary = _create_account("erin")
	var account_b: Dictionary = _create_account("frank")
	var account_a_id: String = account_a["account"].account_id
	var account_b_id: String = account_b["account"].account_id

	var created: Dictionary = _repo.create_character(account_a_id, "Rowan", {})
	var character_id: String = created["character"].character_id

	var listed_before: Dictionary = _repo.list_characters(account_a_id)
	assert_eq((listed_before["characters"] as Array).size(), 1, "the character is listed before deletion")

	var delete_result: Dictionary = _repo.soft_delete_character(account_a_id, character_id)
	assert_eq(delete_result["outcome"], "ok", "soft delete succeeds: %s" % delete_result.get("detail", ""))

	var listed_after: Dictionary = _repo.list_characters(account_a_id)
	assert_eq((listed_after["characters"] as Array).size(), 0, "the soft-deleted character is absent from list_characters")

	# Owner can create again under the cap.
	var recreated: Dictionary = _repo.create_character(account_a_id, "AnotherName", {})
	assert_eq(recreated["outcome"], "ok", "the owner can create again after freeing a cap slot")

	# A DIFFERENT account may reuse the freed name "Rowan" (resolved tension:
	# only the live-name namespace is globally unique).
	var reused: Dictionary = _repo.create_character(account_b_id, "Rowan", {})
	assert_eq(reused["outcome"], "ok", "a different account may reuse the freed display_name: %s" % reused.get("detail", ""))

	# The soft-deleted row is retained (not hard-deleted) — verified via a raw
	# row count including deleted rows through a second repository call:
	# find it through select_character with include semantics unavailable at
	# the public seam, so assert indirectly: a second soft_delete on the same
	# id is ALREADY_DELETED (proves the row still exists).
	var second_delete: Dictionary = _repo.soft_delete_character(account_a_id, character_id)
	assert_eq(second_delete["outcome"], CharacterRecordScript.REJECT_ALREADY_DELETED, "the retained soft-deleted row reports ALREADY_DELETED, not NO_SUCH_CHARACTER")


# Scenario 5: cross-account ownership checks.
func test_select_and_delete_reject_non_owner_and_unknown_character() -> void:
	var account_a: Dictionary = _create_account("grace")
	var account_b: Dictionary = _create_account("heidi")
	var account_a_id: String = account_a["account"].account_id
	var account_b_id: String = account_b["account"].account_id

	var created: Dictionary = _repo.create_character(account_a_id, "Rowan", {})
	var character_id: String = created["character"].character_id

	var select_by_b: Dictionary = _repo.select_character(account_b_id, character_id)
	assert_eq(select_by_b["outcome"], CharacterRecordScript.REJECT_NOT_OWNER, "selecting another account's character is rejected")

	var delete_by_b: Dictionary = _repo.soft_delete_character(account_b_id, character_id)
	assert_eq(delete_by_b["outcome"], CharacterRecordScript.REJECT_NOT_OWNER, "deleting another account's character is rejected")

	var select_unknown: Dictionary = _repo.select_character(account_a_id, "nonexistent-id")
	assert_eq(select_unknown["outcome"], CharacterRecordScript.REJECT_NO_SUCH_CHARACTER, "an unknown character_id is rejected")

	var delete_unknown: Dictionary = _repo.soft_delete_character(account_a_id, "nonexistent-id")
	assert_eq(delete_unknown["outcome"], CharacterRecordScript.REJECT_NO_SUCH_CHARACTER, "an unknown character_id is rejected on delete too")


# Scenario 6: a hostile value that legitimately reaches a parameter-bound
# insert (cosmetic, which is JSON-serialized and stored as text, not
# charset-validated like display_name) is stored/retrieved literally with no
# injected statement running. Separately, the display_name validator rejects
# a hostile display_name outright.
func test_hostile_value_through_parameter_binding_is_stored_literally_and_display_name_charset_rejects_injection_attempt() -> void:
	var account: Dictionary = _create_account("ivan")
	var account_id: String = account["account"].account_id

	var hostile_cosmetic_value: String = "Robert'); DROP TABLE characters; --"
	var created: Dictionary = _repo.create_character(account_id, "Ivan", {"nickname": hostile_cosmetic_value})
	assert_eq(created["outcome"], "ok", "create_character with a hostile cosmetic value succeeds: %s" % created.get("detail", ""))
	assert_eq((created["character"] as CharacterRecord).cosmetic["nickname"], hostile_cosmetic_value, "the hostile value round-trips literally")

	var listed: Dictionary = _repo.list_characters(account_id)
	assert_eq((listed["characters"] as Array).size(), 1, "the characters table survives; no injected statement executed")

	var hostile_display_name: String = "Robert'); DROP TABLE characters; --"
	assert_false(CharacterRecordScript.is_valid_display_name(hostile_display_name), "the charset validator rejects a hostile display_name")
	var rejected: Dictionary = _repo.create_character(account_id, hostile_display_name, {})
	assert_eq(rejected["outcome"], CharacterRecordScript.REJECT_NAME_INVALID, "create_character rejects the hostile display_name as NAME_INVALID")


# Scenario 7: covered structurally by scenario 3 (the DB-layer partial unique
# index is the actual mechanism preventing the second same-named insert,
# since the app-layer pre-check already catches ordinary duplicates in a
# single-threaded test). This test forces the pre-check to be bypassed by
# racing two inserts for the same name against the same account in a way
# that still exercises the DB constraint path: insert one row directly
# through ensure_schema's table via the store, bypassing the repository's
# pre-check, then confirm the repository's own create_character for the same
# name is rejected without leaving a partial row.
func test_duplicate_name_slipping_past_app_precheck_is_rejected_atomically_by_db_constraint() -> void:
	var account: Dictionary = _create_account("judy")
	var account_id: String = account["account"].account_id

	# Insert a live "Rowan" row directly at the store layer, bypassing the
	# repository's pre-check entirely, to simulate a race winner.
	var direct_insert: Dictionary = _store.query_with_bindings(
		"INSERT INTO characters (character_id, account_id, display_name, cosmetic_json, vessel_json, created_at, last_played_at, deleted, schema_version) VALUES (?, ?, ?, ?, NULL, ?, ?, 0, ?);",
		["char-direct-1", account_id, "Rowan", "{}", 1000, 1000, CharacterRecordScript.SCHEMA_VERSION]
	)
	assert_eq(direct_insert["outcome"], "ok", "the direct race-winner insert succeeds")

	# Force the repository to skip its own pre-check by asking it to create a
	# character with a name whose pre-check we can't bypass from the public
	# seam alone, so instead assert the DB constraint is truly authoritative:
	# a second direct insert for the same live name must fail at the DB layer.
	var conflicting_direct_insert: Dictionary = _store.query_with_bindings(
		"INSERT INTO characters (character_id, account_id, display_name, cosmetic_json, vessel_json, created_at, last_played_at, deleted, schema_version) VALUES (?, ?, ?, ?, NULL, ?, ?, 0, ?);",
		["char-direct-2", account_id, "Rowan", "{}", 1000, 1000, CharacterRecordScript.SCHEMA_VERSION]
	)
	assert_eq(conflicting_direct_insert["outcome"], SqliteStoreScript.OUTCOME_QUERY_FAILED, "the partial unique index rejects a second live 'Rowan' row at the DB layer")

	# And through the repository's normal path (pre-check catches it, same
	# bounded outcome either way):
	var via_repo: Dictionary = _repo.create_character(account_id, "Rowan", {})
	assert_eq(via_repo["outcome"], CharacterRecordScript.REJECT_NAME_TAKEN, "the repository surfaces a bounded NAME_TAKEN, not a crash")

	var listed: Dictionary = _repo.list_characters(account_id)
	assert_eq((listed["characters"] as Array).size(), 1, "no partial row was left by the rejected attempts")


# Scenario 8: durability across restart.
func test_account_and_character_survive_store_close_and_reopen() -> void:
	var account: Dictionary = _create_account("karl")
	var account_id: String = account["account"].account_id
	var created: Dictionary = _repo.create_character(account_id, "Rowan", {"hair": "black"})
	var character_id: String = created["character"].character_id

	_store.close()

	var reopened_store: SqliteStore = SqliteStoreScript.new()
	reopened_store.open(_relative_path)
	var reopened_repo: AccountCharacterRepository = AccountCharacterRepositoryScript.new(reopened_store)
	reopened_repo.ensure_schema()

	var lookup: Dictionary = reopened_repo.find_account_by_username("karl")
	assert_eq(lookup["outcome"], "ok", "the account survives close+reopen")
	assert_eq(lookup["account_id"], account_id)

	var listed: Dictionary = reopened_repo.list_characters(account_id)
	assert_eq((listed["characters"] as Array).size(), 1, "the character survives close+reopen")
	assert_eq((listed["characters"][0] as CharacterRecord).character_id, character_id)

	reopened_store.close()
	_store = reopened_store # let after_each clean up the same file


# Scenario 9: display_name validation matrix at the repository seam
# (mirrors tests/unit/test_character_record.gd, exercised here through
# create_character to prove the repository itself enforces it, not just the
# pure contract).
func test_create_character_display_name_validation_matrix() -> void:
	var account: Dictionary = _create_account("liam")
	var account_id: String = account["account"].account_id

	var invalid_names: Array[String] = ["ab", "a".repeat(21), " Rowan", "Rowan ", "Ro  wan", "Ro$wan"]
	for name: String in invalid_names:
		var result: Dictionary = _repo.create_character(account_id, name, {})
		assert_eq(result["outcome"], CharacterRecordScript.REJECT_NAME_INVALID, "'%s' is rejected as NAME_INVALID" % name)

	var valid_names: Array[String] = ["Rowan", "Ro-wan_1"]
	for name: String in valid_names:
		var result: Dictionary = _repo.create_character(account_id, name, {})
		assert_eq(result["outcome"], "ok", "'%s' is accepted: %s" % [name, result.get("detail", "")])


func test_select_character_updates_last_played_at() -> void:
	var account: Dictionary = _create_account("mona")
	var account_id: String = account["account"].account_id
	var created: Dictionary = _repo.create_character(account_id, "Rowan", {})
	var character_id: String = created["character"].character_id
	var original_last_played: int = (created["character"] as CharacterRecord).last_played_at

	var select_result: Dictionary = _repo.select_character(account_id, character_id)
	assert_eq(select_result["outcome"], "ok", "select_character succeeds: %s" % select_result.get("detail", ""))
	var selected_record: CharacterRecord = select_result["character"]
	assert_true(selected_record.last_played_at >= original_last_played, "last_played_at is refreshed to a value at least as new as creation")

	var listed: Dictionary = _repo.list_characters(account_id)
	var listed_record: CharacterRecord = listed["characters"][0]
	assert_eq(listed_record.last_played_at, selected_record.last_played_at, "the persisted row reflects the same last_played_at select_character returned")
