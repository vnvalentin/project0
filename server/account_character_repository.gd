extends RefCounted
class_name AccountCharacterRepository
## Slice 039: server-only Account/Character data-access repository, wrapping
## a SqliteStore (Slice 038, server/sqlite_store.gd, CONSUMED and never
## modified). Per CLAUDE.md's Shared Contracts / Runtime Ownership rules,
## `shared/` and `client/` never reference this class or hold a DB handle.
##
## Scope: atomic, parameter-bound, fail-closed CRUD for the `accounts` and
## `characters` tables only. No RPC, no PBKDF2 hashing/verification (this
## repository stores and returns the credential bytes it is given and never
## computes or compares them), no session objects, no Character->Player
## instantiation. See docs/slices/039-accounts-characters-repository.md.
##
## Name-uniqueness reconciliation (ticket 06 vs. ticket 05 tension, resolved
## per the Slice 039 handoff): the partial unique index on
## `characters.display_name WHERE deleted = 0` is authoritative. A
## soft-deleted Character's name is retained in the row (history) but does
## NOT lock the name against other Accounts — only LIVE names are globally
## unique. This is a deliberate deviation from ticket 05's prose ("name stays
## reserved to the Account"), documented in the slice record.
##
## Every public method returns a bounded, structured result Dictionary and
## never raises, matching SqliteStore's fail-closed contract style.

const CharacterRecordScript: Script = preload("res://shared/character_record.gd")
const AccountHandleScript: Script = preload("res://shared/account_handle.gd")

const OUTCOME_OK: String = "ok"
const NAKAMA_ACCOUNT_USERNAME_PREFIX: String = "nakama:"
const NAKAMA_CREDENTIAL_SENTINEL_SALT: String = "00000000000000000000000000000000"
const NAKAMA_CREDENTIAL_SENTINEL_HASH: String = "0000000000000000000000000000000000000000000000000000000000000000"
const NAKAMA_CREDENTIAL_SENTINEL_ITERATIONS: int = 1

var _store: SqliteStore = null
var _id_sequence: int = 0


func _init(store: SqliteStore) -> void:
	_store = store


## Public seam. Idempotent `CREATE TABLE IF NOT EXISTS` for the domain schema
## plus the required indexes. Must be called once after the wrapped
## SqliteStore is open, before any other method is used.
func ensure_schema() -> Dictionary:
	if not _store.is_open():
		return _result(SqliteStore.OUTCOME_NOT_OPEN, "Store is not open.")

	var statements: Array[String] = [
		"""
		CREATE TABLE IF NOT EXISTS accounts (
			account_id TEXT PRIMARY KEY,
			username TEXT UNIQUE NOT NULL,
			pbkdf2_salt TEXT NOT NULL,
			pbkdf2_hash TEXT NOT NULL,
			pbkdf2_iterations INTEGER NOT NULL,
			created_at INTEGER NOT NULL,
			schema_version INTEGER NOT NULL
		);
		""",
		"""
		CREATE TABLE IF NOT EXISTS characters (
			character_id TEXT PRIMARY KEY,
			account_id TEXT NOT NULL REFERENCES accounts(account_id),
			display_name TEXT NOT NULL,
			cosmetic_json TEXT NOT NULL,
			vessel_json TEXT NULL,
			created_at INTEGER NOT NULL,
			last_played_at INTEGER NOT NULL,
			deleted INTEGER NOT NULL DEFAULT 0,
			schema_version INTEGER NOT NULL
		);
		""",
		"""
		CREATE UNIQUE INDEX IF NOT EXISTS idx_characters_display_name_live
		ON characters (display_name) WHERE deleted = 0;
		""",
		"CREATE INDEX IF NOT EXISTS idx_characters_account_id ON characters (account_id);",
	]

	for statement: String in statements:
		var result: Dictionary = _store.query(statement)
		if result["outcome"] != SqliteStore.OUTCOME_OK:
			return _result(SqliteStore.OUTCOME_QUERY_FAILED, "ensure_schema failed: %s" % result["detail"])

	return _result(OUTCOME_OK, "Schema ready.")


## Public seam. Creates a new Account. Stores the credential bytes it is
## given verbatim; never computes or verifies PBKDF2 itself (that is a later
## slice's job). Returns:
##   { "outcome": OUTCOME_OK, "account": AccountHandle }
##   { "outcome": CharacterRecord.REJECT_MALFORMED, "detail": String }
##   { "outcome": CharacterRecord.REJECT_USERNAME_TAKEN, "detail": String }
func create_account(username: Variant, pbkdf2_salt: Variant, pbkdf2_hash: Variant, pbkdf2_iterations: Variant) -> Dictionary:
	if not _store.is_open():
		return _result(SqliteStore.OUTCOME_NOT_OPEN, "Store is not open.")
	if not (username is String) or (username as String).is_empty():
		return _result(CharacterRecordScript.REJECT_MALFORMED, "username must be a non-empty string.")
	if not (pbkdf2_salt is String) or (pbkdf2_salt as String).is_empty():
		return _result(CharacterRecordScript.REJECT_MALFORMED, "pbkdf2_salt must be a non-empty string.")
	if not (pbkdf2_hash is String) or (pbkdf2_hash as String).is_empty():
		return _result(CharacterRecordScript.REJECT_MALFORMED, "pbkdf2_hash must be a non-empty string.")
	if not (pbkdf2_iterations is int) or (pbkdf2_iterations as int) <= 0:
		return _result(CharacterRecordScript.REJECT_MALFORMED, "pbkdf2_iterations must be a positive integer.")

	var existing: Dictionary = find_account_by_username(username)
	if existing["outcome"] == OUTCOME_OK:
		return _result(CharacterRecordScript.REJECT_USERNAME_TAKEN, "Username '%s' is already taken." % username)

	var account_id: String = _generate_id("account")
	var created_at: int = _now()

	var txn_result: Dictionary = _store.transaction(func() -> bool:
		var insert: Dictionary = _store.query_with_bindings(
			"INSERT INTO accounts (account_id, username, pbkdf2_salt, pbkdf2_hash, pbkdf2_iterations, created_at, schema_version) VALUES (?, ?, ?, ?, ?, ?, ?);",
			[account_id, username, pbkdf2_salt, pbkdf2_hash, pbkdf2_iterations, created_at, CharacterRecordScript.SCHEMA_VERSION]
		)
		return insert["outcome"] == SqliteStore.OUTCOME_OK
	)

	if txn_result["outcome"] != SqliteStore.OUTCOME_OK:
		# Defense in depth: a race that slipped past the pre-check above hits
		# the UNIQUE constraint on accounts.username inside the transaction.
		# Surface it as the same bounded USERNAME_TAKEN reason, not a crash.
		return _result(CharacterRecordScript.REJECT_USERNAME_TAKEN, "Username '%s' is already taken (constraint)." % username)

	return {
		"outcome": OUTCOME_OK,
		"account": AccountHandleScript.new(account_id, username),
	}


## Public seam. Server-only lookup of the stored credential row for the later
## auth slice to verify. NEVER a client DTO — includes salt/hash/iterations.
## Returns:
##   { "outcome": OUTCOME_OK, "account_id", "username", "pbkdf2_salt", "pbkdf2_hash", "pbkdf2_iterations" }
##   { "outcome": CharacterRecord.REJECT_MALFORMED, "detail": String }
##   { "outcome": "NO_SUCH_ACCOUNT", "detail": String }
func find_account_by_username(username: Variant) -> Dictionary:
	if not _store.is_open():
		return _result(SqliteStore.OUTCOME_NOT_OPEN, "Store is not open.")
	if not (username is String) or (username as String).is_empty():
		return _result(CharacterRecordScript.REJECT_MALFORMED, "username must be a non-empty string.")

	var select_result: Dictionary = _store.query_with_bindings(
		"SELECT account_id, username, pbkdf2_salt, pbkdf2_hash, pbkdf2_iterations FROM accounts WHERE username = ?;",
		[username]
	)
	if select_result["outcome"] != SqliteStore.OUTCOME_OK:
		return _result(SqliteStore.OUTCOME_QUERY_FAILED, select_result["detail"])
	var rows: Array = select_result["rows"]
	if rows.is_empty():
		return _result("NO_SUCH_ACCOUNT", "No account with username '%s'." % username)

	var row: Dictionary = rows[0]
	return {
		"outcome": OUTCOME_OK,
		"account_id": row["account_id"],
		"username": row["username"],
		"pbkdf2_salt": row["pbkdf2_salt"],
		"pbkdf2_hash": row["pbkdf2_hash"],
		"pbkdf2_iterations": int(row["pbkdf2_iterations"]),
	}


## Public seam (Slice 168). Materializes a Project0 Account row for a Nakama
## user id without making Project0 the password authority. The account_id is the
## Nakama user id; username is an internal deterministic storage key; PBKDF2
## fields are sentinel values that cannot satisfy Project0 password login.
## Idempotent: calling it repeatedly for the same Nakama user returns the same
## AccountHandle and does not create duplicate rows.
func ensure_nakama_account(nakama_user_id: Variant, username: Variant = "") -> Dictionary:
	if not _store.is_open():
		return _result(SqliteStore.OUTCOME_NOT_OPEN, "Store is not open.")
	if not (nakama_user_id is String) or (nakama_user_id as String).strip_edges().is_empty():
		return _result(CharacterRecordScript.REJECT_MALFORMED, "nakama_user_id must be a non-empty string.")
	if not (username is String):
		return _result(CharacterRecordScript.REJECT_MALFORMED, "username must be a string.")

	var account_id: String = (nakama_user_id as String).strip_edges()
	var existing: Dictionary = _find_account_by_id(account_id)
	if existing["outcome"] == OUTCOME_OK:
		return {"outcome": OUTCOME_OK, "account": AccountHandleScript.new(existing["account_id"], existing["username"])}

	var storage_username: String = "%s%s" % [NAKAMA_ACCOUNT_USERNAME_PREFIX, account_id]
	var created_at: int = _now()
	var txn_result: Dictionary = _store.transaction(func() -> bool:
		var insert: Dictionary = _store.query_with_bindings(
			"INSERT INTO accounts (account_id, username, pbkdf2_salt, pbkdf2_hash, pbkdf2_iterations, created_at, schema_version) VALUES (?, ?, ?, ?, ?, ?, ?);",
			[account_id, storage_username, NAKAMA_CREDENTIAL_SENTINEL_SALT, NAKAMA_CREDENTIAL_SENTINEL_HASH, NAKAMA_CREDENTIAL_SENTINEL_ITERATIONS, created_at, CharacterRecordScript.SCHEMA_VERSION]
		)
		return insert["outcome"] == SqliteStore.OUTCOME_OK
	)

	if txn_result["outcome"] != SqliteStore.OUTCOME_OK:
		return _result(SqliteStore.OUTCOME_TRANSACTION_FAILED, txn_result.get("detail", "Failed to materialize Nakama account."))

	return {"outcome": OUTCOME_OK, "account": AccountHandleScript.new(account_id, storage_username)}


## Public seam. Creates a Character under `account_id`. Validates the
## display_name (length/charset), the account exists, the 5-cap, and global
## live-name uniqueness (app-layer pre-check + DB partial-unique-index
## defense in depth). Returns:
##   { "outcome": OUTCOME_OK, "character": CharacterRecord }
##   { "outcome": CharacterRecord.REJECT_NAME_INVALID, "detail": String }
##   { "outcome": CharacterRecord.REJECT_NAME_TAKEN, "detail": String }
##   { "outcome": CharacterRecord.REJECT_CHARACTER_CAP_REACHED, "detail": String }
##   { "outcome": "NO_SUCH_ACCOUNT", "detail": String }
func create_character(account_id: Variant, display_name: Variant, cosmetic: Variant) -> Dictionary:
	if not _store.is_open():
		return _result(SqliteStore.OUTCOME_NOT_OPEN, "Store is not open.")
	if not (account_id is String) or (account_id as String).is_empty():
		return _result(CharacterRecordScript.REJECT_MALFORMED, "account_id must be a non-empty string.")
	if not CharacterRecordScript.is_valid_display_name(display_name):
		return _result(CharacterRecordScript.REJECT_NAME_INVALID, "display_name '%s' is not valid." % [display_name])
	var cosmetic_dict: Dictionary = cosmetic if cosmetic is Dictionary else {}

	if not _account_exists(account_id):
		return _result("NO_SUCH_ACCOUNT", "No account with account_id '%s'." % account_id)

	var live_count: int = _count_live_characters(account_id)
	if live_count >= CharacterRecordScript.MAX_CHARACTERS_PER_ACCOUNT:
		return _result(CharacterRecordScript.REJECT_CHARACTER_CAP_REACHED, "Account '%s' already owns the maximum of %d Characters." % [account_id, CharacterRecordScript.MAX_CHARACTERS_PER_ACCOUNT])

	if _live_name_exists(display_name):
		return _result(CharacterRecordScript.REJECT_NAME_TAKEN, "display_name '%s' is already in use." % display_name)

	var character_id: String = _generate_id("character")
	var now: int = _now()
	var cosmetic_json: String = JSON.stringify(cosmetic_dict)

	var txn_result: Dictionary = _store.transaction(func() -> bool:
		var insert: Dictionary = _store.query_with_bindings(
			"INSERT INTO characters (character_id, account_id, display_name, cosmetic_json, vessel_json, created_at, last_played_at, deleted, schema_version) VALUES (?, ?, ?, ?, NULL, ?, ?, 0, ?);",
			[character_id, account_id, display_name, cosmetic_json, now, now, CharacterRecordScript.SCHEMA_VERSION]
		)
		return insert["outcome"] == SqliteStore.OUTCOME_OK
	)

	if txn_result["outcome"] != SqliteStore.OUTCOME_OK:
		# Defense in depth: a duplicate display_name that slipped past the
		# app-layer pre-check above (a race) hits the partial unique index
		# inside the transaction. Surface it as the same bounded NAME_TAKEN
		# reason, not a crash; no partial row is left (atomic rollback).
		return _result(CharacterRecordScript.REJECT_NAME_TAKEN, "display_name '%s' is already in use (constraint)." % display_name)

	return {
		"outcome": OUTCOME_OK,
		"character": CharacterRecordScript.new(character_id, account_id, display_name, cosmetic_dict, now, now, false, null),
	}


## Public seam. Lists the non-deleted Characters owned by `account_id` as
## client-safe DTOs (CharacterRecord instances).
## Returns { "outcome": OUTCOME_OK, "characters": CharacterRecord[] }.
func list_characters(account_id: Variant) -> Dictionary:
	if not _store.is_open():
		return _result(SqliteStore.OUTCOME_NOT_OPEN, "Store is not open.")
	if not (account_id is String) or (account_id as String).is_empty():
		return _result(CharacterRecordScript.REJECT_MALFORMED, "account_id must be a non-empty string.")

	var select_result: Dictionary = _store.query_with_bindings(
		"SELECT character_id, account_id, display_name, cosmetic_json, created_at, last_played_at FROM characters WHERE account_id = ? AND deleted = 0 ORDER BY created_at ASC;",
		[account_id]
	)
	if select_result["outcome"] != SqliteStore.OUTCOME_OK:
		return _result(SqliteStore.OUTCOME_QUERY_FAILED, select_result["detail"])

	var characters: Array[CharacterRecord] = []
	for row: Dictionary in select_result["rows"]:
		characters.append(_row_to_character_record(row, false))

	return {
		"outcome": OUTCOME_OK,
		"characters": characters,
	}


## Public seam. Data operation only — session binding + world entry are later
## slices. Validates ownership, then sets `last_played_at` to now. Returns:
##   { "outcome": OUTCOME_OK, "character": CharacterRecord }
##   { "outcome": CharacterRecord.REJECT_NOT_OWNER, "detail": String }
##   { "outcome": CharacterRecord.REJECT_NO_SUCH_CHARACTER, "detail": String }
func select_character(account_id: Variant, character_id: Variant) -> Dictionary:
	var lookup: Dictionary = _find_owned_character(account_id, character_id)
	if lookup["outcome"] != OUTCOME_OK:
		return lookup

	var now: int = _now()
	var txn_result: Dictionary = _store.transaction(func() -> bool:
		var update: Dictionary = _store.query_with_bindings(
			"UPDATE characters SET last_played_at = ? WHERE character_id = ?;",
			[now, character_id]
		)
		return update["outcome"] == SqliteStore.OUTCOME_OK
	)
	if txn_result["outcome"] != SqliteStore.OUTCOME_OK:
		return _result(SqliteStore.OUTCOME_TRANSACTION_FAILED, txn_result["detail"])

	var record: CharacterRecord = lookup["character"]
	record.last_played_at = now
	return {
		"outcome": OUTCOME_OK,
		"character": record,
	}


## Public seam. Soft-deletes a Character owned by `account_id` (sets
## `deleted = 1`; row is retained). Per the resolved name-reservation
## tension, this frees the display_name for reuse by any Account (only the
## partial unique index on live rows is authoritative). Returns:
##   { "outcome": OUTCOME_OK }
##   { "outcome": CharacterRecord.REJECT_NOT_OWNER, "detail": String }
##   { "outcome": CharacterRecord.REJECT_NO_SUCH_CHARACTER, "detail": String }
##   { "outcome": CharacterRecord.REJECT_ALREADY_DELETED, "detail": String }
func soft_delete_character(account_id: Variant, character_id: Variant) -> Dictionary:
	var lookup: Dictionary = _find_owned_character(account_id, character_id, true)
	if lookup["outcome"] != OUTCOME_OK:
		return lookup

	var record: CharacterRecord = lookup["character"]
	if record.deleted:
		return _result(CharacterRecordScript.REJECT_ALREADY_DELETED, "Character '%s' is already deleted." % character_id)

	var txn_result: Dictionary = _store.transaction(func() -> bool:
		var update: Dictionary = _store.query_with_bindings(
			"UPDATE characters SET deleted = 1 WHERE character_id = ?;",
			[character_id]
		)
		return update["outcome"] == SqliteStore.OUTCOME_OK
	)
	if txn_result["outcome"] != SqliteStore.OUTCOME_OK:
		return _result(SqliteStore.OUTCOME_TRANSACTION_FAILED, txn_result["detail"])

	return _result(OUTCOME_OK, "Character '%s' soft-deleted." % character_id)


func _account_exists(account_id: String) -> bool:
	var result: Dictionary = _store.query_with_bindings(
		"SELECT account_id FROM accounts WHERE account_id = ?;", [account_id]
	)
	return result["outcome"] == SqliteStore.OUTCOME_OK and not (result["rows"] as Array).is_empty()


func _find_account_by_id(account_id: String) -> Dictionary:
	var result: Dictionary = _store.query_with_bindings(
		"SELECT account_id, username FROM accounts WHERE account_id = ?;", [account_id]
	)
	if result["outcome"] != SqliteStore.OUTCOME_OK:
		return _result(SqliteStore.OUTCOME_QUERY_FAILED, result["detail"])
	var rows: Array = result["rows"]
	if rows.is_empty():
		return _result("NO_SUCH_ACCOUNT", "No account with account_id '%s'." % account_id)
	var row: Dictionary = rows[0]
	return {"outcome": OUTCOME_OK, "account_id": row["account_id"], "username": row["username"]}


func _count_live_characters(account_id: String) -> int:
	var result: Dictionary = _store.query_with_bindings(
		"SELECT COUNT(*) AS live_count FROM characters WHERE account_id = ? AND deleted = 0;", [account_id]
	)
	if result["outcome"] != SqliteStore.OUTCOME_OK or (result["rows"] as Array).is_empty():
		return CharacterRecordScript.MAX_CHARACTERS_PER_ACCOUNT
	return int((result["rows"][0] as Dictionary)["live_count"])


func _live_name_exists(display_name: String) -> bool:
	var result: Dictionary = _store.query_with_bindings(
		"SELECT character_id FROM characters WHERE display_name = ? AND deleted = 0;", [display_name]
	)
	return result["outcome"] == SqliteStore.OUTCOME_OK and not (result["rows"] as Array).is_empty()


## Shared ownership/existence lookup for select_character/soft_delete_character.
## `include_deleted` allows soft_delete_character to distinguish
## NO_SUCH_CHARACTER from ALREADY_DELETED for its own row.
func _find_owned_character(account_id: Variant, character_id: Variant, include_deleted: bool = false) -> Dictionary:
	if not _store.is_open():
		return _result(SqliteStore.OUTCOME_NOT_OPEN, "Store is not open.")
	if not (account_id is String) or (account_id as String).is_empty():
		return _result(CharacterRecordScript.REJECT_MALFORMED, "account_id must be a non-empty string.")
	if not (character_id is String) or (character_id as String).is_empty():
		return _result(CharacterRecordScript.REJECT_MALFORMED, "character_id must be a non-empty string.")

	var sql: String = "SELECT character_id, account_id, display_name, cosmetic_json, created_at, last_played_at, deleted FROM characters WHERE character_id = ?"
	if not include_deleted:
		sql += " AND deleted = 0"
	sql += ";"

	var select_result: Dictionary = _store.query_with_bindings(sql, [character_id])
	if select_result["outcome"] != SqliteStore.OUTCOME_OK:
		return _result(SqliteStore.OUTCOME_QUERY_FAILED, select_result["detail"])

	var rows: Array = select_result["rows"]
	if rows.is_empty():
		return _result(CharacterRecordScript.REJECT_NO_SUCH_CHARACTER, "No Character with character_id '%s'." % character_id)

	var row: Dictionary = rows[0]
	if String(row["account_id"]) != (account_id as String):
		return _result(CharacterRecordScript.REJECT_NOT_OWNER, "Account '%s' does not own Character '%s'." % [account_id, character_id])

	return {
		"outcome": OUTCOME_OK,
		"character": _row_to_character_record(row, row.get("deleted", 0) == 1),
	}


func _row_to_character_record(row: Dictionary, deleted: bool) -> CharacterRecord:
	var cosmetic: Dictionary = {}
	var parsed: Variant = JSON.parse_string(String(row["cosmetic_json"]))
	if parsed is Dictionary:
		cosmetic = parsed

	return CharacterRecordScript.new(
		row["character_id"],
		row["account_id"],
		row["display_name"],
		cosmetic,
		int(row["created_at"]),
		int(row["last_played_at"]),
		deleted,
		null
	)


func _generate_id(prefix: String) -> String:
	_id_sequence += 1
	return "%s-%d-%d-%d" % [prefix, Time.get_ticks_usec(), OS.get_process_id(), _id_sequence]


func _now() -> int:
	return Time.get_unix_time_from_system() as int


func _result(outcome: String, detail: String) -> Dictionary:
	return {
		"outcome": outcome,
		"detail": detail,
	}
