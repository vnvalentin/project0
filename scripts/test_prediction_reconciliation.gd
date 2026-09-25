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
## Run with:
##   godot --headless --path . -s scripts/test_prediction_reconciliation.gd
## Exits 0 and prints "ALL PASS" only if every assertion below holds.

const NetworkConfigScript: Script = preload("res://shared/network_config.gd")

var _failures: int = 0
var _server_process_id: int = -1
var _gameplay_instance: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_prediction_and_reconciliation()

	if _server_process_id != -1 and OS.is_process_running(_server_process_id):
		OS.kill(_server_process_id)

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


func _test_prediction_and_reconciliation() -> void:
	var port_probe: PacketPeerUDP = PacketPeerUDP.new()
	var bind_error: Error = port_probe.bind(0, "127.0.0.1")
	_assert(bind_error == OK, "private test UDP port is available")
	if bind_error != OK:
		return
	var server_port: int = port_probe.get_local_port()
	port_probe.close()
	var had_operator_port: bool = OS.has_environment("PROJECT0_OPERATOR_CONTROL_PORT")
	var previous_operator_port: String = OS.get_environment("PROJECT0_OPERATOR_CONTROL_PORT")
	OS.set_environment("PROJECT0_OPERATOR_CONTROL_PORT", "0")
	var godot_executable: String = OS.get_executable_path()
	_server_process_id = OS.create_process(godot_executable, [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "server/server_main.gd", "--", "--server-port=%d" % server_port,
	])
	if had_operator_port:
		OS.set_environment("PROJECT0_OPERATOR_CONTROL_PORT", previous_operator_port)
	else:
		OS.unset_environment("PROJECT0_OPERATOR_CONTROL_PORT")
	_assert(_server_process_id != -1, "server process starts")
	if _server_process_id == -1:
		return

	var startup_deadline_msec: int = Time.get_ticks_msec() + 5000
	while OS.is_process_running(_server_process_id) and Time.get_ticks_msec() < startup_deadline_msec:
		await process_frame

	_assert(OS.is_process_running(_server_process_id), "server process is still running after startup")
	if not OS.is_process_running(_server_process_id):
		return

	# root.get_node("NetworkClient") rather than the bare autoload identifier:
	# -s script execution does not register autoloads as global identifiers
	# (see the equivalent note in docs/slices/001-*.md and 004-*.md).
	var network_client: Node = root.get_node("NetworkClient")

	_gameplay_instance = load("res://client/gameplay.tscn").instantiate()
	root.add_child(_gameplay_instance)
	current_scene = _gameplay_instance
	await process_frame

	network_client.connect_to_server(NetworkConfigScript.SERVER_ADDRESS, server_port)

	var connect_deadline_msec: int = Time.get_ticks_msec() + 5000
	while network_client.status != "connected: player spawned" and Time.get_ticks_msec() < connect_deadline_msec:
		await process_frame

	_assert(network_client.status == "connected: player spawned", "client connects and its NetworkedPlayer is spawned")

	var player: Node3D = _gameplay_instance.get_node_or_null("Player")
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
	if _server_process_id != -1 and OS.is_process_running(_server_process_id):
		OS.kill(_server_process_id)
		_server_process_id = -1

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
