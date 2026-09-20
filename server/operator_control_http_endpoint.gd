extends Node
class_name OperatorControlHttpEndpoint

const BIND_ADDRESS: String = "0.0.0.0"
const REQUEST_PATH: String = "/internal/control"
const MAX_REQUEST_BYTES: int = 8192

var _adapter: Object
var _server: TCPServer
var _port: int = -1

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
	if _server != null and _server.is_listening():
		_server.stop()

func _process(_delta: float) -> void:
	if _server == null or not _server.is_connection_available():
		return
	var connection: StreamPeerTCP = _server.take_connection()
	connection.poll()
	var available: int = mini(connection.get_available_bytes(), MAX_REQUEST_BYTES)
	if available <= 0:
		connection.disconnect_from_host()
		return
	var raw: PackedByteArray = connection.get_data(available)[1]
	var text: String = raw.get_string_from_utf8()
	var separator: int = text.find("\r\n\r\n")
	if separator < 0:
		_send(connection, 400, {"outcome": "rejected", "reason": "malformed_request"})
		return
	var head: PackedStringArray = text.left(separator).split("\r\n")
	var request_line: PackedStringArray = head[0].split(" ")
	var body: String = text.substr(separator + 4)
	if request_line.size() != 3 or request_line[0] != "POST" or request_line[1] != REQUEST_PATH:
		_send(connection, 404, {"outcome": "rejected", "reason": "not_found"})
		return
	var parsed: Variant = JSON.parse_string(body)
	if not (parsed is Dictionary):
		_send(connection, 400, {"outcome": "rejected", "reason": "malformed_request"})
		return
	var request: Dictionary = parsed
	var token: String = String(request.get("operator_token", ""))
	var result: Dictionary = _adapter.handle_request(token, request, int(Time.get_unix_time_from_system()))
	_send(connection, 200 if result.get("outcome") == "accepted" else 403, result)

func _send(connection: StreamPeerTCP, status: int, body: Dictionary) -> void:
	var payload: String = JSON.stringify(body)
	var response: String = "HTTP/1.1 %d\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" % [status, payload.to_utf8_buffer().size(), payload]
	connection.put_data(response.to_utf8_buffer())
	connection.disconnect_from_host()
