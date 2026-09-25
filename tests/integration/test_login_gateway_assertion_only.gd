extends GutTest
## Slice 076: public-seam test for the game server's assertion-only mode
## (server/login_gateway.gd). A gateway with account authority disabled refuses
## register/login/Character-CRUD (accounts live on the login process) but still
## establishes a session from a signed assertion and resolves the selected
## Character from the snapshot for world entry. Mirrors
## tests/integration/test_login_gateway_assertions.gd setup.

const SqliteStoreScript: Script = preload("res://server/sqlite_store.gd")
const AccountCharacterRepositoryScript: Script = preload("res://server/account_character_repository.gd")
const AuthServiceScript: Script = preload("res://server/auth_service.gd")
const CharacterServiceScript: Script = preload("res://server/character_service.gd")
const LoginGatewayScript: Script = preload("res://server/login_gateway.gd")
const AssertionIssuerScript: Script = preload("res://server/assertion_issuer.gd")
const AssertionValidatorScript: Script = preload("res://server/assertion_validator.gd")
const SessionAssertionScript: Script = preload("res://shared/session_assertion.gd")
const JourneyRegistryScript: Script = preload("res://server/journey_registry.gd")

const SECRET: String = "0f1e2d3c4b5a69788796a5b4c3d2e1f00f1e2d3c4b5a69788796a5b4c3d2e1f0"
const ISSUER: String = "project0-login"
const AUDIENCE: String = "project0-game"

var _relative_path: String = ""
var _store: SqliteStore = null
var _repo: AccountCharacterRepository = null
var _auth: Node = null
var _characters: CharacterService = null
var _gateway: Node = null
var _journey_registry: RefCounted = null


func before_each() -> void:
	_relative_path = "test_login_gateway_assertion_only_%d_%d.db" % [Time.get_ticks_usec(), randi()]
	_store = SqliteStoreScript.new()
	_store.open(_relative_path)
	_repo = AccountCharacterRepositoryScript.new(_store)
	_repo.ensure_schema()
	_auth = AuthServiceScript.new(_repo)
	add_child_autofree(_auth)
	_characters = CharacterServiceScript.new(_repo, _auth.get_session_registry())
	_gateway = LoginGatewayScript.new(_auth, _characters)
	_gateway.set_assertion_seams(
		AssertionIssuerScript.new(SECRET, ISSUER, AUDIENCE),
		AssertionValidatorScript.new(SECRET, ISSUER, AUDIENCE)
	)
	# Slice 076: the game server in a split deployment.
	_gateway.set_account_authority_enabled(false)
	_journey_registry = JourneyRegistryScript.new()
	_gateway.set_journey_registry(_journey_registry)
	add_child_autofree(_gateway)


func after_each() -> void:
	if _store.is_open():
		_store.close()
	if is_instance_valid(_characters):
		_characters.free()
	for suffix: String in ["", "-wal", "-shm", "-journal"]:
		var abs_path: String = ProjectSettings.globalize_path("user://%s%s" % [_relative_path, suffix])
		if FileAccess.file_exists(abs_path):
			DirAccess.remove_absolute(abs_path)


func test_register_and_login_are_refused() -> void:
	var registered: Dictionary = await _gateway.register(1, "alice", "hunter2")
	assert_eq(registered["outcome"], LoginGatewayScript.REASON_ACCOUNT_AUTHORITY_DISABLED, "register is refused in assertion-only mode")
	assert_false(_gateway.is_authenticated(1), "no session is bound by a refused register")

	var logged_in: Dictionary = await _gateway.login(2, "alice", "hunter2")
	assert_eq(logged_in["outcome"], LoginGatewayScript.REASON_ACCOUNT_AUTHORITY_DISABLED, "login is refused in assertion-only mode")


func test_character_crud_is_refused() -> void:
	assert_eq(_gateway.list_characters(1)["outcome"], LoginGatewayScript.REASON_ACCOUNT_AUTHORITY_DISABLED, "list is refused")
	assert_eq(_gateway.create_character(1, "Hero", {})["outcome"], LoginGatewayScript.REASON_ACCOUNT_AUTHORITY_DISABLED, "create is refused")
	assert_eq(_gateway.select_character(1, "char-1")["outcome"], LoginGatewayScript.REASON_ACCOUNT_AUTHORITY_DISABLED, "select is refused")
	assert_eq(_gateway.delete_character(1, "char-1")["outcome"], LoginGatewayScript.REASON_ACCOUNT_AUTHORITY_DISABLED, "delete is refused")


func test_assertion_path_still_establishes_and_binds() -> void:
	# A signed assertion from the login authority (minted here with a snapshot).
	var issuer: RefCounted = AssertionIssuerScript.new(SECRET, ISSUER, AUDIENCE)
	var token: String = issuer.issue("sess-1", "acc-1", "char-1", 1000, 300, "Carol the Bold", {"tint": "amber"})

	var established: Dictionary = _gateway.establish_session_from_assertion(7, token, 1001)
	assert_eq(established["outcome"], LoginGatewayScript.OUTCOME_OK, "the assertion path still establishes a session in assertion-only mode")
	assert_true(_gateway.is_authenticated(7), "the peer holds a session from the assertion")

	var selected: Dictionary = _gateway.get_selected_character(7)
	assert_eq(selected["outcome"], "ok", "world entry still resolves the Character from the snapshot")
	assert_eq(selected["character"].display_name, "Carol the Bold", "the bound Character came from the signed snapshot")


func test_asserted_character_reclaims_one_journey_after_disconnect() -> void:
	var issuer: RefCounted = AssertionIssuerScript.new(SECRET, ISSUER, AUDIENCE)
	var token: String = issuer.issue("sess-1", "acc-1", "char-1", 1000, 300, "Carol the Bold", {})

	assert_eq(_gateway.establish_session_from_assertion(7, token, 1001)["outcome"], LoginGatewayScript.OUTCOME_OK)
	var first_entry: Dictionary = _gateway.get_selected_character(7)
	assert_eq(first_entry["outcome"], LoginGatewayScript.OUTCOME_OK)

	assert_eq(_gateway.establish_session_from_assertion(8, token, 1001)["outcome"], LoginGatewayScript.OUTCOME_OK)
	var conflict: Dictionary = _gateway.get_selected_character(8)
	assert_eq(conflict["outcome"], JourneyRegistryScript.REASON_CHARACTER_ACTIVE)

	var disconnected: Dictionary = _journey_registry.mark_disconnected("char-1", 7, int(Time.get_unix_time_from_system()))
	assert_eq(disconnected["kind"], "disconnect")
	_gateway.clear_session(7)
	var reclaimed: Dictionary = _gateway.get_selected_character(8)
	assert_eq(reclaimed["outcome"], JourneyRegistryScript.OUTCOME_OK)
	assert_eq(reclaimed["journey_id"], first_entry["journey_id"])
