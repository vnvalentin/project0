extends Node
class_name FakeOllamaHttpServer
## Minimal local HTTP test harness standing in for Ollama's /api/generate
## endpoint, so Slice 008's async request seam can be exercised against a
## real HTTPRequest/TCP round trip without requiring a live Ollama instance
## (per .scratch/game-vision/issues/15-sector-blueprint-contract.md's
## acceptance evidence: "A real or fixture-backed asynchronous public-seam
## test"). Test-only: not referenced by shared/local_llm_client.gd,
## server/sector_blueprint_service.gd, or any production path.
##
## Behavior is scripted per-test via `next_response_body` /
## `next_response_status` / `respond_at_all`, so callers can simulate a
## successful Ollama envelope, a malformed envelope, an HTTP error status, or
## (by setting respond_at_all = false) a hang that exercises
## LocalLLMClient's own request_timeout_sec bound.

var _tcp_server: TCPServer
var _pending_connection: StreamPeerTCP
var port: int = -1

## When true, every accepted connection is answered with
## next_response_status/next_response_body. When false, the connection is
## accepted but never written to, simulating an unresponsive server so the
## caller's own HTTPRequest.timeout is what ends the request.
var respond_at_all: bool = true
var next_response_status: int = 200
var next_response_body: String = "{}"


func start() -> int:
	_tcp_server = TCPServer.new()
	# Port 0 asks the OS for any free ephemeral port so parallel test runs
	# never collide on a fixed port.
	var listen_error: Error = _tcp_server.listen(0, "127.0.0.1")
	if listen_error != OK:
		return -1
	port = _tcp_server.get_local_port()
	set_process(true)
	return port


func stop() -> void:
	set_process(false)
	if _tcp_server != null and _tcp_server.is_listening():
		_tcp_server.stop()


func _process(_delta: float) -> void:
	if _tcp_server == null or not _tcp_server.is_listening():
		return
	if _tcp_server.is_connection_available():
		var connection: StreamPeerTCP = _tcp_server.take_connection()
		_pending_connection = connection

	if _pending_connection == null:
		return

	_pending_connection.poll()
	if _pending_connection.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	if _pending_connection.get_available_bytes() <= 0:
		return

	# Drain the request. A minimal HTTP/1.1 request/header block ends with
	# "\r\n\r\n"; this harness does not need to parse method/path/body since
	# every fixture test targets the same single fake endpoint.
	var _request_bytes: PackedByteArray = _pending_connection.get_data(_pending_connection.get_available_bytes())[1]

	if not respond_at_all:
		# Deliberately do not close or write; the connection stays open and
		# silent so the client's own HTTPRequest.timeout is the only thing
		# that ends the request. The harness's caller is responsible for
		# eventually calling stop() to release the socket.
		return

	var body_bytes: PackedByteArray = next_response_body.to_utf8_buffer()
	var status_text: String = "OK" if next_response_status == 200 else "Error"
	var response_text: String = "HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" % [
		next_response_status, status_text, body_bytes.size(), next_response_body,
	]
	_pending_connection.put_data(response_text.to_utf8_buffer())
	_pending_connection.disconnect_from_host()
	_pending_connection = null
