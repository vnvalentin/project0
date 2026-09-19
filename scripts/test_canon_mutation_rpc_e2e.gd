extends SceneTree
## Slice 097 (P-013): headless two-process smoke test proving the real ENet RPC
## wiring for Canon mutation intents end to end — a real client submits a
## CanonMutationIntent via NetworkClient.submit_canon_mutation_intent(), the real
## production server/server_main.gd resolves it through its live
## CanonMutationService, and the client receives back a real resolution via
## NetworkClient.receive_canon_mutation_resolution.
##
## Godot 4.3 allows only one MultiplayerAPI peer per SceneTree, so GUT cannot
## open a real socket to a second server process; this mirrors the existing
## two-process pattern (scripts/test_authoritative_melee_strike_e2e.gd et al).
## The harness peer is unauthenticated (no Character bound), so the round-trip
## resolves to `invalid_actor` — that still exercises both RPC directions and the
## server wiring. The accepted/target/idempotent outcome mapping is proven at the
## service seam in tests/integration/test_canon_mutation_service.gd.
##
## Run with:
##   godot --headless --path . -s scripts/test_canon_mutation_rpc_e2e.gd
## Exits 0 and prints "ALL PASS" only if every assertion below holds.

const NetworkConfigScript: Script = preload("res://shared/network_config.gd")
const CanonMutationIntentScript: Script = preload("res://shared/canon_mutation_intent.gd")
const CanonMutationServiceScript: Script = preload("res://server/canon_mutation_service.gd")

var _failures: int = 0
var _server_process_id: int = -1
var _gameplay_instance: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_canon_mutation_rpc_round_trip()

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


func _test_canon_mutation_rpc_round_trip() -> void:
	var godot_executable: String = OS.get_executable_path()
	_server_process_id = OS.create_process(godot_executable, [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "server/server_main.gd",
	])
	_assert(_server_process_id != -1, "server process starts")

	var startup_wait_ticks: int = 0
	while startup_wait_ticks < 60:
		await process_frame
		startup_wait_ticks += 1
	_assert(OS.is_process_running(_server_process_id), "server process is still running after startup")

	var network_client: Node = root.get_node("NetworkClient")

	_gameplay_instance = load("res://client/gameplay.tscn").instantiate()
	root.add_child(_gameplay_instance)
	current_scene = _gameplay_instance
	await process_frame

	network_client.connect_to_server(NetworkConfigScript.SERVER_ADDRESS, NetworkConfigScript.SERVER_PORT)

	var connect_waited_ticks: int = 0
	while not network_client.status.begins_with("connected") and connect_waited_ticks < 180:
		await process_frame
		connect_waited_ticks += 1
	_assert(network_client.status.begins_with("connected"), "client connects to the server")

	# Capture the authoritative resolution relayed back to this client.
	var resolution_received: Array = [false, {}]
	network_client.canon_mutation_resolution_received.connect(
		func(resolution: Dictionary) -> void:
			resolution_received[0] = true
			resolution_received[1] = resolution
	)

	# A well-formed intent against the canonical starting-town hub. The server
	# stamps the actor/event_id/tick; this client supplies none of them.
	var intent: Dictionary = CanonMutationIntentScript.build("sector-0-0", "structure-village_hall", "defeat_leader", 0, 1, {"leader": "baron"})
	network_client.submit_canon_mutation_intent(intent)

	var resolution_wait_ticks: int = 0
	while not resolution_received[0] and resolution_wait_ticks < 120:
		await process_frame
		resolution_wait_ticks += 1

	_assert(resolution_received[0], "the client receives a real authoritative mutation resolution over the network")
	var resolution: Dictionary = resolution_received[1]
	_assert(resolution.get("status") == CanonMutationServiceScript.STATUS_REJECTED, "the unauthenticated peer's mutation is rejected (status: %s)" % resolution.get("status"))
	_assert(resolution.get("reason") == CanonMutationServiceScript.REASON_INVALID_ACTOR, "rejection reason is invalid_actor for a peer with no bound Character (reason: %s)" % resolution.get("reason"))
	_assert(resolution.get("client_seq") == 1, "the resolution echoes the client's sequence")

	_gameplay_instance.queue_free()
	await process_frame
