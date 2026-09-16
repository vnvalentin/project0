extends Node
class_name LoginLoopbackHttpEndpoint
## Slice 088: loopback-only HTTP/JSON endpoint on the login authority process
## (server/login_server_main.gd), the delegation seam the enrollment service's
## public `POST /login` (infra/enrollment/) calls into so it never touches an
## accounts database or PBKDF2 code itself (ADR 0004 sub-decisions 1 and 2).
##
## Uses the same TCPServer/StreamPeerTCP primitives as
## scripts/fake_ollama_http_server.gd, but — unlike that test-only fixture,
## which deliberately does not parse — this seam accepts input from a process
## that itself relays untrusted public traffic, so it implements a real
## strict, bounded HTTP/1.1 request parser: POST only, exact path match, a
## header-byte cap and a body-byte cap enforced before further reads, no
## chunked Transfer-Encoding, and a strict two-key JSON body.
##
## It adds NO new credential or signing logic: it calls the same LoginGateway
## instance server/login_server_main.gd already built via
## LoginRuntime.build_services() (gateway.login() -> AuthService.login(),
## PBKDF2 verify + session bind; gateway.issue_account_assertion() ->
## AssertionIssuer.issue(), HMAC signing).
##
## Session-binding mechanism: an HTTP request has no ENet peer, so each
## request synthesizes a per-request NEGATIVE peer_id (a monotonically
## decrementing counter starting at -1). Real ENet peer ids are always
## non-negative (server is 1, clients are positive), so the negative space is
## provably disjoint from any real connected peer's SessionRegistry entry —
## this is a hard safety requirement, not a convenience (see the slice
## record's Safety invariants: a positive counter could race a real peer's
## register/login RPC across the await points inside AuthService's off-thread
## PBKDF2 hashing). The synthetic session is unconditionally cleared
## (gateway.clear_session()) before the response is written, win or lose, so
## no synthetic session ever outlives one request.
##
## Bind address is hard-coded to the literal "127.0.0.1" — never resolved
## from NetworkConfig.resolve_server_bind_address() or any other override.
## The endpoint's entire safety argument depends on it never being reachable
## except from the same host (see docs/slices/088-auth-gated-onboarding-login-delegation.md).

const CharacterRecordScript: Script = preload("res://shared/character_record.gd")
const SessionAssertionScript: Script = preload("res://shared/session_assertion.gd")

## Hardcoded bind literal (see class doc) — deliberately not a NetworkConfig lookup.
const BIND_ADDRESS: String = "127.0.0.1"

const REQUEST_METHOD: String = "POST"
# Slice 088 path (verify credentials + mint an assertion) and Slice 089 path
# (validate an assertion, no session bound) served from the same listener.
const REQUEST_PATH_VERIFY: String = "/internal/verify-and-mint"
const REQUEST_PATH_REGISTER: String = "/internal/register"
const REQUEST_PATH_VALIDATE: String = "/internal/validate-assertion"
# Slice 090 (ADR 0005): account-scoped character endpoints. Each takes an
# account assertion, binds a synthetic negative-peer-id session via
# establish_session_from_assertion, runs the existing gateway character op,
# then clears the session — the same synthetic-session pattern as verify-and-mint.
const REQUEST_PATH_CHAR_LIST: String = "/internal/characters/list"
const REQUEST_PATH_CHAR_CREATE: String = "/internal/characters/create"
const REQUEST_PATH_CHAR_DELETE: String = "/internal/characters/delete"
const REQUEST_PATH_CHAR_SELECT: String = "/internal/characters/select"
const MAX_HEADER_BYTES: int = 8192
const MAX_BODY_BYTES: int = 1024
# Character create carries a cosmetic (up to MAX_COSMETIC_JSON_LEN) plus the
# account assertion, so its bound is larger than the 1 KiB credential bodies.
const MAX_CHAR_BODY_BYTES: int = 4096
## Not a const: a PackedByteArray constructor isn't a compile-time constant
## expression in GDScript 2.0. Value/behavior is identical to the intended
## const — bytes 13,10,13,10 ("\r\n\r\n") — and never reassigned after init.
var _header_body_separator: PackedByteArray = PackedByteArray([13, 10, 13, 10])

const OUTCOME_OK: String = "ok"
const OUTCOME_BAD_CREDENTIALS: String = "bad_credentials"
const OUTCOME_MALFORMED: String = "malformed"
const OUTCOME_UNAVAILABLE: String = "unavailable"

const ASSERTION_TTL_SECONDS: int = 300  # short-lived; consumed promptly by /redeem (Slice 089) and the game handoff (Slice 090)

## Set before calling start() to bind a specific port (production resolves this
## via NetworkConfig.resolve_login_http_port() at the call site). Left at the
## default 0, start() asks the OS for any free ephemeral port so parallel test
## runs never collide on a fixed port (mirrors scripts/fake_ollama_http_server.gd).
var bind_port: int = 0

## The actual bound port after a successful start(), or -1 before starting /
## on bind failure (mirrors scripts/fake_ollama_http_server.gd's `port`).
var port: int = -1

var _gateway: Object = null
var _tcp_server: TCPServer = null
var _pending_connection: StreamPeerTCP = null
var _next_synthetic_peer_id: int = -1

# Per-connection parse state, reset for each new connection.
var _read_buffer: PackedByteArray = PackedByteArray()
var _headers_parsed: bool = false
var _body_start_index: int = 0
var _content_length: int = -1
## Which accepted path the current request targeted (Slice 089 dual-path).
var _request_path: String = ""
## True once a complete request has been handed to _handle_complete_request()
## for the current _pending_connection, until that coroutine responds (or the
## connection is otherwise closed). Guards two hazards from the fact that
## gateway.login()/issue_account_assertion() await across frames: (1) extra
## bytes arriving mid-authentication re-triggering a second concurrent dispatch
## for the same buffered request, and (2) _pending_connection being freed and
## reassigned to a NEW connection before the in-flight coroutine responds,
## which would write a stale response onto the wrong socket. While true,
## _process() neither reads new bytes nor accepts a new connection (accepting
## only happens when _pending_connection is null, and it stays non-null for the
## whole dispatch) — it simply waits for the in-flight coroutine to respond.
var _request_dispatched: bool = false


func _init(gateway: Object) -> void:
	_gateway = gateway


## Public seam. Binds the hard-coded loopback address on `bind_port` (or an
## OS-assigned ephemeral port when left at the default 0). Returns the bound
## port, or -1 on bind failure. Never resolves an address override.
func start() -> int:
	_tcp_server = TCPServer.new()
	var listen_error: Error = _tcp_server.listen(bind_port, BIND_ADDRESS)
	if listen_error != OK:
		port = -1
		return -1
	port = _tcp_server.get_local_port()
	set_process(true)
	return port


## Public seam. Stops listening and drops any pending connection.
func stop() -> void:
	set_process(false)
	_pending_connection = null
	_reset_parse_state()
	if _tcp_server != null and _tcp_server.is_listening():
		_tcp_server.stop()


func _process(_delta: float) -> void:
	if _tcp_server == null or not _tcp_server.is_listening():
		return

	if _pending_connection == null and _tcp_server.is_connection_available():
		_pending_connection = _tcp_server.take_connection()
		_reset_parse_state()

	if _pending_connection == null:
		return

	if _request_dispatched:
		# A complete request is already being authenticated (awaiting the
		# gateway across frames); its own coroutine will respond and close
		# this connection. Ignore further bytes and never accept a new
		# connection until it does (see _request_dispatched's doc comment).
		return

	_pending_connection.poll()
	if _pending_connection.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_close_pending_connection()
		return

	var available: int = _pending_connection.get_available_bytes()
	if available <= 0:
		return

	var chunk: PackedByteArray = _pending_connection.get_data(available)[1]
	_read_buffer.append_array(chunk)

	if not _headers_parsed:
		_try_parse_headers()
		if not _headers_parsed:
			# Either still awaiting more header bytes under the cap, or a
			# bounded rejection was already written and reset connection state.
			return

	var body_bytes_so_far: int = _read_buffer.size() - _body_start_index
	if body_bytes_so_far < _content_length:
		return  # awaiting more body bytes

	_request_dispatched = true
	await _handle_complete_request()


## Parses the header block once "\r\n\r\n" is found, setting `_headers_parsed`
## true once concluded (successfully, or with a bounded rejection already
## written and the connection already reset — see `_reject`). Leaves
## `_headers_parsed` false while still awaiting more header bytes. Enforces
## MAX_HEADER_BYTES before the terminator is found so an attacker cannot force
## unbounded header buffering.
func _try_parse_headers() -> void:
	var separator_index: int = _find_subarray(_read_buffer, _header_body_separator)
	if separator_index == -1:
		if _read_buffer.size() > MAX_HEADER_BYTES:
			_headers_parsed = true
			_reject(400, OUTCOME_MALFORMED)
		return

	if separator_index > MAX_HEADER_BYTES:
		_headers_parsed = true
		_reject(400, OUTCOME_MALFORMED)
		return

	var header_text: String = _read_buffer.slice(0, separator_index).get_string_from_utf8()
	_body_start_index = separator_index + _header_body_separator.size()
	_headers_parsed = true

	var lines: PackedStringArray = header_text.split("\r\n")
	if lines.is_empty():
		_reject(400, OUTCOME_MALFORMED)
		return

	var request_line_parts: PackedStringArray = lines[0].split(" ")
	if request_line_parts.size() < 2:
		_reject(400, OUTCOME_MALFORMED)
		return

	var method: String = request_line_parts[0]
	var path: String = request_line_parts[1]

	var headers: Dictionary = {}
	for i in range(1, lines.size()):
		var line: String = lines[i]
		if line.is_empty():
			continue
		var colon_index: int = line.find(":")
		if colon_index == -1:
			continue
		var header_name: String = line.substr(0, colon_index).strip_edges().to_lower()
		var header_value: String = line.substr(colon_index + 1).strip_edges()
		headers[header_name] = header_value

	if headers.has("transfer-encoding"):
		_reject(400, OUTCOME_MALFORMED)
		return

	if method != REQUEST_METHOD:
		_reject(405, OUTCOME_MALFORMED)
		return

	if path != REQUEST_PATH_VERIFY and path != REQUEST_PATH_REGISTER and path != REQUEST_PATH_VALIDATE and not _is_character_path(path):
		_reject(404, OUTCOME_MALFORMED)
		return
	_request_path = path

	if String(headers.get("content-type", "")) != "application/json":
		_reject(400, OUTCOME_MALFORMED)
		return

	var content_length_raw: String = String(headers.get("content-length", ""))
	if not content_length_raw.is_valid_int():
		_reject(400, OUTCOME_MALFORMED)
		return
	var content_length: int = content_length_raw.to_int()
	var max_body: int = MAX_CHAR_BODY_BYTES if _is_character_path(path) else MAX_BODY_BYTES
	if content_length < 0 or content_length > max_body:
		_reject(400, OUTCOME_MALFORMED)
		return

	_content_length = content_length


func _is_character_path(path: String) -> bool:
	return (
		path == REQUEST_PATH_CHAR_LIST
		or path == REQUEST_PATH_CHAR_CREATE
		or path == REQUEST_PATH_CHAR_DELETE
		or path == REQUEST_PATH_CHAR_SELECT
	)


func _handle_complete_request() -> void:
	var body_bytes: PackedByteArray = _read_buffer.slice(_body_start_index, _body_start_index + _content_length)
	var body_text: String = body_bytes.get_string_from_utf8()

	var parsed: Variant = JSON.parse_string(body_text)
	if not (parsed is Dictionary):
		_reject(400, OUTCOME_MALFORMED)
		return

	var raw: Dictionary = parsed
	if _request_path == REQUEST_PATH_REGISTER:
		await _handle_register(raw)
		return
	if _request_path == REQUEST_PATH_VALIDATE:
		_handle_validate(raw)
		return
	if _request_path == REQUEST_PATH_CHAR_LIST:
		_handle_char_list(raw)
		return
	if _request_path == REQUEST_PATH_CHAR_CREATE:
		_handle_char_create(raw)
		return
	if _request_path == REQUEST_PATH_CHAR_DELETE:
		_handle_char_delete(raw)
		return
	if _request_path == REQUEST_PATH_CHAR_SELECT:
		_handle_char_select(raw)
		return
	await _handle_verify_and_mint(raw)


## Slice 090: validates the account assertion and binds a synthetic
## negative-peer-id session. Returns the peer_id on success, or 0 after writing
## a 401 rejection (0 is neither a real nor a synthetic peer id). Always paired
## with a clear_session by the caller once its op completes.
func _bind_synthetic_from_assertion(assertion: String) -> int:
	var peer_id: int = _next_synthetic_peer_id
	_next_synthetic_peer_id -= 1
	var established: Dictionary = _gateway.establish_session_from_assertion(peer_id, assertion, int(Time.get_unix_time_from_system()))
	if String(established.get("outcome", "")) != OUTCOME_OK:
		_gateway.clear_session(peer_id)
		_reject(401, String(established.get("outcome", OUTCOME_MALFORMED)))
		return 0
	return peer_id


## Extracts a required non-empty "assertion" plus exactly `extra_keys`; on any
## shape mismatch writes a 400 and returns "".
func _extract_assertion(raw: Dictionary, extra_keys: Array) -> String:
	if raw.size() != extra_keys.size() + 1 or not raw.has("assertion"):
		_reject(400, OUTCOME_MALFORMED)
		return ""
	for key: Variant in extra_keys:
		if not raw.has(key):
			_reject(400, OUTCOME_MALFORMED)
			return ""
	var assertion: Variant = raw["assertion"]
	if not (assertion is String) or (assertion as String).is_empty():
		_reject(400, OUTCOME_MALFORMED)
		return ""
	return assertion as String


## Slice 090: {assertion} -> the account's live Characters as wire dicts.
func _handle_char_list(raw: Dictionary) -> void:
	var assertion: String = _extract_assertion(raw, [])
	if assertion.is_empty():
		return
	var peer_id: int = _bind_synthetic_from_assertion(assertion)
	if peer_id == 0:
		return
	var result: Dictionary = _gateway.list_characters(peer_id)
	_gateway.clear_session(peer_id)
	var wire: Array = []
	for record: Object in result.get("characters", []):
		wire.append(record.to_wire_dict())
	_respond(200, "OK", {"outcome": OUTCOME_OK, "characters": wire})


## Slice 090: {assertion, name, cosmetic} -> create; 200 {outcome, character?}.
## A domain rejection (name taken/invalid/cap) is relayed with a valid-assertion
## 200 and its bounded outcome string; the public route maps it to a status.
func _handle_char_create(raw: Dictionary) -> void:
	var assertion: String = _extract_assertion(raw, ["name", "cosmetic"])
	if assertion.is_empty():
		return
	var name_value: Variant = raw["name"]
	var cosmetic_value: Variant = raw["cosmetic"]
	if not (name_value is String) or not (cosmetic_value is Dictionary):
		_reject(400, OUTCOME_MALFORMED)
		return
	var peer_id: int = _bind_synthetic_from_assertion(assertion)
	if peer_id == 0:
		return
	var result: Dictionary = _gateway.create_character(peer_id, name_value, cosmetic_value)
	_gateway.clear_session(peer_id)
	var outcome: String = String(result.get("outcome", ""))
	if outcome == OUTCOME_OK:
		_respond(200, "OK", {"outcome": OUTCOME_OK, "character": (result["character"] as Object).to_wire_dict()})
		return
	_respond(200, "OK", {"outcome": outcome})


## Slice 090: {assertion, character_id} -> soft-delete; 200 {outcome}.
func _handle_char_delete(raw: Dictionary) -> void:
	var assertion: String = _extract_assertion(raw, ["character_id"])
	if assertion.is_empty():
		return
	var character_id: Variant = raw["character_id"]
	if not (character_id is String):
		_reject(400, OUTCOME_MALFORMED)
		return
	var peer_id: int = _bind_synthetic_from_assertion(assertion)
	if peer_id == 0:
		return
	var result: Dictionary = _gateway.delete_character(peer_id, character_id)
	_gateway.clear_session(peer_id)
	_respond(200, "OK", {"outcome": String(result.get("outcome", ""))})


## Slice 090: {assertion, character_id} -> select then mint a CHARACTER
## assertion; 200 {outcome, assertion?}. This is the token the client presents
## to the game server for world entry.
func _handle_char_select(raw: Dictionary) -> void:
	var assertion: String = _extract_assertion(raw, ["character_id"])
	if assertion.is_empty():
		return
	var character_id: Variant = raw["character_id"]
	if not (character_id is String):
		_reject(400, OUTCOME_MALFORMED)
		return
	var peer_id: int = _bind_synthetic_from_assertion(assertion)
	if peer_id == 0:
		return
	var select_result: Dictionary = _gateway.select_character(peer_id, character_id)
	if String(select_result.get("outcome", "")) != OUTCOME_OK:
		_gateway.clear_session(peer_id)
		_respond(200, "OK", {"outcome": String(select_result.get("outcome", ""))})
		return
	var minted: Dictionary = _gateway.issue_character_assertion(peer_id, int(Time.get_unix_time_from_system()), ASSERTION_TTL_SECONDS)
	_gateway.clear_session(peer_id)
	if String(minted.get("outcome", "")) != OUTCOME_OK:
		_respond(200, "OK", {"outcome": String(minted.get("outcome", OUTCOME_UNAVAILABLE))})
		return
	_respond(200, "OK", {"outcome": OUTCOME_OK, "assertion": minted["assertion"]})


## Slice 088: {username, password} -> verify credentials, mint an assertion.
func _handle_verify_and_mint(raw: Dictionary) -> void:
	if raw.size() != 2 or not raw.has("username") or not raw.has("password"):
		_reject(400, OUTCOME_MALFORMED)
		return

	var username_raw: Variant = raw["username"]
	var password_raw: Variant = raw["password"]
	if not (username_raw is String) or (username_raw as String).is_empty():
		_reject(400, OUTCOME_MALFORMED)
		return
	if not (password_raw is String) or (password_raw as String).is_empty():
		_reject(400, OUTCOME_MALFORMED)
		return

	await _authenticate_and_respond(username_raw as String, password_raw as String)


func _handle_register(raw: Dictionary) -> void:
	if raw.size() != 2 or not raw.has("username") or not raw.has("password"):
		_reject(400, OUTCOME_MALFORMED)
		return
	var username_raw: Variant = raw["username"]
	var password_raw: Variant = raw["password"]
	if not (username_raw is String) or (username_raw as String).is_empty() or not (password_raw is String) or (password_raw as String).is_empty():
		_reject(400, OUTCOME_MALFORMED)
		return
	var synthetic_peer_id: int = _next_synthetic_peer_id
	_next_synthetic_peer_id -= 1
	var result: Dictionary = await _gateway.register(synthetic_peer_id, username_raw as String, password_raw as String)
	_gateway.clear_session(synthetic_peer_id)
	var outcome: String = String(result.get("outcome", OUTCOME_MALFORMED))
	if outcome != OUTCOME_OK:
		var status_code: int = 409 if outcome == CharacterRecordScript.REJECT_USERNAME_TAKEN else 400
		_reject(status_code, "username_taken" if status_code == 409 else outcome)
		return
	_respond(200, "OK", {"outcome": OUTCOME_OK, "account_id": String(result["account_id"]), "username": String(result["username"])})


## Slice 089: {assertion} -> validate (no session bound) -> account_id + expiry.
## Pure signature/claims check via LoginGateway.validate_assertion; unlike the
## verify-and-mint path there is no synthetic peer id and no SessionRegistry
## write, so nothing to clear.
func _handle_validate(raw: Dictionary) -> void:
	if raw.size() != 1 or not raw.has("assertion"):
		_reject(400, OUTCOME_MALFORMED)
		return
	var assertion_raw: Variant = raw["assertion"]
	if not (assertion_raw is String) or (assertion_raw as String).is_empty():
		_reject(400, OUTCOME_MALFORMED)
		return

	var now_unix: int = int(Time.get_unix_time_from_system())
	var result: Dictionary = _gateway.validate_assertion(assertion_raw as String, now_unix)
	if String(result.get("outcome", "")) != OUTCOME_OK:
		_reject(401, String(result.get("outcome", OUTCOME_MALFORMED)))
		return
	var claims: Dictionary = result["claims"]
	_respond(200, "OK", {
		"outcome": OUTCOME_OK,
		"account_id": String(claims[SessionAssertionScript.KEY_ACCOUNT_ID]),
		"expires_at": int(claims[SessionAssertionScript.KEY_EXPIRES_AT]),
	})


## Synthesizes a fresh negative peer_id, delegates to the shared LoginGateway,
## and unconditionally clears the synthetic session before writing the
## response — win or lose, no synthetic session outlives one request.
func _authenticate_and_respond(username: String, password: String) -> void:
	var synthetic_peer_id: int = _next_synthetic_peer_id
	_next_synthetic_peer_id -= 1

	var login_result: Dictionary = await _gateway.login(synthetic_peer_id, username, password)
	var login_outcome: String = String(login_result.get("outcome", ""))

	if login_outcome != OUTCOME_OK:
		_gateway.clear_session(synthetic_peer_id)
		if login_outcome == CharacterRecordScript.REJECT_BAD_CREDENTIALS:
			_reject(401, OUTCOME_BAD_CREDENTIALS)
		else:
			_reject(400, OUTCOME_MALFORMED)
		return

	var now_unix: int = int(Time.get_unix_time_from_system())
	var assertion_result: Dictionary = _gateway.issue_account_assertion(synthetic_peer_id, now_unix, ASSERTION_TTL_SECONDS)
	_gateway.clear_session(synthetic_peer_id)

	if String(assertion_result.get("outcome", "")) != OUTCOME_OK:
		_reject(503, OUTCOME_UNAVAILABLE)
		return

	_respond(200, "OK", {"outcome": OUTCOME_OK, "assertion": assertion_result["assertion"]})


func _reject(status_code: int, outcome: String) -> void:
	var status_text: String = "Bad Request"
	if status_code == 401:
		status_text = "Unauthorized"
	elif status_code == 404:
		status_text = "Not Found"
	elif status_code == 405:
		status_text = "Method Not Allowed"
	elif status_code == 503:
		status_text = "Service Unavailable"
	_respond(status_code, status_text, {"outcome": outcome})


func _respond(status_code: int, status_text: String, body: Dictionary) -> void:
	if _pending_connection == null:
		return
	var body_text: String = JSON.stringify(body)
	var body_bytes: PackedByteArray = body_text.to_utf8_buffer()
	var response_text: String = "HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" % [
		status_code, status_text, body_bytes.size(), body_text,
	]
	_pending_connection.put_data(response_text.to_utf8_buffer())
	_close_pending_connection()


func _close_pending_connection() -> void:
	if _pending_connection != null:
		_pending_connection.disconnect_from_host()
	_pending_connection = null
	_reset_parse_state()


func _reset_parse_state() -> void:
	_read_buffer = PackedByteArray()
	_headers_parsed = false
	_body_start_index = 0
	_content_length = -1
	_request_path = ""
	_request_dispatched = false


func _find_subarray(haystack: PackedByteArray, needle: PackedByteArray) -> int:
	if needle.is_empty() or haystack.size() < needle.size():
		return -1
	var last_start: int = haystack.size() - needle.size()
	for start in range(last_start + 1):
		var matched: bool = true
		for offset in range(needle.size()):
			if haystack[start + offset] != needle[offset]:
				matched = false
				break
		if matched:
			return start
	return -1
