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


func test_wire_round_trip_preserves_all_fields_including_cosmetic() -> void:
	var record: CharacterRecord = CharacterRecordScript.new(
		"char-1", "acct-1", "Rowan", {"hair": "brown", "shirt": "blue"}, 1000, 2000, false, null
	)
	var wire: Dictionary = record.to_wire_dict()
	var restored: CharacterRecord = CharacterRecordScript.from_wire_dict(wire)
	assert_not_null(restored, "a well-formed wire dict round-trips")
	assert_eq(restored.schema_version, record.schema_version)
	assert_eq(restored.character_id, record.character_id)
	assert_eq(restored.account_id, record.account_id)
	assert_eq(restored.display_name, record.display_name)
	assert_eq(restored.cosmetic, record.cosmetic)
	assert_eq(restored.created_at, record.created_at)
	assert_eq(restored.last_played_at, record.last_played_at)
	assert_eq(restored.deleted, record.deleted)
	assert_null(restored.vessel_seam, "a null vessel_seam round-trips as null")


func test_wire_round_trip_preserves_deleted_true_and_null_vessel_seam() -> void:
	var record: CharacterRecord = CharacterRecordScript.new(
		"char-2", "acct-2", "Aldric", {}, 500, 900, true, null
	)
	var restored: CharacterRecord = CharacterRecordScript.from_wire_dict(record.to_wire_dict())
	assert_not_null(restored)
	assert_true(restored.deleted, "deleted=true round-trips")
	assert_null(restored.vessel_seam, "vessel_seam has no Phase 12 values yet")


func test_wire_dict_carries_no_extra_credential_or_db_fields() -> void:
	var record: CharacterRecord = CharacterRecordScript.new(
		"char-3", "acct-3", "Bram", {"hat": "red"}, 1, 2, false, null
	)
	var wire: Dictionary = record.to_wire_dict()
	var expected_keys: Array = [
		"schema_version", "character_id", "account_id", "display_name",
		"cosmetic", "created_at", "last_played_at", "deleted", "vessel_seam",
	]
	for key: String in wire.keys():
		assert_true(expected_keys.has(key), "wire dict has no unexpected key '%s'" % key)
	for key: String in expected_keys:
		assert_true(wire.has(key), "wire dict includes expected key '%s'" % key)


func test_from_wire_dict_rejects_missing_required_field() -> void:
	var record: CharacterRecord = CharacterRecordScript.new(
		"char-4", "acct-4", "Cara", {}, 1, 2, false, null
	)
	var wire: Dictionary = record.to_wire_dict()
	wire.erase("display_name")
	assert_null(CharacterRecordScript.from_wire_dict(wire), "a wire dict missing a required field is rejected fail-closed")


func test_from_wire_dict_rejects_wrong_types() -> void:
	var record: CharacterRecord = CharacterRecordScript.new(
		"char-5", "acct-5", "Devin", {}, 1, 2, false, null
	)
	var wire: Dictionary = record.to_wire_dict()
	wire["created_at"] = "not-a-number"
	assert_null(CharacterRecordScript.from_wire_dict(wire), "a wrong-typed field is rejected fail-closed")


func test_from_wire_dict_rejects_unsupported_schema_version() -> void:
	var record: CharacterRecord = CharacterRecordScript.new(
		"char-6", "acct-6", "Elara", {}, 1, 2, false, null
	)
	var wire: Dictionary = record.to_wire_dict()
	wire["schema_version"] = 999
	assert_null(CharacterRecordScript.from_wire_dict(wire), "an unsupported schema_version is rejected fail-closed")


func test_from_wire_dict_rejects_non_dictionary() -> void:
	assert_null(CharacterRecordScript.from_wire_dict("not-a-dict"), "a non-Dictionary input is rejected fail-closed")
	assert_null(CharacterRecordScript.from_wire_dict(null), "null input is rejected fail-closed")


func test_from_wire_dict_rejects_non_dictionary_cosmetic() -> void:
	var record: CharacterRecord = CharacterRecordScript.new(
		"char-7", "acct-7", "Finn", {}, 1, 2, false, null
	)
	var wire: Dictionary = record.to_wire_dict()
	wire["cosmetic"] = "not-a-dict"
	assert_null(CharacterRecordScript.from_wire_dict(wire), "a non-Dictionary cosmetic is rejected fail-closed")


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
