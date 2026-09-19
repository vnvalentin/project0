extends GutTest
## Slice 088: public-seam test for the login authority's loopback-only HTTP
## delegation endpoint (server/login_loopback_http_endpoint.gd). Wires a real
## LoginGateway (AuthService + CharacterService + SessionRegistry + Slice 059
## assertion issuer/validator) over a temporary SQLite store, exactly like
## tests/integration/test_login_gateway_assertions.gd, then drives the endpoint
## over a REAL raw StreamPeerTCP client — the actual socket contract, not a
## mocked HTTP layer — matching the slice record's BDD plan.

const SqliteStoreScript: Script = preload("res://server/sqlite_store.gd")
const AccountCharacterRepositoryScript: Script = preload("res://server/account_character_repository.gd")
const AuthServiceScript: Script = preload("res://server/auth_service.gd")
const CharacterServiceScript: Script = preload("res://server/character_service.gd")
const LoginGatewayScript: Script = preload("res://server/login_gateway.gd")
const AssertionIssuerScript: Script = preload("res://server/assertion_issuer.gd")
const AssertionValidatorScript: Script = preload("res://server/assertion_validator.gd")
const LoginLoopbackHttpEndpointScript: Script = preload("res://server/login_loopback_http_endpoint.gd")

const SECRET: String = "0f1e2d3c4b5a69788796a5b4c3d2e1f00f1e2d3c4b5a69788796a5b4c3d2e1f0"
const ISSUER: String = "project0-login"
const AUDIENCE: String = "project0-game"
const REQUEST_PATH: String = "/internal/verify-and-mint"
const REQUEST_PATH_VALIDATE: String = "/internal/validate-assertion"
const REQUEST_PATH_CHAR_LIST: String = "/internal/characters/list"
const REQUEST_PATH_CHAR_CREATE: String = "/internal/characters/create"
const REQUEST_PATH_CHAR_DELETE: String = "/internal/characters/delete"
const REQUEST_PATH_CHAR_SELECT: String = "/internal/characters/select"
const MAX_WAIT_FRAMES: int = 300

var _relative_path: String = ""
var _store: SqliteStore = null
var _repo: AccountCharacterRepository = null
var _auth: Node = null
var _characters: CharacterService = null
var _gateway: Node = null
var _external_validator: RefCounted = null
var _endpoint: Node = null


func before_each() -> void:
	_relative_path = "test_login_loopback_http_endpoint_%d_%d.db" % [Time.get_ticks_usec(), randi()]
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

	_endpoint = LoginLoopbackHttpEndpointScript.new(_gateway)
	add_child_autofree(_endpoint)
	var bound_port: int = _endpoint.start()
	assert_ne(bound_port, -1, "the endpoint binds an ephemeral loopback port")


func after_each() -> void:
	_endpoint.stop()
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


## Sends a raw HTTP request over a fresh StreamPeerTCP connection to the given
## port and returns { "status_code": int, "body": String } parsed from the
## response. Bounded by MAX_WAIT_FRAMES so a hung/silent endpoint fails the
## test instead of hanging the suite.
func _raw_request(port: int, request_text: String) -> Dictionary:
	var client: StreamPeerTCP = StreamPeerTCP.new()
	var connect_error: Error = client.connect_to_host("127.0.0.1", port)
	assert_eq(connect_error, OK, "test client initiates a loopback connection")

	var connected: bool = false
	for _i in range(MAX_WAIT_FRAMES):
		client.poll()
		if client.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			connected = true
			break
		await wait_process_frames(1)
	assert_true(connected, "test client reaches STATUS_CONNECTED before the bounded wait elapses")
	if not connected:
		return {"status_code": -1, "body": ""}

	client.put_data(request_text.to_utf8_buffer())

	var response_bytes: PackedByteArray = PackedByteArray()
	for _i in range(MAX_WAIT_FRAMES):
		client.poll()
		var available: int = client.get_available_bytes()
		if available > 0:
			response_bytes.append_array(client.get_data(available)[1])
		if client.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			break
		await wait_process_frames(1)

	client.disconnect_from_host()
	return _parse_http_response(response_bytes)


func _parse_http_response(raw: PackedByteArray) -> Dictionary:
	var text: String = raw.get_string_from_utf8()
	var separator_index: int = text.find("\r\n\r\n")
	if separator_index == -1:
		return {"status_code": -1, "body": ""}
	var header_block: String = text.substr(0, separator_index)
	var body: String = text.substr(separator_index + 4)
	var lines: PackedStringArray = header_block.split("\r\n")
	var status_line_parts: PackedStringArray = lines[0].split(" ")
	var status_code: int = -1
	if status_line_parts.size() > 1 and status_line_parts[1].is_valid_int():
		status_code = status_line_parts[1].to_int()
	return {"status_code": status_code, "body": body}


func _build_request(body_text: String, content_type: String = "application/json", extra_header_lines: String = "", method: String = "POST", path: String = REQUEST_PATH) -> String:
	var body_bytes: PackedByteArray = body_text.to_utf8_buffer()
	var header: String = "%s %s HTTP/1.1\r\nHost: 127.0.0.1\r\n" % [method, path]
	if not content_type.is_empty():
		header += "Content-Type: %s\r\n" % content_type
	header += "Content-Length: %d\r\n" % body_bytes.size()
	header += extra_header_lines
	header += "\r\n"
	return header + body_text


func test_valid_credentials_return_assertion_and_leave_no_session() -> void:
	await _gateway.register(1, "alice", "correct horse battery staple")
	_gateway.clear_session(1)

	var request: String = _build_request(JSON.stringify({"username": "alice", "password": "correct horse battery staple"}))
	var response: Dictionary = await _raw_request(_endpoint.port, request)

	assert_eq(response["status_code"], 200, "valid credentials return 200")
	var parsed: Variant = JSON.parse_string(response["body"])
	assert_true(parsed is Dictionary, "the response body is valid JSON")
	var body: Dictionary = parsed
	assert_eq(body.get("outcome", ""), "ok", "the outcome is ok")
	assert_true(String(body.get("assertion", "")).length() > 0, "a non-empty assertion is returned")

	var validated: Dictionary = _external_validator.validate(body["assertion"], int(Time.get_unix_time_from_system()))
	assert_eq(validated["outcome"], "ok", "the minted assertion independently validates")

	# No synthetic session should remain bound anywhere observable. Real
	# peer ids are non-negative, so every negative id the endpoint could have
	# used is disjoint from any real session; spot-check a plausible range.
	for synthetic_id in range(-1, -6, -1):
		assert_false(_gateway.is_authenticated(synthetic_id), "no synthetic session outlives the request (id %d)" % synthetic_id)


func test_wrong_password_and_unknown_username_return_same_bad_credentials_and_no_session() -> void:
	await _gateway.register(1, "bob", "hunter2222")
	_gateway.clear_session(1)

	var wrong_password_request: String = _build_request(JSON.stringify({"username": "bob", "password": "not-the-password"}))
	var wrong_password_response: Dictionary = await _raw_request(_endpoint.port, wrong_password_request)
	assert_eq(wrong_password_response["status_code"], 401, "wrong password is rejected")
	var wrong_password_body: Dictionary = JSON.parse_string(wrong_password_response["body"])
	assert_eq(wrong_password_body.get("outcome", ""), "bad_credentials", "wrong password reports bad_credentials")

	var unknown_user_request: String = _build_request(JSON.stringify({"username": "nobody-registered", "password": "whatever12"}))
	var unknown_user_response: Dictionary = await _raw_request(_endpoint.port, unknown_user_request)
	assert_eq(unknown_user_response["status_code"], 401, "unknown username is rejected")
	var unknown_user_body: Dictionary = JSON.parse_string(unknown_user_response["body"])
	assert_eq(unknown_user_body.get("outcome", ""), "bad_credentials", "unknown username reports the identical bad_credentials reason (no enumeration)")

	for synthetic_id in range(-1, -6, -1):
		assert_false(_gateway.is_authenticated(synthetic_id), "no synthetic session remains bound after a rejected attempt (id %d)" % synthetic_id)


func test_malformed_requests_are_bounded_rejections_and_the_listener_recovers() -> void:
	# Missing/empty JSON body.
	var empty_body_response: Dictionary = await _raw_request(_endpoint.port, _build_request(""))
	assert_ne(empty_body_response["status_code"], 200, "an empty body is rejected")
	assert_ne(empty_body_response["status_code"], -1, "the connection did not hang for an empty body")

	# Wrong Content-Type.
	var wrong_content_type_response: Dictionary = await _raw_request(_endpoint.port, _build_request(JSON.stringify({"username": "carol", "password": "s3cret1234"}), "text/plain"))
	assert_ne(wrong_content_type_response["status_code"], 200, "a non-JSON Content-Type is rejected")

	# Non-string field.
	var non_string_response: Dictionary = await _raw_request(_endpoint.port, _build_request(JSON.stringify({"username": 12345, "password": "s3cret1234"})))
	assert_ne(non_string_response["status_code"], 200, "a non-string username is rejected")

	# Unknown top-level key.
	var unknown_key_response: Dictionary = await _raw_request(_endpoint.port, _build_request(JSON.stringify({"username": "carol", "password": "s3cret1234", "extra": "nope"})))
	assert_ne(unknown_key_response["status_code"], 200, "an unknown top-level key is rejected")

	# Oversized body (over the 1 KiB cap).
	var oversized_password: String = "x".repeat(2000)
	var oversized_response: Dictionary = await _raw_request(_endpoint.port, _build_request(JSON.stringify({"username": "carol", "password": oversized_password})))
	assert_ne(oversized_response["status_code"], 200, "a body over the 1 KiB cap is rejected")

	# Wrong method.
	var wrong_method_response: Dictionary = await _raw_request(_endpoint.port, _build_request(JSON.stringify({"username": "carol", "password": "s3cret1234"}), "application/json", "", "GET"))
	assert_eq(wrong_method_response["status_code"], 405, "a non-POST method is rejected with a bounded 405")

	# Wrong path.
	var wrong_path_response: Dictionary = await _raw_request(_endpoint.port, _build_request(JSON.stringify({"username": "carol", "password": "s3cret1234"}), "application/json", "", "POST", "/nope"))
	assert_eq(wrong_path_response["status_code"], 404, "a non-matching path is rejected with a bounded 404")

	# The listener must still accept and correctly serve a fresh valid request afterward.
	await _gateway.register(1, "carol", "s3cret1234")
	_gateway.clear_session(1)
	var recovery_response: Dictionary = await _raw_request(_endpoint.port, _build_request(JSON.stringify({"username": "carol", "password": "s3cret1234"})))
	assert_eq(recovery_response["status_code"], 200, "the listener keeps accepting connections after a run of malformed requests")


## Slice 089: mints a valid account assertion by registering a peer, issuing an
## account assertion for its bound session, then clearing the session.
func _mint_assertion_for(peer_id: int, username: String, password: String) -> String:
	await _gateway.register(peer_id, username, password)
	var minted: Dictionary = _gateway.issue_account_assertion(peer_id, int(Time.get_unix_time_from_system()), 300)
	_gateway.clear_session(peer_id)
	return String(minted.get("assertion", ""))


func test_validate_valid_assertion_returns_account_and_expiry_and_binds_no_session() -> void:
	var token: String = await _mint_assertion_for(2, "dave", "s3cret1234")
	assert_true(token.length() > 0, "a token was minted for the test")

	var request: String = _build_request(JSON.stringify({"assertion": token}), "application/json", "", "POST", REQUEST_PATH_VALIDATE)
	var response: Dictionary = await _raw_request(_endpoint.port, request)

	assert_eq(response["status_code"], 200, "a valid assertion validates with 200")
	var body: Dictionary = JSON.parse_string(response["body"])
	assert_eq(body.get("outcome", ""), "ok", "outcome ok")
	assert_true(String(body.get("account_id", "")).length() > 0, "an account_id is returned")
	assert_true(int(body.get("expires_at", 0)) > 0, "an expires_at is returned")

	# The validate path binds NO session (unlike verify-and-mint): no synthetic id.
	for synthetic_id in range(-1, -6, -1):
		assert_false(_gateway.is_authenticated(synthetic_id), "validate binds no session (id %d)" % synthetic_id)


func test_validate_tampered_and_garbage_assertions_are_bounded_rejections() -> void:
	var token: String = await _mint_assertion_for(2, "erin", "s3cret1234")

	# Tamper the first payload byte so the recomputed HMAC no longer matches.
	var first: String = token.substr(0, 1)
	var replacement: String = "A" if first != "A" else "B"
	var tampered: String = replacement + token.substr(1)
	var tampered_response: Dictionary = await _raw_request(_endpoint.port, _build_request(JSON.stringify({"assertion": tampered}), "application/json", "", "POST", REQUEST_PATH_VALIDATE))
	assert_eq(tampered_response["status_code"], 401, "a tampered assertion is rejected")

	var garbage_response: Dictionary = await _raw_request(_endpoint.port, _build_request(JSON.stringify({"assertion": "not-a-real-token"}), "application/json", "", "POST", REQUEST_PATH_VALIDATE))
	assert_eq(garbage_response["status_code"], 401, "a malformed token is rejected")


func test_validate_malformed_request_is_rejected_and_listener_recovers() -> void:
	# Missing assertion key.
	var missing_response: Dictionary = await _raw_request(_endpoint.port, _build_request(JSON.stringify({"nope": "x"}), "application/json", "", "POST", REQUEST_PATH_VALIDATE))
	assert_ne(missing_response["status_code"], 200, "a request missing the assertion key is rejected")
	assert_ne(missing_response["status_code"], -1, "the connection did not hang")

	# Non-string assertion.
	var non_string_response: Dictionary = await _raw_request(_endpoint.port, _build_request(JSON.stringify({"assertion": 123}), "application/json", "", "POST", REQUEST_PATH_VALIDATE))
	assert_ne(non_string_response["status_code"], 200, "a non-string assertion is rejected")

	# The listener still serves a valid validate request afterward.
	var token: String = await _mint_assertion_for(2, "frank", "s3cret1234")
	var recovery: Dictionary = await _raw_request(_endpoint.port, _build_request(JSON.stringify({"assertion": token}), "application/json", "", "POST", REQUEST_PATH_VALIDATE))
	assert_eq(recovery["status_code"], 200, "the listener keeps serving validate after malformed requests")


func test_both_loopback_paths_coexist_on_one_listener() -> void:
	await _gateway.register(3, "grace", "s3cret1234")
	_gateway.clear_session(3)

	var mint_response: Dictionary = await _raw_request(_endpoint.port, _build_request(JSON.stringify({"username": "grace", "password": "s3cret1234"})))
	assert_eq(mint_response["status_code"], 200, "verify-and-mint still works")
	var minted_token: String = String(JSON.parse_string(mint_response["body"]).get("assertion", ""))

	var validate_response: Dictionary = await _raw_request(_endpoint.port, _build_request(JSON.stringify({"assertion": minted_token}), "application/json", "", "POST", REQUEST_PATH_VALIDATE))
	assert_eq(validate_response["status_code"], 200, "validate-assertion works on the same listener")


func test_gateway_validate_assertion_returns_claims_and_fails_closed() -> void:
	var token: String = await _mint_assertion_for(4, "heidi", "s3cret1234")
	var result: Dictionary = _gateway.validate_assertion(token, int(Time.get_unix_time_from_system()))
	assert_eq(result.get("outcome", ""), "ok", "validate_assertion accepts a good token")
	assert_true(result.has("claims"), "claims are returned")

	var bad: Dictionary = _gateway.validate_assertion("garbage", int(Time.get_unix_time_from_system()))
	assert_ne(bad.get("outcome", ""), "ok", "validate_assertion fails closed on a bad token")


## Slice 090: end-to-end character flow over the loopback endpoint — list (empty),
## create, select (mints a CHARACTER assertion), all account-scoped by the
## presented account assertion, leaving no synthetic session bound.
func test_characters_list_create_select_flow() -> void:
	var token: String = await _mint_assertion_for(2, "ivan", "s3cret1234")

	var list0: Dictionary = await _raw_request(_endpoint.port, _build_request(JSON.stringify({"assertion": token}), "application/json", "", "POST", REQUEST_PATH_CHAR_LIST))
	assert_eq(list0["status_code"], 200, "list returns 200")
	var list0_body: Dictionary = JSON.parse_string(list0["body"])
	assert_eq((list0_body.get("characters", []) as Array).size(), 0, "a new account has no characters")

	var create: Dictionary = await _raw_request(_endpoint.port, _build_request(JSON.stringify({"assertion": token, "name": "Ivan Hero", "cosmetic": {}}), "application/json", "", "POST", REQUEST_PATH_CHAR_CREATE))
	assert_eq(create["status_code"], 200, "create returns 200")
	var create_body: Dictionary = JSON.parse_string(create["body"])
	assert_eq(create_body.get("outcome", ""), "ok", "create ok")
	var character_id: String = String((create_body["character"] as Dictionary).get("character_id", ""))
	assert_true(character_id.length() > 0, "created character has an id")

	var select: Dictionary = await _raw_request(_endpoint.port, _build_request(JSON.stringify({"assertion": token, "character_id": character_id}), "application/json", "", "POST", REQUEST_PATH_CHAR_SELECT))
	assert_eq(select["status_code"], 200, "select returns 200")
	var select_body: Dictionary = JSON.parse_string(select["body"])
	assert_eq(select_body.get("outcome", ""), "ok", "select ok")
	var char_assertion: String = String(select_body.get("assertion", ""))
	assert_true(char_assertion.length() > 0, "a character assertion is minted")

	var validated: Dictionary = _external_validator.validate(char_assertion, int(Time.get_unix_time_from_system()))
	assert_eq(validated["outcome"], "ok", "the character assertion validates")
	assert_eq(String((validated["claims"] as Dictionary).get("cid", "")), character_id, "it carries the selected character id")

	for synthetic_id in range(-1, -12, -1):
		assert_false(_gateway.is_authenticated(synthetic_id), "no synthetic session outlives a character op (id %d)" % synthetic_id)


func test_characters_reject_a_bad_account_assertion() -> void:
	var response: Dictionary = await _raw_request(_endpoint.port, _build_request(JSON.stringify({"assertion": "garbage"}), "application/json", "", "POST", REQUEST_PATH_CHAR_LIST))
	assert_eq(response["status_code"], 401, "a bad account assertion is rejected 401")


func test_characters_delete_removes_a_character() -> void:
	var token: String = await _mint_assertion_for(2, "judy", "s3cret1234")
	var create: Dictionary = await _raw_request(_endpoint.port, _build_request(JSON.stringify({"assertion": token, "name": "Judy Hero", "cosmetic": {}}), "application/json", "", "POST", REQUEST_PATH_CHAR_CREATE))
	var character_id: String = String((JSON.parse_string(create["body"])["character"] as Dictionary).get("character_id", ""))

	var deleted: Dictionary = await _raw_request(_endpoint.port, _build_request(JSON.stringify({"assertion": token, "character_id": character_id}), "application/json", "", "POST", REQUEST_PATH_CHAR_DELETE))
	assert_eq(deleted["status_code"], 200, "delete returns 200")
	assert_eq(JSON.parse_string(deleted["body"]).get("outcome", ""), "ok", "delete ok")

	var list_after: Dictionary = await _raw_request(_endpoint.port, _build_request(JSON.stringify({"assertion": token}), "application/json", "", "POST", REQUEST_PATH_CHAR_LIST))
	assert_eq((JSON.parse_string(list_after["body"]).get("characters", []) as Array).size(), 0, "the deleted character no longer lists")


func test_loopback_bind_is_hardcoded_to_127_0_0_1() -> void:
	assert_eq(LoginLoopbackHttpEndpointScript.BIND_ADDRESS, "127.0.0.1", "the endpoint's bind literal is hardcoded to loopback")

	# Even with a non-default PROJECT0_SERVER_BIND_ADDRESS override present in
	# the environment (the ENet login port's own configurable override) set to
	# an address that is NOT assigned to this host (TEST-NET-1, RFC 5737), a
	# fresh endpoint still binds and serves on 127.0.0.1 — it never reads that
	# variable. If a future change mistakenly wired this override in, binding
	# 192.0.2.1 would fail on this host (bound_port == -1) or, if it somehow
	# bound, 127.0.0.1 would no longer be reachable — either way this test
	# would fail, unlike an "0.0.0.0" override which would mask the regression.
	OS.set_environment("PROJECT0_SERVER_BIND_ADDRESS", "192.0.2.1")
	var override_endpoint: Node = LoginLoopbackHttpEndpointScript.new(_gateway)
	add_child_autofree(override_endpoint)
	var bound_port: int = override_endpoint.start()
	OS.unset_environment("PROJECT0_SERVER_BIND_ADDRESS")
	assert_ne(bound_port, -1, "the override endpoint still binds successfully on 127.0.0.1, proving it never reads the unrelated env override")

	await _gateway.register(1, "dora", "s3cret12345")
	_gateway.clear_session(1)
	var response: Dictionary = await _raw_request(bound_port, _build_request(JSON.stringify({"username": "dora", "password": "s3cret12345"})))
	assert_eq(response["status_code"], 200, "127.0.0.1 still reaches the endpoint regardless of the unrelated env override")
	override_endpoint.stop()


func test_synthetic_peer_id_never_collides_with_a_real_bound_session() -> void:
	await _gateway.register(42, "erin", "s3cret123456")
	assert_true(_gateway.is_authenticated(42), "the real ENet-style peer holds a bound session")

	await _gateway.register(1, "frank", "s3cret1234567")
	_gateway.clear_session(1)
	var request: String = _build_request(JSON.stringify({"username": "frank", "password": "s3cret1234567"}))
	var response: Dictionary = await _raw_request(_endpoint.port, request)
	assert_eq(response["status_code"], 200, "the loopback request succeeds independently")

	assert_true(_gateway.is_authenticated(42), "the real peer's session survives the loopback request's clear_session call untouched")
