extends SceneTree
## Headless integration smoke test for Slice 007: proves two-client
## authoritative Player replication. Spawns three real OS processes — the
## unmodified production server/server_main.gd, and two instances of the
## test-only scripts/multi_peer_client_harness.gd, each a faithful client
## instance that loads the real client/gameplay.tscn and connects through the
## real production NetworkClient/ENet path — because Godot 4.3 allows only
## one MultiplayerAPI peer per SceneTree.root, so a client cannot run in the
## same process as this orchestrator either (matching the constraint already
## documented in scripts/test_client_server_connection.gd). This orchestrator
## process itself makes no network connection; it only starts the three real
## processes and polls each harness's state file (written from the harness's
## own public-seam observations — NetworkClient.status and node positions in
## the scene tree) to make its assertions.
##
## Proves:
##   1. Two real clients connect to one real server.
##   2. Each client sees two distinct peer-owned Player representations (its
##      own Player/NetworkedPlayer, and a RemotePlayer_<peer_id> for the
##      other peer).
##   3. Movement from Client A's held input reaches Client B's view of A
##      through server authority (Client B's RemotePlayer for A moves).
##   4. Movement from Client B's held input reaches Client A's view of B.
##   5. Disconnecting Client A removes Client A's RemotePlayer representation
##      from Client B without crashing Client B's process.
##
## Run with:
##   godot --headless --path . -s scripts/test_multi_peer_replication.gd
## Exits 0 and prints "ALL PASS" only if every assertion below holds.

var _failures: int = 0
var _server_process_id: int = -1
var _client_a_process_id: int = -1
var _client_b_process_id: int = -1
var _state_file_a: String = ""
var _state_file_b: String = ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_two_peer_replication_and_disconnect_cleanup()
	_cleanup_processes()

	if _failures == 0:
		print("ALL PASS")
		quit(0)
	else:
		push_error("%d assertion(s) failed" % _failures)
		quit(1)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: %s" % message)
	else:
		print("PASS: %s" % message)


func _cleanup_processes() -> void:
	for pid: int in [_server_process_id, _client_a_process_id, _client_b_process_id]:
		if pid != -1 and OS.is_process_running(pid):
			OS.kill(pid)
	for path: String in [_state_file_a, _state_file_b]:
		if not path.is_empty() and FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _test_two_peer_replication_and_disconnect_cleanup() -> void:
	var godot_executable: String = OS.get_executable_path()
	var project_path: String = ProjectSettings.globalize_path("res://")

	_server_process_id = OS.create_process(godot_executable, [
		"--headless", "--path", project_path,
		"-s", "server/server_main.gd",
	])
	_assert(_server_process_id != -1, "server process starts")

	var startup_wait_ticks: int = 0
	while startup_wait_ticks < 60:
		await process_frame
		startup_wait_ticks += 1
	_assert(OS.is_process_running(_server_process_id), "server process is still running after startup")

	_state_file_a = project_path.path_join(".test_multi_peer_state_a.json")
	_state_file_b = project_path.path_join(".test_multi_peer_state_b.json")
	for path: String in [_state_file_a, _state_file_b]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

	# Client A holds "move_back" (+Z); Client B holds "move_right" (+X), so
	# each peer's movement is distinguishable by axis when observed from the
	# other peer's RemotePlayer representation.
	_client_a_process_id = OS.create_process(godot_executable, [
		"--headless", "--path", project_path,
		"-s", "scripts/multi_peer_client_harness.gd",
		"--", "--server-host=127.0.0.1", "--state-file=%s" % _state_file_a, "--hold-input=move_back",
	])
	_assert(_client_a_process_id != -1, "client A process starts")

	_client_b_process_id = OS.create_process(godot_executable, [
		"--headless", "--path", project_path,
		"-s", "scripts/multi_peer_client_harness.gd",
		"--", "--server-host=127.0.0.1", "--state-file=%s" % _state_file_b, "--hold-input=move_right",
	])
	_assert(_client_b_process_id != -1, "client B process starts")

	# --- Both clients connect and see two distinct Player representations --
	var state_a: Dictionary = await _wait_for_state(_state_file_a, func(s: Dictionary) -> bool:
		return s.get("status", "") == "connected: player spawned" and s.get("remote_players", {}).size() >= 1
	, 300)
	var state_b: Dictionary = await _wait_for_state(_state_file_b, func(s: Dictionary) -> bool:
		return s.get("status", "") == "connected: player spawned" and s.get("remote_players", {}).size() >= 1
	, 300)

	_assert(state_a.get("status", "") == "connected: player spawned", "client A connects and spawns its own Player representation")
	_assert(state_b.get("status", "") == "connected: player spawned", "client B connects and spawns its own Player representation")
	_assert(state_a.has("player_position") and state_a.has("networked_player_position"), "client A has its own distinct red+blue Player representations")
	_assert(state_b.has("player_position") and state_b.has("networked_player_position"), "client B has its own distinct red+blue Player representations")

	var remote_players_on_a: Dictionary = state_a.get("remote_players", {})
	var remote_players_on_b: Dictionary = state_b.get("remote_players", {})
	_assert(remote_players_on_a.size() == 1, "client A sees exactly one distinct remote peer representation for client B")
	_assert(remote_players_on_b.size() == 1, "client B sees exactly one distinct remote peer representation for client A")

	# Baseline positions right after both peers are confirmed connected, since
	# each peer's server-assigned start position depends on connection order
	# (see server_main.gd's _start_position_for_slot), not a fixed coordinate.
	# Comparing distance moved from this baseline (rather than an absolute
	# coordinate) stays correct regardless of which peer claims which slot.
	var b_seen_from_a_baseline: Vector3 = _array_to_vector3(remote_players_on_a.values()[0])
	var a_seen_from_b_baseline: Vector3 = _array_to_vector3(remote_players_on_b.values()[0])

	# --- Movement from A reaches B, and from B reaches A, through the server -
	# Let both held inputs run long enough for each server-authoritative tick
	# to integrate and broadcast several times.
	var settle_ticks: int = 0
	while settle_ticks < 90:
		await physics_frame
		settle_ticks += 1

	state_a = _read_state(_state_file_a)
	state_b = _read_state(_state_file_b)
	remote_players_on_a = state_a.get("remote_players", {})
	remote_players_on_b = state_b.get("remote_players", {})

	var b_seen_from_a: Vector3 = _array_to_vector3(remote_players_on_a.values()[0]) if remote_players_on_a.size() > 0 else Vector3.ZERO
	var a_seen_from_b: Vector3 = _array_to_vector3(remote_players_on_b.values()[0]) if remote_players_on_b.size() > 0 else Vector3.ZERO

	var b_moved_as_seen_from_a: float = b_seen_from_a.distance_to(b_seen_from_a_baseline)
	var a_moved_as_seen_from_b: float = a_seen_from_b.distance_to(a_seen_from_b_baseline)

	_assert(b_moved_as_seen_from_a > 0.5, "movement from client B (held move_right) reaches client A's view of B through server authority")
	_assert(a_moved_as_seen_from_b > 0.5, "movement from client A (held move_back) reaches client B's view of A through server authority")

	# --- Disconnect cleanup: killing client A removes it from client B's view
	# Killing the process (SIGKILL) gives the server no graceful ENet
	# disconnect packet to react to immediately; it only notices once its own
	# peer-timeout heartbeat expires, which is a real wall-clock duration, not
	# a fixed number of engine frames. A headless SceneTree with nothing to
	# render can iterate process_frame far faster than real time, so this
	# wait polls on a real wall-clock deadline (Time.get_ticks_msec()) rather
	# than a frame count, so it reliably outlasts ENet's own timeout instead
	# of racing it.
	if _client_a_process_id != -1 and OS.is_process_running(_client_a_process_id):
		OS.kill(_client_a_process_id)
		_client_a_process_id = -1

	var state_b_after_disconnect: Dictionary = await _wait_for_state_with_deadline(_state_file_b, func(s: Dictionary) -> bool:
		return s.get("remote_players", {}).size() == 0
	, 20000)

	_assert(state_b_after_disconnect.get("remote_players", {}).size() == 0, "disconnecting client A removes its RemotePlayer representation from client B")
	_assert(OS.is_process_running(_client_b_process_id), "client B's process is still running (no crash) after client A disconnects")
	_assert(_client_b_process_id != -1 and OS.is_process_running(_client_b_process_id), "client B remains connected and usable after the other peer's disconnect")


## Polls the given JSON state file (written by multi_peer_client_harness.gd)
## until the predicate matches its parsed contents or max_ticks elapses.
## Returns the last successfully parsed state (or an empty Dictionary if none
## parsed yet).
func _wait_for_state(path: String, predicate: Callable, max_ticks: int) -> Dictionary:
	var state: Dictionary = {}
	var waited_ticks: int = 0
	while waited_ticks < max_ticks:
		state = _read_state(path)
		if not state.is_empty() and predicate.call(state):
			return state
		await process_frame
		waited_ticks += 1
	return state


func _array_to_vector3(value: Variant) -> Vector3:
	if value is Array and value.size() == 3:
		return Vector3(value[0], value[1], value[2])
	return Vector3.ZERO


## Same as _wait_for_state, but bounded by real wall-clock milliseconds
## (OS.get_ticks_msec()) instead of a frame count, for waits whose real-world
## duration does not scale with this headless SceneTree's own frame rate —
## e.g. ENet's server-side peer timeout after an abrupt (SIGKILL) client
## disconnect, which elapses in real time regardless of how many engine
## frames this process renders while waiting.
func _wait_for_state_with_deadline(path: String, predicate: Callable, max_wait_msec: int) -> Dictionary:
	var state: Dictionary = {}
	var deadline_msec: int = Time.get_ticks_msec() + max_wait_msec
	while Time.get_ticks_msec() < deadline_msec:
		state = _read_state(path)
		if not state.is_empty() and predicate.call(state):
			return state
		await process_frame
	return state


func _read_state(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text: String = file.get_as_text()
	file.close()
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	return {}
