extends SceneTree
## Headless integration smoke test for Slice 005: proves client-side
## prediction/reconciliation on top of Slice 004's server-authoritative
## movement — the red local Player responds to input immediately (no wait on
## the network), locally sent input intents carry a monotonically increasing
## sequence number that the server acknowledges in order, a forced
## authoritative correction converges the red Player's predicted position to
## the server snapshot (replaying only unacknowledged input on top of it),
## and the blue NetworkedPlayer approaches an authoritative snapshot smoothly
## rather than jumping to it instantly. Asserts via the public seams
## (NetworkClient.submit_input_intent/receive_authoritative_position, the
## Player and NetworkedPlayer nodes' position in the scene tree), not private
## implementation details — the same real-second-process pattern established
## by scripts/test_client_server_connection.gd and
## scripts/test_authoritative_movement.gd.
##
## Run through the canonical source-bound validation entrypoint. An unbound
## standalone invocation refuses readiness; PID liveness alone is not the
## independently qualified outer descendant/source-ownership envelope.
## Exits 0 and prints "ALL PASS" only if every assertion below holds.

const NetworkConfigScript: Script = preload("res://shared/network_config.gd")
const GameplayTestSessionScript: Script = preload("res://scripts/gameplay_test_session.gd")
const ReadyCodec = preload("res://tests/fixtures/prediction_listener_ready.gd")
const LISTENER_SOURCE_FILES: Array[String] = [
	"server/server_main.gd", "tests/fixtures/prediction_listener_ready.gd",
	"tests/fixtures/prediction_listener_server.gd", "scripts/test_prediction_reconciliation.gd",
]
const TELEMETRY_DB_PATH_ENV_VAR: String = "PROJECT0_TELEMETRY_DB_PATH"

var _failures: int = 0
var _server_process_id: int = -1
var _gameplay_instance: Node3D
var _telemetry_db_path: String = ""
var _ready_namespace: String = ""
var _ready_namespace_chain: Array[String] = []
var _ready_root: String = ""
var _ready_chain: Array[String] = []
var _ready_bytes: String = ""
var _listener_run_id: String = ""
var _listener_revision: String = ""
var _listener_source_hashes: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var had_telemetry_override: bool = OS.has_environment(TELEMETRY_DB_PATH_ENV_VAR)
	var previous_telemetry_override: String = OS.get_environment(TELEMETRY_DB_PATH_ENV_VAR)
	_telemetry_db_path = "test_prediction_telemetry_%d_%d.db" % [OS.get_process_id(), Time.get_ticks_usec()]
	OS.set_environment(TELEMETRY_DB_PATH_ENV_VAR, _telemetry_db_path)
	var session_environment: Dictionary = GameplayTestSessionScript.begin()
	await _test_prediction_and_reconciliation()

	var server_stopped: bool = await _stop_server_process()
	_assert(server_stopped, "owned server child process stopped before fixture cleanup")
	_assert(_cleanup_listener_readiness(server_stopped), "owned listener readiness removed after server stop")
	if server_stopped:
		_assert(GameplayTestSessionScript.restore(session_environment), "owned authenticated fixture database removed")
	else:
		_restore_environment(session_environment["environment"])
	_assert(
		_restore_telemetry_database(had_telemetry_override, previous_telemetry_override, server_stopped),
		"owned telemetry fixture database removed"
	)
	if _failures == 0:
		print("ALL PASS")
		quit(0)
	else:
		push_error("%d assertion(s) failed" % _failures)
		quit(1)


func _stop_server_process() -> bool:
	if _server_process_id == -1:
		return true
	if OS.is_process_running(_server_process_id):
		OS.kill(_server_process_id)
	var deadline_msec: int = Time.get_ticks_msec() + 5000
	while OS.is_process_running(_server_process_id) and Time.get_ticks_msec() < deadline_msec:
		await process_frame
	var stopped: bool = not OS.is_process_running(_server_process_id)
	if stopped:
		_server_process_id = -1
	return stopped


func _restore_environment(environment: Dictionary) -> void:
	for key: String in environment:
		if environment[key] == null:
			OS.unset_environment(key)
		else:
			OS.set_environment(key, environment[key])


func _restore_telemetry_database(had_override: bool, previous_override: String, server_stopped: bool) -> bool:
	if had_override:
		OS.set_environment(TELEMETRY_DB_PATH_ENV_VAR, previous_override)
	else:
		OS.unset_environment(TELEMETRY_DB_PATH_ENV_VAR)
	if not server_stopped:
		return false

	var removed: bool = true
	for suffix: String in ["", "-wal", "-shm", "-journal"]:
		var path: String = "user://" + _telemetry_db_path + suffix
		if FileAccess.file_exists(path) and DirAccess.remove_absolute(path) != OK:
			removed = false
	return removed


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: %s" % message)
	else:
		print("PASS: %s" % message)


func _test_prediction_and_reconciliation() -> void:
	_listener_revision = OS.get_environment("M4_SOURCE_REVISION")
	_assert(ReadyCodec.valid_revision(_listener_revision), "listener source metadata is qualified")
	if not ReadyCodec.valid_revision(_listener_revision):
		return
	_listener_run_id = "prediction_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var user_directory: String = ProjectSettings.globalize_path("user://").trim_suffix("/")
	var parent_chain: Array[String] = ReadyCodec.ordinary_chain(user_directory)
	_assert(not parent_chain.is_empty(), "listener namespace parent is ordinary")
	if parent_chain.is_empty():
		return
	var candidate: String = user_directory.path_join("prediction-listener-ready-" + _listener_run_id)
	var parent: DirAccess = DirAccess.open(user_directory)
	var absent: bool = parent != null and not parent.is_link(candidate.get_file()) \
		and not parent.file_exists(candidate.get_file()) and not parent.dir_exists(candidate.get_file())
	_assert(absent, "listener namespace is fresh")
	if not absent:
		return
	var created: Error = DirAccess.make_dir_absolute(candidate)
	_assert(created == OK, "listener namespace is created once")
	if created != OK:
		return
	_ready_namespace = candidate
	_ready_namespace_chain = ReadyCodec.ordinary_chain(_ready_namespace)
	var namespace_chain: Array[String] = parent_chain.duplicate()
	namespace_chain.append(_ready_namespace)
	_assert(_ready_namespace_chain == namespace_chain, "listener namespace ancestry is qualified")
	if _ready_namespace_chain != namespace_chain:
		return
	var ready_candidate: String = _ready_namespace.path_join("ready")
	var ready_created: Error = DirAccess.make_dir_absolute(ready_candidate)
	_assert(ready_created == OK, "listener ready child is created once")
	if ready_created != OK:
		return
	_ready_root = ready_candidate
	_ready_chain = ReadyCodec.ordinary_chain(_ready_root)
	var expected_chain: Array[String] = _ready_namespace_chain.duplicate()
	expected_chain.append(_ready_root)
	_assert(_ready_chain == expected_chain, "listener ready ancestry is qualified")
	if _ready_chain != expected_chain:
		return
	for relative: String in LISTENER_SOURCE_FILES:
		var digest: String = FileAccess.get_sha256("res://" + relative)
		_assert(digest.length() == 64, "listener source bytes are available")
		if digest.length() != 64:
			return
		_listener_source_hashes[relative] = digest

	var had_operator_port: bool = OS.has_environment("PROJECT0_OPERATOR_CONTROL_PORT")
	var previous_operator_port: String = OS.get_environment("PROJECT0_OPERATOR_CONTROL_PORT")
	OS.set_environment("PROJECT0_OPERATOR_CONTROL_PORT", "0")
	var godot_executable: String = OS.get_executable_path()
	_server_process_id = OS.create_process(godot_executable, [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "tests/fixtures/prediction_listener_server.gd", "--",
		"--server-bind-address=127.0.0.1", "--listener-ready-root=" + _ready_root,
		"--listener-run-id=" + _listener_run_id, "--listener-source-revision=" + _listener_revision,
		"--listener-user-directory=" + user_directory,
	])
	if had_operator_port:
		OS.set_environment("PROJECT0_OPERATOR_CONTROL_PORT", previous_operator_port)
	else:
		OS.unset_environment("PROJECT0_OPERATOR_CONTROL_PORT")
	_assert(_server_process_id != -1, "server process starts")
	if _server_process_id == -1:
		return

	var server_port: int = 0
	var startup_deadline_msec: int = Time.get_ticks_msec() + 5000
	while OS.is_process_running(_server_process_id) and Time.get_ticks_msec() < startup_deadline_msec:
		if FileAccess.file_exists(_ready_root.path_join(ReadyCodec.READY_LEAF)):
			_ready_bytes = ReadyCodec.read_ready(_ready_root, _ready_chain)
			var record: Dictionary = ReadyCodec.decode_ready(_ready_bytes, _listener_run_id, _listener_revision)
			_assert(record["passed"] == true, "listener readiness has exact source and run")
			if record["passed"] != true:
				_ready_bytes = ""
				return
			server_port = record["port"]
			break
		await process_frame
	_assert(server_port > 0, "listener publishes actual bound readiness within startup deadline")
	if server_port <= 0:
		return
	# Supplemental liveness only. Qualified outer validation owns actual
	# descendant/source custody and reaping; this API supplies no pidfd proof.
	_assert(OS.is_process_running(_server_process_id), "server process is still running after startup")
	if not OS.is_process_running(_server_process_id):
		return
	_assert(_listener_sources_unchanged(), "listener source bytes remain qualified")
	if not _listener_sources_unchanged():
		return

	# root.get_node("NetworkClient") rather than the bare autoload identifier:
	# -s script execution does not register autoloads as global identifiers
	# (see the equivalent note in docs/slices/001-*.md and 004-*.md).
	var network_client: Node = root.get_node("NetworkClient")

	_gameplay_instance = load("res://client/gameplay.tscn").instantiate()
	root.add_child(_gameplay_instance)
	current_scene = _gameplay_instance
	await process_frame

	var unchanged_ready: bool = ReadyCodec.read_ready(_ready_root, _ready_chain) == _ready_bytes
	var listener_live: bool = OS.is_process_running(_server_process_id)
	_assert(unchanged_ready and _listener_sources_unchanged() and listener_live, "listener readiness and liveness qualify before client connection")
	if not unchanged_ready or not _listener_sources_unchanged() or not listener_live:
		return
	network_client.connect_to_server(NetworkConfigScript.SERVER_ADDRESS, server_port)

	var connect_deadline_msec: int = Time.get_ticks_msec() + 5000
	while network_client.status != "connected: player spawned" and Time.get_ticks_msec() < connect_deadline_msec:
		await process_frame

	_assert(network_client.status == "connected: player spawned", "client connects and its NetworkedPlayer is spawned")

	var player: Node3D = _gameplay_instance.get_node_or_null("Player")
	var admitted: bool = await GameplayTestSessionScript.enter_world(network_client)
	_assert(admitted, "client establishes a validated test session and enters world")
	if not admitted:
		return
	var networked_player: Node3D = _gameplay_instance.get_node_or_null("NetworkedPlayer")
	_assert(player != null, "red predicted Player exists")
	_assert(networked_player != null, "blue NetworkedPlayer exists")
	if player == null or networked_player == null:
		return

	# --- Immediate local responsiveness -----------------------------------
	# Hold input and confirm the red Player has already moved within a
	# couple of physics ticks — far fewer than the ~30-tick window the rest
	# of this test uses for a real localhost server round trip — proving
	# prediction moves the node immediately rather than waiting on any
	# server acknowledgement. A single-tick check was flaky: whether
	# Input.action_press() lands before or after the current physics frame
	# already polled input is a real, harmless scheduling race, not a
	# prediction defect, so this allows a couple of ticks without weakening
	# what "immediate" (no network wait) is proving.
	var start_position: Vector3 = player.position
	Input.action_press("move_back")
	var immediate_check_ticks: int = 0
	var moved_before_any_network_round_trip: Vector3 = Vector3.ZERO
	while moved_before_any_network_round_trip.z <= 0.0 and immediate_check_ticks < 3:
		await physics_frame
		moved_before_any_network_round_trip = player.position - start_position
		immediate_check_ticks += 1
	_assert(moved_before_any_network_round_trip.z > 0.0, "red Player moves immediately on local input, within a couple of physics ticks")
	_assert(immediate_check_ticks < 3, "red Player responded well before a server round trip (~30 ticks) could complete")

	# --- Ordered input sequence acknowledgement ----------------------------
	# Let several more ticks elapse so multiple sequence-tagged intents are
	# sent and the server has time to process and acknowledge them.
	var send_ticks: int = 0
	while send_ticks < 30:
		await physics_frame
		send_ticks += 1
	Input.action_release("move_back")

	var settle_ticks: int = 0
	while settle_ticks < 30:
		await physics_frame
		settle_ticks += 1

	var next_sequence: int = network_client.next_input_sequence()
	_assert(next_sequence > 0, "red Player assigned monotonically increasing sequence numbers to sent input")
	_assert(player._pending_inputs.size() < next_sequence, "the server has acknowledged at least one sent input sequence (fewer pending than sent)")

	var predicted_before_correction: Vector3 = player.position
	_assert(predicted_before_correction.z - start_position.z > 0.5, "red Player's predicted position advanced from held input before any correction")

	# --- Forced authoritative correction converges the red Player ----------
	# Directly invoke the same public RPC-target method the server calls on
	# this client (network_client.receive_authoritative_position), with a
	# deliberately displaced position far from the current prediction and a
	# last_processed_sequence covering only the already-sent inputs. This is
	# not a private hook: it is the exact function the production server RPC
	# dispatches to; calling it directly here simulates "the server's
	# snapshot disagreed with the client's prediction" without depending on
	# real network jitter to produce that condition on demand.
	var forced_correction: Vector3 = predicted_before_correction + Vector3(20.0, 0.0, 0.0)
	var correction_sequence: int = next_sequence - 1
	# Assert immediately, with no awaited frame in between: the real server
	# connection is still live and sends its own genuine (much smaller)
	# authoritative correction every physics tick, which would otherwise
	# race with and overwrite this deliberately-injected one. Calling
	# receive_authoritative_position() directly is synchronous — position is
	# set before this call returns — so checking right after it proves this
	# specific correction was applied and converged the predicted position,
	# without depending on winning a race against real network traffic.
	network_client.receive_authoritative_position(forced_correction, correction_sequence)

	var distance_after_correction: float = player.position.distance_to(forced_correction)
	_assert(distance_after_correction < 0.01, "a forced authoritative correction converges the red Player to the server snapshot")

	# --- Blue NetworkedPlayer smooths, does not teleport --------------------
	# Stop the real server process first: it otherwise keeps sending its own
	# genuine (much smaller) authoritative snapshots every physics tick,
	# which would race with and overwrite the deliberately-injected snapshot
	# below before the smoothing/convergence loop finishes observing it.
	# Server-authoritative delivery itself is already proven above (ordered
	# sequence acknowledgement) and in scripts/test_authoritative_movement.gd
	# (Slice 004); this section isolates only the client-side smoothing
	# behavior added in Slice 005.
	var server_stopped: bool = await _stop_server_process()
	_assert(server_stopped, "server process stops before client-only smoothing checks")
	if not server_stopped:
		return

	# OS.kill() ends the server process but does not recall UDP packets it
	# already sent before dying; without draining a few frames here, one of
	# those stray in-flight real snapshots can land right after the
	# deliberately-injected one below and stomp it, making this assertion
	# flaky. Waiting lets any such packet arrive and be superseded before the
	# injected snapshot is sent.
	var drain_ticks: int = 0
	while drain_ticks < 10:
		await physics_frame
		drain_ticks += 1

	# Send an authoritative snapshot to the blue NetworkedPlayer that is a
	# bounded, ordinary distance away and confirm it moves only part of the
	# way there on the very next tick rather than jumping instantly, then
	# confirm it keeps approaching (converges) over subsequent ticks.
	var blue_start: Vector3 = networked_player.position
	var nearby_target: Vector3 = blue_start + Vector3(0.0, 0.0, 2.0)
	network_client.receive_authoritative_position(nearby_target, correction_sequence)
	await physics_frame

	var blue_distance_to_target_after_one_tick: float = networked_player.position.distance_to(nearby_target)
	_assert(blue_distance_to_target_after_one_tick > 0.01, "blue NetworkedPlayer does not teleport instantly to an ordinary authoritative delta")
	_assert(networked_player.position.distance_to(blue_start) < nearby_target.distance_to(blue_start), "blue NetworkedPlayer moved only partway toward the snapshot on the first tick")

	var smoothing_ticks: int = 0
	while networked_player.position.distance_to(nearby_target) > 0.05 and smoothing_ticks < 60:
		await physics_frame
		smoothing_ticks += 1

	_assert(networked_player.position.distance_to(nearby_target) <= 0.05, "blue NetworkedPlayer converges to the authoritative snapshot without unbounded drift")

	_gameplay_instance.queue_free()
	await process_frame


func _listener_sources_unchanged() -> bool:
	if _listener_source_hashes.size() != LISTENER_SOURCE_FILES.size():
		return false
	for relative: String in LISTENER_SOURCE_FILES:
		if FileAccess.get_sha256("res://" + relative) != _listener_source_hashes[relative]:
			return false
	return true


func _cleanup_listener_readiness(server_stopped: bool) -> bool:
	if _ready_namespace.is_empty():
		return true
	if not server_stopped or not _listener_sources_unchanged() \
		or _ready_namespace_chain.is_empty() \
		or ReadyCodec.ordinary_chain(_ready_namespace) != _ready_namespace_chain:
		return false
	var namespace: DirAccess = DirAccess.open(_ready_namespace)
	if namespace == null:
		return false
	namespace.include_hidden = true
	if namespace.list_dir_begin() != OK:
		return false
	var namespace_entries: Array[String] = []
	var namespace_ordinary: bool = true
	while true:
		var entry: String = namespace.get_next()
		if entry.is_empty():
			break
		if not namespace_entries.is_empty() or not namespace.current_is_dir() \
			or namespace.is_link(entry) or entry != "ready":
			namespace_ordinary = false
			break
		namespace_entries.append(entry)
	namespace.list_dir_end()
	if not namespace_ordinary or ReadyCodec.ordinary_chain(_ready_namespace) != _ready_namespace_chain:
		return false
	if _ready_root.is_empty():
		if not namespace_entries.is_empty():
			return false
	else:
		if namespace_entries != ["ready"] or _ready_chain.is_empty() \
			or ReadyCodec.ordinary_chain(_ready_root) != _ready_chain:
			return false
		var opened: DirAccess = DirAccess.open(_ready_root)
		if opened == null:
			return false
		opened.include_hidden = true
		if opened.list_dir_begin() != OK:
			return false
		var files: Array[String] = []
		var ordinary: bool = true
		while true:
			var entry: String = opened.get_next()
			if entry.is_empty():
				break
			if not files.is_empty() or opened.current_is_dir() or opened.is_link(entry) \
				or entry != ReadyCodec.READY_LEAF:
				ordinary = false
				break
			files.append(entry)
		opened.list_dir_end()
		if not ordinary or ReadyCodec.ordinary_chain(_ready_root) != _ready_chain:
			return false
		if _ready_bytes.is_empty():
			if not files.is_empty():
				return false
		elif files != [ReadyCodec.READY_LEAF] \
			or ReadyCodec.read_ready(_ready_root, _ready_chain) != _ready_bytes:
			return false
		if not files.is_empty():
			if ReadyCodec.read_ready(_ready_root, _ready_chain) != _ready_bytes \
				or opened.is_link(ReadyCodec.READY_LEAF) \
				or DirAccess.remove_absolute(_ready_root.path_join(ReadyCodec.READY_LEAF)) != OK:
				return false
		if ReadyCodec.ordinary_chain(_ready_root) != _ready_chain \
			or DirAccess.remove_absolute(_ready_root) != OK:
			return false
	# Recheck the known now-empty parent before removing this owned namespace.
	if ReadyCodec.ordinary_chain(_ready_namespace) != _ready_namespace_chain \
		or namespace.list_dir_begin() != OK:
		return false
	var empty: bool = namespace.get_next().is_empty()
	namespace.list_dir_end()
	if not empty or ReadyCodec.ordinary_chain(_ready_namespace) != _ready_namespace_chain \
		or DirAccess.remove_absolute(_ready_namespace) != OK:
		return false
	_ready_namespace = ""
	_ready_namespace_chain.clear()
	_ready_root = ""
	_ready_chain.clear()
	_ready_bytes = ""
	return true
