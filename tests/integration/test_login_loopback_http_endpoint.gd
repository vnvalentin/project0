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
