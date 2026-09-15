extends GutTest
## Slice 069: public-seam test for the cross-process assertion handoff. Builds
## TWO independent LoginRuntimes on DIFFERENT accounts databases but the SAME
## assertion secret — modelling the login process and the game process — and
## proves the game side establishes a peer's session purely from an assertion the
## login side minted, WITHOUT its DB holding that account. A token signed with a
## different secret is rejected and binds nothing (the trust boundary). This is
## the trust model the register-from-login / present-to-game RPC seams
## (client/network_client.gd, Slice 069) carry over the wire.

const SqliteStoreScript: Script = preload("res://server/sqlite_store.gd")
const AccountCharacterRepositoryScript: Script = preload("res://server/account_character_repository.gd")
const LoginRuntimeScript: Script = preload("res://server/login_runtime.gd")
const AssertionIssuerScript: Script = preload("res://server/assertion_issuer.gd")
const SessionAssertionScript: Script = preload("res://shared/session_assertion.gd")

const SECRET: String = "0f1e2d3c4b5a69788796a5b4c3d2e1f00f1e2d3c4b5a69788796a5b4c3d2e1f0"
const WRONG_SECRET: String = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"

var _login_path: String = ""
var _game_path: String = ""
var _login_store: SqliteStore = null
var _game_store: SqliteStore = null
var _login_container: Node = null
var _game_container: Node = null
var _login_gateway: Node = null
var _game_gateway: Node = null
var _game_auth: Node = null


func before_each() -> void:
	_login_container = Node.new()
	add_child_autofree(_login_container)
	_game_container = Node.new()
	add_child_autofree(_game_container)

	_login_path = "test_handoff_login_%d_%d.db" % [Time.get_ticks_usec(), randi()]
	_login_store = SqliteStoreScript.new()
	_login_store.open(_login_path)
	var login_repo: AccountCharacterRepository = AccountCharacterRepositoryScript.new(_login_store)
	login_repo.ensure_schema()

	_game_path = "test_handoff_game_%d_%d.db" % [Time.get_ticks_usec(), randi()]
	_game_store = SqliteStoreScript.new()
	_game_store.open(_game_path)
	var game_repo: AccountCharacterRepository = AccountCharacterRepositoryScript.new(_game_store)
	game_repo.ensure_schema()

	# Different DBs, same shared assertion secret — the login and game processes.
	_login_gateway = LoginRuntimeScript.build_services(login_repo, _login_container, SECRET)["gateway"]
	var game_services: Dictionary = LoginRuntimeScript.build_services(game_repo, _game_container, SECRET)
	_game_gateway = game_services["gateway"]
	_game_auth = game_services["auth"]


func after_each() -> void:
	if _login_store.is_open():
		_login_store.close()
	if _game_store.is_open():
		_game_store.close()
	_delete_user_file(_login_path)
	_delete_user_file(_game_path)
	for suffix: String in ["-wal", "-shm", "-journal"]:
		_delete_user_file(_login_path + suffix)
		_delete_user_file(_game_path + suffix)


func _delete_user_file(relative_path: String) -> void:
	var abs_path: String = ProjectSettings.globalize_path("user://%s" % relative_path)
	if FileAccess.file_exists(abs_path):
		DirAccess.remove_absolute(abs_path)


func test_game_establishes_session_from_login_assertion_without_shared_db() -> void:
	await _login_gateway.register(1, "alice", "hunter2")
	var created: Dictionary = _login_gateway.create_character(1, "Alice the Bold", {})
	var character_id: String = created["character"].character_id
	_login_gateway.select_character(1, character_id)
	var minted: Dictionary = _login_gateway.issue_character_assertion(1, 1000, 300)
	assert_eq(minted["outcome"], "ok", "the login process mints a selected-Character assertion")

	# The game side's DB has no "alice" account, yet it establishes the session
	# purely from the validated assertion — the point of the split.
	var established: Dictionary = _game_gateway.establish_session_from_assertion(7, minted["assertion"], 1001)
	assert_eq(established["outcome"], "ok", "the game process trusts the login assertion without a shared DB")
	assert_true(_game_gateway.is_authenticated(7), "the peer holds a game-server session")
	assert_eq(_game_auth.get_session_registry().get_selected_character(7), character_id, "the established session carries the asserted Character")


func test_game_rejects_assertion_signed_with_a_different_secret() -> void:
	var rogue_issuer: RefCounted = AssertionIssuerScript.new(WRONG_SECRET, LoginRuntimeScript.ASSERTION_ISSUER_ID, LoginRuntimeScript.ASSERTION_AUDIENCE)
	var forged: String = rogue_issuer.issue("rogue-session", "rogue-account", "", 1000, 300)

	var established: Dictionary = _game_gateway.establish_session_from_assertion(8, forged, 1001)
	assert_ne(established["outcome"], "ok", "a token signed with a different secret is rejected")
	assert_false(_game_gateway.is_authenticated(8), "no session is bound for a rejected assertion")
