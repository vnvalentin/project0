extends GutTest
## Slice 060: public-seam test for assertion-backed session establishment in the
## login gateway (server/login_gateway.gd, Slice 060 additions). Wires the Slice
## 059 AssertionIssuer/AssertionValidator into a real LoginGateway over
## AuthService+CharacterService on a temporary SQLite store, and proves the
## gateway mints session assertions and establishes a session purely from a
## validated one. Mirrors tests/integration/test_login_gateway.gd setup.

const SqliteStoreScript: Script = preload("res://server/sqlite_store.gd")
const AccountCharacterRepositoryScript: Script = preload("res://server/account_character_repository.gd")
const AuthServiceScript: Script = preload("res://server/auth_service.gd")
const CharacterServiceScript: Script = preload("res://server/character_service.gd")
const LoginGatewayScript: Script = preload("res://server/login_gateway.gd")
const AssertionIssuerScript: Script = preload("res://server/assertion_issuer.gd")
const AssertionValidatorScript: Script = preload("res://server/assertion_validator.gd")
const SessionAssertionScript: Script = preload("res://shared/session_assertion.gd")

const SECRET: String = "0f1e2d3c4b5a69788796a5b4c3d2e1f00f1e2d3c4b5a69788796a5b4c3d2e1f0"
const ISSUER: String = "project0-login"
const AUDIENCE: String = "project0-game"

var _relative_path: String = ""
var _store: SqliteStore = null
var _repo: AccountCharacterRepository = null
var _auth: Node = null
var _characters: CharacterService = null
var _gateway: Node = null
var _external_validator: RefCounted = null


func before_each() -> void:
	_relative_path = "test_login_gateway_assertions_%d_%d.db" % [Time.get_ticks_usec(), randi()]
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
	add_child_autofree(_gateway)
	_external_validator = AssertionValidatorScript.new(SECRET, ISSUER, AUDIENCE)


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


func test_issue_account_assertion_after_login() -> void:
	var account: Dictionary = await _gateway.register(1, "alice", "hunter2")
	var minted: Dictionary = _gateway.issue_account_assertion(1, 1000, 60)
	assert_eq(minted["outcome"], LoginGatewayScript.OUTCOME_OK, "an account assertion is minted for a bound session")

	var validated: Dictionary = _external_validator.validate(minted["assertion"], 1001)
	assert_eq(validated["outcome"], SessionAssertionScript.OUTCOME_OK, "the minted token independently validates")
	assert_eq(validated["claims"][SessionAssertionScript.KEY_ACCOUNT_ID], account["account_id"], "the assertion carries the session account")
	assert_eq(validated["claims"][SessionAssertionScript.KEY_CHARACTER_ID], "", "an account assertion carries no character")


func test_establish_session_from_account_assertion() -> void:
	var account: Dictionary = await _gateway.register(1, "bob", "correct-horse")
	var minted: Dictionary = _gateway.issue_account_assertion(1, 1000, 60)

	var established: Dictionary = _gateway.establish_session_from_assertion(2, minted["assertion"], 1001)
	assert_eq(established["outcome"], LoginGatewayScript.OUTCOME_OK, "a valid assertion establishes a session on a fresh peer")
	assert_true(_gateway.is_authenticated(2), "the peer holds a session after establishment")
	var session: Dictionary = _auth.get_session_registry().get_session(2)
	assert_eq(session["account_id"], account["account_id"], "the established session carries the asserted account")


func test_issue_character_assertion_requires_selection_then_carries_it() -> void:
	await _gateway.register(1, "carol", "passphrase")
	assert_eq(_gateway.issue_character_assertion(1, 1000, 60)["outcome"], LoginGatewayScript.REASON_NO_CHARACTER, "no character selected yet -> rejected")

	var created: Dictionary = _gateway.create_character(1, "Carol the Bold", {})
	var character_id: String = created["character"].character_id
	_gateway.select_character(1, character_id)

	var minted: Dictionary = _gateway.issue_character_assertion(1, 1000, 60)
	assert_eq(minted["outcome"], LoginGatewayScript.OUTCOME_OK)
	var validated: Dictionary = _external_validator.validate(minted["assertion"], 1001)
	assert_eq(validated["claims"][SessionAssertionScript.KEY_CHARACTER_ID], character_id, "the assertion carries the selected Character")


func test_establish_with_character_assertion_binds_the_selection() -> void:
	await _gateway.register(1, "dave", "passphrase")
	var created: Dictionary = _gateway.create_character(1, "Dave the Quick", {})
	var character_id: String = created["character"].character_id
	_gateway.select_character(1, character_id)
	var minted: Dictionary = _gateway.issue_character_assertion(1, 1000, 60)

	var established: Dictionary = _gateway.establish_session_from_assertion(3, minted["assertion"], 1001)
	assert_eq(established["outcome"], LoginGatewayScript.OUTCOME_OK)
	assert_eq(_auth.get_session_registry().get_selected_character(3), character_id, "the established session carries the asserted selection")


func test_establish_rejects_expired_assertion_and_binds_nothing() -> void:
	await _gateway.register(1, "erin", "passphrase")
	var minted: Dictionary = _gateway.issue_account_assertion(1, 1000, 60)
	var established: Dictionary = _gateway.establish_session_from_assertion(4, minted["assertion"], 2000)
	assert_eq(established["outcome"], SessionAssertionScript.REASON_EXPIRED, "an expired assertion is rejected")
	assert_false(_gateway.is_authenticated(4), "no session is bound for a rejected assertion")


func test_establish_rejects_tampered_assertion_and_binds_nothing() -> void:
	await _gateway.register(1, "frank", "passphrase")
	var minted: Dictionary = _gateway.issue_account_assertion(1, 1000, 60)
	var parts: Dictionary = SessionAssertionScript.split_token(minted["assertion"])
	var payload: String = parts["payload_b64"]
	var flipped: String = ("A" if payload[0] != "A" else "B") + payload.substr(1)
	var tampered: String = SessionAssertionScript.encode_token(flipped, parts["sig_b64"])

	var established: Dictionary = _gateway.establish_session_from_assertion(5, tampered, 1001)
	assert_eq(established["outcome"], SessionAssertionScript.REASON_BAD_SIGNATURE, "a tampered assertion fails the signature check")
	assert_false(_gateway.is_authenticated(5), "no session is bound for a tampered assertion")


func test_issue_without_session_is_rejected() -> void:
	assert_eq(_gateway.issue_account_assertion(99, 1000, 60)["outcome"], LoginGatewayScript.REASON_NO_SESSION, "issuing for an unauthenticated peer is rejected")
