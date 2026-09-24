extends SceneTree
## Headless integration smoke test for Slice 012: proves the real ENet RPC
## wiring end to end — a real client process submits a melee ActionIntent
## over the network via NetworkClient.submit_action_intent(), the real
## production server/server_main.gd resolves it authoritatively through
## ServerPlayerState's tick lifecycle, and the client receives back a real
## ActionResolution and (after the swing's WINDUP completes and the client is
## positioned in reach/arc of the server's target dummy) a real
## CombatEvent.HIT via NetworkClient.receive_combat_event. This exists
## because tests/integration/test_authoritative_melee_strike.gd (GUT) proves
## the server-side state machine and hit math directly in-process — Godot 4.3
## allows only one MultiplayerAPI peer per SceneTree, so GUT (itself a single
## process) cannot open a real ENet connection to a second real server
## process — and this script proves the RPC methods added to
## client/network_client.gd (receive_action_intent_on_server,
## receive_action_resolution, receive_combat_event) actually work over a real
## socket, matching the existing two-process pattern established by
## scripts/test_prediction_reconciliation.gd and
## scripts/test_multi_peer_replication.gd.
##
## Run with:
##   godot --headless --path . -s scripts/test_authoritative_melee_strike_e2e.gd
## Exits 0 and prints "ALL PASS" only if every assertion below holds.

const NetworkConfigScript: Script = preload("res://shared/network_config.gd")
const CombatContractsScript: Script = preload("res://shared/combat_contracts.gd")

var _failures: int = 0
var _server_process_id: int = -1
var _gameplay_instance: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_authoritative_melee_strike()

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


func _test_authoritative_melee_strike() -> void:
	# DT-006: this harness's hard-coded forward+left walk from START_POSITIONS[0]
	# (3,1,3) toward TARGET_DUMMY_POSITION (0,1,-2) predates Slice 030's town
	# collision — both points now sit inside the starting-town hub, so town
	# geometry deflects the walk before it reaches melee range. Set the E2E
	# isolation env var (inherited by the child process below) so the spawned
	# server skips injecting town collision, restoring the original flat-arena
	# path this harness was written against.
	OS.set_environment("PROJECT0_E2E_DISABLE_TOWN_COLLISION", "1")

	var godot_executable: String = OS.get_executable_path()
	_server_process_id = OS.create_process(godot_executable, [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "server/server_main.gd",
	])
	_assert(_server_process_id != -1, "server process starts")

	var startup_deadline_msec: int = Time.get_ticks_msec() + 5000
	while OS.is_process_running(_server_process_id) and Time.get_ticks_msec() < startup_deadline_msec:
		await process_frame
	_assert(OS.is_process_running(_server_process_id), "server process is still running after startup")

	var network_client: Node = root.get_node("NetworkClient")

	_gameplay_instance = load("res://client/gameplay.tscn").instantiate()
	root.add_child(_gameplay_instance)
	current_scene = _gameplay_instance
	await process_frame

	network_client.connect_to_server(NetworkConfigScript.SERVER_ADDRESS, NetworkConfigScript.resolve_server_port())

	var connect_deadline_msec: int = Time.get_ticks_msec() + 5000
	while network_client.status != "connected: player spawned" and Time.get_ticks_msec() < connect_deadline_msec:
		await process_frame
	_assert(network_client.status == "connected: player spawned", "client connects and its Player is spawned")

	var player: Node3D = _gameplay_instance.get_node_or_null("Player")
	_assert(player != null, "red predicted Player exists")
	if player == null:
		return

	# --- Move into reach of the server's stationary target dummy -----------
	# The server's first connected peer starts at one of START_POSITIONS
	# (server/server_main.gd); the target dummy sits at
	# TARGET_DUMMY_POSITION = (0, 1, -2) — beyond the Generic Sword's 2.0m
	# reach from every configured start slot. Hold forward+left movement
	# input (the same real WASD path Slice 004/005 already prove) one tick at
	# a time, stopping as soon as the red Player's own predicted position
	# (which tracks the server's authoritative position via reconciliation)
	# is within reach, so this does not depend on knowing which start slot
	# this run was assigned.
	var target_dummy_position: Vector3 = Vector3(0.0, 1.0, -2.0)
	Input.action_press("move_forward")
	Input.action_press("move_left")
	var move_ticks: int = 0
	while player.position.distance_to(target_dummy_position) > 1.5 and move_ticks < 300:
		await physics_frame
		move_ticks += 1
	Input.action_release("move_forward")
	Input.action_release("move_left")

	var settle_ticks: int = 0
	while settle_ticks < 15:
		await physics_frame
		settle_ticks += 1

	_assert(player.position.distance_to(target_dummy_position) < 2.0, "the red Player's predicted position is within melee reach of the target dummy before attacking (position: %s)" % player.position)

	# --- Submit a melee ActionIntent over the real RPC seam -----------------
	var resolution_received: Array = [false, "", ""]
	network_client.action_resolution_received.connect(
		func(sequence: int, result: String, rejection_reason: String, _server_tick: int) -> void:
			resolution_received[0] = true
			resolution_received[1] = result
			resolution_received[2] = rejection_reason
	)

	var combat_event_received: Array = [false, ""]
	network_client.combat_event_received.connect(
		func(kind: String, _attacker_peer_id: int, target_id: String, _impact_position: Vector3, _server_tick: int) -> void:
			if kind == CombatContractsScript.COMBAT_EVENT_HIT:
				combat_event_received[0] = true
				combat_event_received[1] = target_id
	)

	var aim_direction: Vector3 = (target_dummy_position - player.position)
	aim_direction.y = 0.0
	aim_direction = aim_direction.normalized()
	network_client.submit_action_intent(0, Engine.get_physics_frames(), CombatContractsScript.ACTION_KIND_MELEE_STRIKE, aim_direction)

	var resolution_wait_ticks: int = 0
	while not resolution_received[0] and resolution_wait_ticks < 60:
		await physics_frame
		resolution_wait_ticks += 1

	_assert(resolution_received[0], "the client receives a real authoritative ActionResolution over the network")
	_assert(resolution_received[1] == CombatContractsScript.RESULT_ACCEPTED, "the first melee intent from IDLE is accepted (got rejection reason: %s)" % resolution_received[2])

	# --- Wait through the full swing lifecycle for the hit confirmation -----
	var archetype: Object = CombatContractsScript.generic_sword_archetype()
	var lifecycle_wait_ticks: int = 0
	var max_lifecycle_ticks: int = (archetype.windup_ticks + archetype.active_ticks + archetype.recovery_ticks) + 60
	while not combat_event_received[0] and lifecycle_wait_ticks < max_lifecycle_ticks:
		await physics_frame
		lifecycle_wait_ticks += 1

	_assert(combat_event_received[0], "the client receives a real authoritative CombatEvent.HIT over the network")
	_assert(combat_event_received[1] == "target_dummy_0", "the confirmed hit names the server's stationary target dummy")

	_gameplay_instance.queue_free()
	await process_frame
