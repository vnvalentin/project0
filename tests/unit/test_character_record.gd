extends GutTest
## Public-seam unit tests for Slice 039's pure Account/Character value
## contracts (shared/character_record.gd, shared/account_handle.gd). Covers
## the display_name validation acceptance scenarios from
## .scratch/player-accounts/handoff-039-accounts-characters-repository.md
## (scenario 9) and the basic contract shape. Pure and stateless — no DB, no
## repository involved.

const CharacterRecordScript: Script = preload("res://shared/character_record.gd")
const AccountHandleScript: Script = preload("res://shared/account_handle.gd")


func test_display_name_accepts_valid_names() -> void:
	assert_true(CharacterRecordScript.is_valid_display_name("Rowan"), "a simple alphabetic name is accepted")
	assert_true(CharacterRecordScript.is_valid_display_name("Ro-wan_1"), "hyphen/underscore/digit charset is accepted")


func test_display_name_rejects_too_short() -> void:
	assert_false(CharacterRecordScript.is_valid_display_name("ab"), "a 2-character name is below the minimum")


func test_display_name_rejects_too_long() -> void:
	var too_long: String = "a".repeat(21)
	assert_false(CharacterRecordScript.is_valid_display_name(too_long), "a 21-character name exceeds the maximum")


func test_display_name_rejects_leading_space() -> void:
	assert_false(CharacterRecordScript.is_valid_display_name(" Rowan"), "a leading space is rejected")


func test_display_name_rejects_trailing_space() -> void:
	assert_false(CharacterRecordScript.is_valid_display_name("Rowan "), "a trailing space is rejected")


func test_display_name_rejects_double_space() -> void:
	assert_false(CharacterRecordScript.is_valid_display_name("Ro  wan"), "a double interior space is rejected")


func test_display_name_rejects_disallowed_charset() -> void:
	assert_false(CharacterRecordScript.is_valid_display_name("Ro$wan"), "a disallowed character is rejected")


func test_display_name_rejects_non_string() -> void:
	assert_false(CharacterRecordScript.is_valid_display_name(12345), "a non-String value is rejected fail-closed")


func test_character_record_holds_fields_without_phase_12_vessel_values() -> void:
	var record: CharacterRecord = CharacterRecordScript.new(
		"char-1", "acct-1", "Rowan", {"hair": "brown"}, 1000, 1000, false, null
	)
	assert_eq(record.schema_version, CharacterRecordScript.SCHEMA_VERSION, "schema_version is stamped")
	assert_eq(record.character_id, "char-1")
	assert_eq(record.account_id, "acct-1")
	assert_eq(record.display_name, "Rowan")
	assert_eq(record.cosmetic, {"hair": "brown"})
	assert_eq(record.created_at, 1000)
	assert_eq(record.last_played_at, 1000)
	assert_false(record.deleted, "a freshly constructed record is not deleted")
	assert_null(record.vessel_seam, "vessel_seam carries no Phase 12 values yet")


func test_account_handle_never_carries_credential_material() -> void:
	var handle: AccountHandle = AccountHandleScript.new("acct-1", "alice")
	assert_eq(handle.account_id, "acct-1")
	assert_eq(handle.username, "alice")
	assert_eq(handle.schema_version, AccountHandleScript.SCHEMA_VERSION, "schema_version is stamped")

	var property_names: Array = []
	for property: Dictionary in handle.get_property_list():
		property_names.append(property["name"])
	assert_false(property_names.has("pbkdf2_hash"), "AccountHandle declares no credential field at all")
	assert_false(property_names.has("pbkdf2_salt"), "AccountHandle declares no credential field at all")
