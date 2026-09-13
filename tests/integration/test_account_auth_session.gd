extends GutTest
## Headless public-seam test for Slice 040's server-only account
## authentication and session dispatch (server/auth_service.gd), exercised
## directly against a temporary user:// SQLite database through the Slice
## 038/039 SqliteStore/AccountCharacterRepository seams (both consumed
## unmodified). Covers the acceptance scenarios from
## .scratch/player-accounts/handoff-040-account-auth-session.md and
## docs/slices/040-account-auth-session.md. No ENet peer is needed: AuthService
## is called directly with a bare peer_id int, matching how
## server_main.gd's RPC dispatch would call it after resolving
## multiplayer.get_remote_sender_id(). Mirrors
## tests/integration/test_account_character_repository.gd's per-test
## temporary-database setup/teardown.

const SqliteStoreScript: Script = preload("res://server/sqlite_store.gd")
const AccountCharacterRepositoryScript: Script = preload("res://server/account_character_repository.gd")
const AuthServiceScript: Script = preload("res://server/auth_service.gd")
const CharacterRecordScript: Script = preload("res://shared/character_record.gd")

var _relative_path: String = ""
var _store: SqliteStore = null
var _repo: AccountCharacterRepository = null
var _auth: Node = null


func before_each() -> void:
	_relative_path = "test_account_auth_session_%d_%d.db" % [Time.get_ticks_usec(), randi()]
	_store = SqliteStoreScript.new()
	_store.open(_relative_path)
	_repo = AccountCharacterRepositoryScript.new(_store)
	_repo.ensure_schema()
	_auth = AuthServiceScript.new(_repo)
	add_child_autofree(_auth)


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


# Scenario 1: register persists an account (via the repo/DB), binds a session,
# and returns an AccountHandle-shaped result.
func test_register_persists_account_binds_session_and_returns_account_handle() -> void:
	var result: Dictionary = await _auth.register(1, "alice", "hunter2")
	assert_eq(result["outcome"], "ok", "register succeeds: %s" % result.get("detail", ""))
	assert_true(String(result["account_id"]).length() > 0, "account_id is opaque and non-empty")
	assert_eq(result["username"], "alice")
	assert_true(_auth.is_authenticated(1), "the peer holds a bound session after register")

	var lookup: Dictionary = _repo.find_account_by_username("alice")
	assert_eq(lookup["outcome"], "ok", "the account is durably persisted via the repository")
	assert_eq(lookup["account_id"], result["account_id"])


# Scenario 2: duplicate username is rejected, no second row.
func test_register_duplicate_username_is_rejected() -> void:
	var first: Dictionary = await _auth.register(1, "alice", "hunter2")
	assert_eq(first["outcome"], "ok")

	var second: Dictionary = await _auth.register(2, "alice", "different-pw")
	assert_eq(second["outcome"], CharacterRecordScript.REJECT_USERNAME_TAKEN, "a duplicate username is rejected")
	assert_false(_auth.is_authenticated(2), "the rejected peer holds no session")


# Scenario 3: login with correct password succeeds + binds a session; wrong
# password and unknown username both -> BAD_CREDENTIALS (no user enumeration).
func test_login_correct_password_succeeds_and_binds_session() -> void:
	await _auth.register(1, "alice", "hunter2")

	var result: Dictionary = await _auth.login(2, "alice", "hunter2")
	assert_eq(result["outcome"], "ok", "login with the correct password succeeds: %s" % result.get("detail", ""))
	assert_eq(result["username"], "alice")
	assert_true(_auth.is_authenticated(2), "the peer holds a bound session after login")


func test_login_wrong_password_and_unknown_username_both_report_bad_credentials() -> void:
	await _auth.register(1, "alice", "hunter2")

	var wrong_password: Dictionary = await _auth.login(2, "alice", "wrong-password")
	assert_eq(wrong_password["outcome"], CharacterRecordScript.REJECT_BAD_CREDENTIALS, "a wrong password is rejected")
	assert_false(_auth.is_authenticated(2))

	var unknown_username: Dictionary = await _auth.login(3, "nobody", "whatever")
	assert_eq(unknown_username["outcome"], CharacterRecordScript.REJECT_BAD_CREDENTIALS, "an unknown username reports the SAME reason as a wrong password")
	assert_false(_auth.is_authenticated(3))


# Scenario: malformed input (empty username/password) is rejected without
# touching the repository or binding a session.
func test_malformed_credentials_are_rejected() -> void:
	var empty_username: Dictionary = await _auth.register(1, "", "somepassword")
	assert_eq(empty_username["outcome"], CharacterRecordScript.REJECT_MALFORMED, "an empty username is rejected")
	assert_false(_auth.is_authenticated(1))

	var empty_password: Dictionary = await _auth.register(2, "someuser", "")
	assert_eq(empty_password["outcome"], CharacterRecordScript.REJECT_MALFORMED, "an empty password is rejected")
	assert_false(_auth.is_authenticated(2))

	var login_empty: Dictionary = await _auth.login(3, "someuser", "")
	assert_eq(login_empty["outcome"], CharacterRecordScript.REJECT_MALFORMED, "login also rejects an empty password")


# Scenario 4: a second register/login on an already-authenticated peer ->
# ALREADY_AUTHENTICATED, both for a repeated register and a login attempt.
func test_second_auth_on_same_peer_is_rejected_as_already_authenticated() -> void:
	await _auth.register(1, "alice", "hunter2")

	var second_register: Dictionary = await _auth.register(1, "bob", "otherpw")
	assert_eq(second_register["outcome"], CharacterRecordScript.REJECT_ALREADY_AUTHENTICATED, "a second register on the same peer is rejected")

	var second_login: Dictionary = await _auth.login(1, "alice", "hunter2")
	assert_eq(second_login["outcome"], CharacterRecordScript.REJECT_ALREADY_AUTHENTICATED, "a login on an already-authenticated peer is rejected too")

	# No second account was created by the rejected second register.
	var bob_lookup: Dictionary = _repo.find_account_by_username("bob")
	assert_ne(bob_lookup["outcome"], "ok", "the rejected register did not create a 'bob' account")


# Scenario 5: disconnect clears the session; a reconnect (same peer_id reused)
# must fully re-authenticate.
func test_clear_session_on_disconnect_requires_full_reauth() -> void:
	await _auth.register(1, "alice", "hunter2")
	assert_true(_auth.is_authenticated(1))

	_auth.clear_session(1)
	assert_false(_auth.is_authenticated(1), "the session is cleared on disconnect")

	# The same peer_id reconnecting must log in again; it cannot silently regain
	# access without submitting credentials.
	var reauth: Dictionary = await _auth.login(1, "alice", "hunter2")
	assert_eq(reauth["outcome"], "ok", "the peer can log back in after its session was cleared")
	assert_true(_auth.is_authenticated(1))


# The session token itself is never persisted: two AuthService instances built
# on top of the same durable account row (simulating a server restart with a
# fresh in-memory SessionRegistry) never share authentication state.
func test_session_is_never_persisted_across_a_fresh_auth_service() -> void:
	await _auth.register(1, "alice", "hunter2")
	assert_true(_auth.is_authenticated(1))

	var fresh_auth: Node = AuthServiceScript.new(_repo)
	add_child_autofree(fresh_auth)
	assert_false(fresh_auth.is_authenticated(1), "a fresh AuthService (simulating a server restart) has no session for peer 1")

	# The account itself is still durable, so the peer can re-authenticate
	# against the fresh in-memory session registry.
	var relogin: Dictionary = await fresh_auth.login(1, "alice", "hunter2")
	assert_eq(relogin["outcome"], "ok")
	assert_true(fresh_auth.is_authenticated(1))
