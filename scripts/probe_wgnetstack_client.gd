extends SceneTree
## One-off proof harness for Slice 032 (wgnetstack netstack bridge, S2): loads
## the real client/gameplay.tscn and connects through the real production
## NetworkClient/ENet path to whatever host/port is passed via --target-host=
## and --target-port=, so it can be pointed at the wgnetstack loopback bridge
## port instead of the server directly. Mirrors
## scripts/multi_peer_client_harness.gd's state-file-polling pattern exactly
## (run as its own OS process, status polled from an external orchestrator)
## since running the client connection inline inside one SceneTree script's
## own await-loop does not reach "connected: player spawned" in this Godot
## build/headless mode, matching the constraint already documented in
## scripts/test_client_server_connection.gd (one client per process). Not
## part of the delivered public seam — a throwaway validation script for this
## slice's acceptance evidence, kept until reviewed.
##
## Run with:
##   godot --headless --path . -s scripts/probe_wgnetstack_client.gd -- \
##     --target-host=127.0.0.1 --target-port=<bridge_port> \
##     --state-file=<path> --run-ticks=300

const NetworkConfigScript: Script = preload("res://shared/network_config.gd")

var _target_host: String = "127.0.0.1"
var _target_port: int = 9999
var _run_ticks: int = 300
var _state_file_path: String = ""
var _network_client: Node
var _gameplay_instance: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_parse_args()
	_network_client = root.get_node("NetworkClient")
	_gameplay_instance = load("res://client/gameplay.tscn").instantiate()
	root.add_child(_gameplay_instance)
	current_scene = _gameplay_instance
	await process_frame

	_network_client.connect_to_server(_target_host, _target_port)

	var ticks_run: int = 0
	while ticks_run < _run_ticks:
		await physics_frame
		ticks_run += 1
		_write_state()

	quit(0)


func _parse_args() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--target-host="):
			_target_host = argument.substr("--target-host=".length())
		elif argument.begins_with("--target-port="):
			_target_port = argument.substr("--target-port=".length()).to_int()
		elif argument.begins_with("--run-ticks="):
			_run_ticks = argument.substr("--run-ticks=".length()).to_int()
		elif argument.begins_with("--state-file="):
			_state_file_path = argument.substr("--state-file=".length())


func _write_state() -> void:
	if _state_file_path.is_empty():
		return
	var state: Dictionary = {"status": _network_client.status}
	var file: FileAccess = FileAccess.open(_state_file_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(state))
		file.close()
