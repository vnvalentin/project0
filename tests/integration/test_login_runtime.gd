extends GutTest
## Slice 068: public-seam test for the shared login-authority builder
## (server/login_runtime.gd). Builds a LoginRuntime standalone (its own temp
## SQLite store, no game server) and proves the full authority + cross-process
## trust flow: register -> create/select Character -> issue a selected-Character
## assertion -> validate it with an independent validator -> establish a session
## on a fresh peer purely from that assertion. Also proves a validator holding a
## different secret rejects the token (the trust boundary a separate login
## process relies on). Mirrors tests/integration/test_login_gateway_assertions.gd.

const SqliteStoreScript: Script = preload("res://server/sqlite_store.gd")
const AccountCharacterRepositoryScript: Script = preload("res://server/account_character_repository.gd")
const LoginRuntimeScript: Script = preload("res://server/login_runtime.gd")
const AssertionValidatorScript: Script = preload("res://server/assertion_validator.gd")
const SessionAssertionScript: Script = preload("res://shared/session_assertion.gd")

const SECRET: String = "0f1e2d3c4b5a69788796a5b4c3d2e1f00f1e2d3c4b5a69788796a5b4c3d2e1f0"
const WRONG_SECRET: String = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"

var _relative_path: String = ""
var _store: SqliteStore = null
var _repo: AccountCharacterRepository = null
var _container: Node = null
var _auth: Node = null
var _gateway: Node = null
var _external_validator: RefCounted = null


func before_each() -> void:
	_relative_path = "test_login_runtime_%d_%d.db" % [Time.get_ticks_usec(), randi()]
	_store = SqliteStoreScript.new()
	_store.open(_relative_path)
	_repo = AccountCharacterRepositoryScript.new(_store)
	_repo.ensure_schema()
	_container = Node.new()
	add_child_autofree(_container)
	var services: Dictionary = LoginRuntimeScript.build_services(_repo, _container, SECRET)
	_auth = services["auth"]
	_gateway = services["gateway"]
	_external_validator = AssertionValidatorScript.new(SECRET, LoginRuntimeScript.ASSERTION_ISSUER_ID, LoginRuntimeScript.ASSERTION_AUDIENCE)


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


func test_build_services_wires_a_working_login_authority() -> void:
	var account: Dictionary = await _gateway.register(1, "alice", "hunter2")
	assert_eq(account["outcome"], "ok", "register works through the runtime-built gateway")
	assert_true(_gateway.is_authenticated(1), "the session is bound after register")


func test_full_authority_and_assertion_trust_flow() -> void:
	await _gateway.register(1, "carol", "passphrase")
	var created: Dictionary = _gateway.create_character(1, "Carol the Bold", {})
	assert_eq(created["outcome"], "ok", "a Character is created under the session account")
	var character_id: String = created["character"].character_id
	_gateway.select_character(1, character_id)

	var minted: Dictionary = _gateway.issue_character_assertion(1, 1000, 60)
	assert_eq(minted["outcome"], "ok", "a selected-Character assertion is minted")

	# An independent validator (the game server's side) accepts the token and
	# reads back the asserted account + selection — the cross-process trust link.
	var validated: Dictionary = _external_validator.validate(minted["assertion"], 1001)
	assert_eq(validated["outcome"], SessionAssertionScript.OUTCOME_OK, "the token validates on the independent validator")
	assert_eq(validated["claims"][SessionAssertionScript.KEY_CHARACTER_ID], character_id, "the assertion carries the selected Character")

	# The game server binds a fresh peer's session purely from the assertion.
	var established: Dictionary = _gateway.establish_session_from_assertion(2, minted["assertion"], 1001)
	assert_eq(established["outcome"], "ok", "a fresh peer's session is established from the assertion")
	assert_eq(_auth.get_session_registry().get_selected_character(2), character_id, "the established session carries the asserted selection")


func test_assertion_from_a_different_secret_is_rejected() -> void:
	await _gateway.register(1, "dave", "passphrase")
	var minted: Dictionary = _gateway.issue_account_assertion(1, 1000, 60)
	assert_eq(minted["outcome"], "ok")

	var foreign_validator: RefCounted = AssertionValidatorScript.new(WRONG_SECRET, LoginRuntimeScript.ASSERTION_ISSUER_ID, LoginRuntimeScript.ASSERTION_AUDIENCE)
	var result: Dictionary = foreign_validator.validate(minted["assertion"], 1001)
	assert_ne(result["outcome"], SessionAssertionScript.OUTCOME_OK, "a validator with a different secret rejects the token")
