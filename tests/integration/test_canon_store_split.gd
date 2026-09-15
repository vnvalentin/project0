extends GutTest
## Slice 079: proves the opt-in dedicated Canon store isolates Canon from the
## accounts store (the wiring server_main selects when PROJECT0_CANON_DB_PATH is
## set), and that the shared-store default still colocates both. See
## docs/slices/079-optional-dedicated-canon-store.md.

const SqliteStoreScript: Script = preload("res://server/sqlite_store.gd")
const CanonRepositoryScript: Script = preload("res://server/canon_repository.gd")
const AccountRepositoryScript: Script = preload("res://server/account_character_repository.gd")
const FixturesScript: Script = preload("res://scripts/sector_blueprint_fixtures.gd")

var _accounts_path: String = ""
var _canon_path: String = ""
var _accounts_store: SqliteStore = null
var _canon_store: SqliteStore = null


func before_each() -> void:
	var stamp: String = "%d_%d" % [Time.get_ticks_usec(), randi()]
	_accounts_path = "test_split_accounts_%s.db" % stamp
	_canon_path = "test_split_canon_%s.db" % stamp
	_accounts_store = SqliteStoreScript.new()
	_accounts_store.open(_accounts_path)
	_canon_store = SqliteStoreScript.new()
	_canon_store.open(_canon_path)


func after_each() -> void:
	for store: SqliteStore in [_accounts_store, _canon_store]:
		if store != null and store.is_open():
			store.close()
	for relative: String in [_accounts_path, _canon_path]:
		for suffix: String in ["", "-wal", "-shm", "-journal"]:
			var path: String = ProjectSettings.globalize_path("user://%s%s" % [relative, suffix])
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)


func _blueprint() -> Dictionary:
	return JSON.parse_string(FixturesScript.VALID)


func test_dedicated_canon_store_isolates_canon_from_accounts() -> void:
	# server_main wiring when PROJECT0_CANON_DB_PATH is set: accounts on one
	# store, Canon on a separate store.
	var accounts: AccountCharacterRepository = AccountRepositoryScript.new(_accounts_store)
	assert_eq(accounts.ensure_schema()["outcome"], AccountRepositoryScript.OUTCOME_OK)
	var canon: CanonRepository = CanonRepositoryScript.new(_canon_store)
	assert_eq(canon.ensure_schema()["outcome"], CanonRepositoryScript.OUTCOME_OK)

	var blueprint: Dictionary = _blueprint()
	assert_eq(canon.canonicalize_blueprint(blueprint)["outcome"], CanonRepositoryScript.OUTCOME_OK)
	assert_eq(accounts.create_account("alice", "salt", "hash", 1000)["outcome"], AccountRepositoryScript.OUTCOME_OK)

	# The sector lives only in the canon store, never in the accounts store.
	assert_eq(canon.get_canonical_sector(blueprint["sector_id"])["outcome"], CanonRepositoryScript.OUTCOME_OK)
	var canon_on_accounts: CanonRepository = CanonRepositoryScript.new(_accounts_store)
	assert_eq(canon_on_accounts.ensure_schema()["outcome"], CanonRepositoryScript.OUTCOME_OK)
	assert_eq(canon_on_accounts.get_canonical_sector(blueprint["sector_id"])["outcome"], CanonRepositoryScript.OUTCOME_NOT_FOUND, "Canon must not leak into the accounts store")

	# The account lives only in the accounts store, never in the canon store.
	assert_eq(accounts.find_account_by_username("alice")["outcome"], AccountRepositoryScript.OUTCOME_OK)
	var accounts_on_canon: AccountCharacterRepository = AccountRepositoryScript.new(_canon_store)
	assert_eq(accounts_on_canon.ensure_schema()["outcome"], AccountRepositoryScript.OUTCOME_OK)
	assert_ne(accounts_on_canon.find_account_by_username("alice")["outcome"], AccountRepositoryScript.OUTCOME_OK, "accounts must not leak into the canon store")


func test_shared_store_default_colocates_canon_and_accounts() -> void:
	# server_main wiring when PROJECT0_CANON_DB_PATH is unset: one shared handle.
	var accounts: AccountCharacterRepository = AccountRepositoryScript.new(_accounts_store)
	assert_eq(accounts.ensure_schema()["outcome"], AccountRepositoryScript.OUTCOME_OK)
	var canon: CanonRepository = CanonRepositoryScript.new(_accounts_store)
	assert_eq(canon.ensure_schema()["outcome"], CanonRepositoryScript.OUTCOME_OK)

	var blueprint: Dictionary = _blueprint()
	assert_eq(canon.canonicalize_blueprint(blueprint)["outcome"], CanonRepositoryScript.OUTCOME_OK)
	assert_eq(accounts.create_account("bob", "salt", "hash", 1000)["outcome"], AccountRepositoryScript.OUTCOME_OK)

	# Both records are reachable through the single shared handle (the default).
	assert_eq(canon.get_canonical_sector(blueprint["sector_id"])["outcome"], CanonRepositoryScript.OUTCOME_OK)
	assert_eq(accounts.find_account_by_username("bob")["outcome"], AccountRepositoryScript.OUTCOME_OK)
