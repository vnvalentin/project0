extends GutTest
## Slice 058: public-seam test for the in-process login gateway
## (server/login_gateway.gd). Constructs a LoginGateway over a real AuthService
## + CharacterService on a temporary user:// SQLite store and proves the facade
## delegates identically to the underlying services (pure delegation, no
## behavior change). Mirrors tests/integration/test_account_auth_session.gd and
## test_character_crud_rpc.gd setup. AuthService and the gateway are Nodes added
## to the tree because AuthService.register/login are coroutines that await
## get_tree().process_frame while PBKDF2 runs off-thread.

const SqliteStoreScript: Script = preload("res://server/sqlite_store.gd")
const AccountCharacterRepositoryScript: Script = preload("res://server/account_character_repository.gd")
const AuthServiceScript: Script = preload("res://server/auth_service.gd")
const CharacterServiceScript: Script = preload("res://server/character_service.gd")
const LoginGatewayScript: Script = preload("res://server/login_gateway.gd")

var _relative_path: String = ""
var _store: SqliteStore = null
var _repo: AccountCharacterRepository = null
var _auth: Node = null
var _characters: CharacterService = null
var _gateway: Node = null


func before_each() -> void:
	_relative_path = "test_login_gateway_%d_%d.db" % [Time.get_ticks_usec(), randi()]
	_store = SqliteStoreScript.new()
	_store.open(_relative_path)
	_repo = AccountCharacterRepositoryScript.new(_store)
	_repo.ensure_schema()
	_auth = AuthServiceScript.new(_repo)
	add_child_autofree(_auth)
	_characters = CharacterServiceScript.new(_repo, _auth.get_session_registry())
	_gateway = LoginGatewayScript.new(_auth, _characters)
	add_child_autofree(_gateway)


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


func test_register_delegates_and_binds_session() -> void:
	var result: Dictionary = await _gateway.register(1, "alice", "hunter2")
	assert_eq(result["outcome"], "ok", "register delegates to AuthService and succeeds")
	assert_true(String(result["account_id"]).length() > 0, "account_id is opaque and non-empty")
	assert_true(_gateway.is_authenticated(1), "gateway.is_authenticated reflects the bound session")


func test_login_delegates_and_reauthenticates() -> void:
	var registered: Dictionary = await _gateway.register(1, "bob", "correct-horse")
	assert_eq(registered["outcome"], "ok")
	_gateway.clear_session(1)
	assert_false(_gateway.is_authenticated(1), "clear_session delegates and clears the session")

	var login_result: Dictionary = await _gateway.login(2, "bob", "correct-horse")
	assert_eq(login_result["outcome"], "ok", "login delegates and re-authenticates")
	assert_true(_gateway.is_authenticated(2), "the new peer holds a session after login")


func test_character_operations_delegate_to_character_service() -> void:
	await _gateway.register(1, "carol", "passphrase")

	var created: Dictionary = _gateway.create_character(1, "Carol the Bold", {})
	assert_eq(created["outcome"], "ok", "create_character delegates and succeeds")
	var character_id: String = created["character"].character_id

	var listed: Dictionary = _gateway.list_characters(1)
	assert_eq(listed["outcome"], "ok", "list_characters delegates")
	assert_eq((listed["characters"] as Array).size(), 1, "the created Character is listed")

	var selected: Dictionary = _gateway.select_character(1, character_id)
	assert_eq(selected["outcome"], "ok", "select_character delegates")

	var current: Dictionary = _gateway.get_selected_character(1)
	assert_eq(current["outcome"], "ok", "get_selected_character delegates")
	assert_eq(current["character"].character_id, character_id, "the selected Character is returned")

	var deleted: Dictionary = _gateway.delete_character(1, character_id)
	assert_eq(deleted["outcome"], "ok", "delete_character delegates")


func test_character_ops_require_session_like_the_underlying_service() -> void:
	# No session bound for peer 9 -> the gateway forwards CharacterService's
	# fail-closed rejection unchanged.
	var listed: Dictionary = _gateway.list_characters(9)
	assert_eq(listed["outcome"], CharacterServiceScript.REJECT_NOT_AUTHENTICATED, "unauthenticated list is rejected via delegation")
	assert_false(listed.has("characters") and (listed["characters"] as Array).size() > 0, "no characters leak for an unauthenticated peer")
