extends Node
class_name OperatorControlHttpEndpoint

const BIND_ADDRESS: String = "0.0.0.0"
const REQUEST_PATH: String = "/internal/control"
const MAX_REQUEST_BYTES: int = 8192

var _adapter: Object
var _server: TCPServer
var _port: int = -1
var _pending_connection: StreamPeerTCP = null
var _buffer: PackedByteArray = PackedByteArray()

func _init(adapter: Object) -> void:
	_adapter = adapter

func start(port: int) -> int:
	_server = TCPServer.new()
	var error: Error = _server.listen(port, BIND_ADDRESS)
	if error != OK:
		return -1
	_port = _server.get_local_port()
	set_process(true)
	return _port

func stop() -> void:
	set_process(false)
	_pending_connection = null
	_buffer = PackedByteArray()
	if _server != null and _server.is_listening():
		_server.stop()

func _process(_delta: float) -> void:
	if _server == null:
		return
	if _pending_connection == null:
		if not _server.is_connection_available():
			return
		_pending_connection = _server.take_connection()
		_buffer = PackedByteArray()
	var connection: StreamPeerTCP = _pending_connection
	connection.poll()
	if connection.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_pending_connection = null
		_buffer = PackedByteArray()
		return
	var available: int = connection.get_available_bytes()
	if available > 0:
		_buffer.append_array(connection.get_data(mini(available, MAX_REQUEST_BYTES - _buffer.size()))[1])
	if _buffer.size() > MAX_REQUEST_BYTES:
		_send_and_clear(connection, 413, {"outcome": "rejected", "reason": "request_too_large"})
		return
	var text: String = _buffer.get_string_from_utf8()
	var separator: int = text.find("\r\n\r\n")
	if separator < 0:
		return
	var head: PackedStringArray = text.left(separator).split("\r\n")
	var request_line: PackedStringArray = head[0].split(" ")
	if request_line.size() != 3 or request_line[0] != "POST" or request_line[1] != REQUEST_PATH:
		_send_and_clear(connection, 404, {"outcome": "rejected", "reason": "not_found"})
		return
	var content_length: int = _content_length(head)
	if content_length < 0 or content_length > MAX_REQUEST_BYTES:
		_send_and_clear(connection, 400, {"outcome": "rejected", "reason": "malformed_request"})
		return
	if _buffer.size() - (separator + 4) < content_length:
		return
	var body: String = text.substr(separator + 4, content_length)
	var parsed: Variant = JSON.parse_string(body)
	if not (parsed is Dictionary):
		_send_and_clear(connection, 400, {"outcome": "rejected", "reason": "malformed_request"})
		return
	var request: Dictionary = parsed
	var token: String = String(request.get("operator_token", ""))
	var result: Dictionary = _adapter.handle_request(token, request, int(Time.get_unix_time_from_system()))
	_send_and_clear(connection, 200 if result.get("outcome") == "accepted" else 403, result)

func _content_length(headers: PackedStringArray) -> int:
	for header: String in headers:
		var parts: PackedStringArray = header.split(":", false, 1)
		if parts.size() == 2 and parts[0].strip_edges().to_lower() == "content-length":
			var value: String = parts[1].strip_edges()
			return value.to_int() if value.is_valid_int() else -1
	return -1

func _send_and_clear(connection: StreamPeerTCP, status: int, body: Dictionary) -> void:
	var payload: String = JSON.stringify(body)
	var response: String = "HTTP/1.1 %d\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" % [status, payload.to_utf8_buffer().size(), payload]
	connection.put_data(response.to_utf8_buffer())
	connection.disconnect_from_host()
	_pending_connection = null
	_buffer = PackedByteArray()
