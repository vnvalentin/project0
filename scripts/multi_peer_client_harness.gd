extends SceneTree
## Slice 007 test-only client harness: a real second/third OS process that
## connects to the production server/server_main.gd exactly like a real
## client, drives one directional input continuously through the real
## production input path, and periodically writes its own observable
## public-seam state (connection status, own Player/NetworkedPlayer
## position, and every currently-spawned RemotePlayer_<peer_id> node's
## position) to a JSON state file. scripts/test_multi_peer_replication.gd (the
## orchestrator) polls that file instead of talking to this process over
## stdout, since Godot does not expose live stdout streaming from a process
## started with OS.create_process(). This harness has no assertions of its
## own — it is a faithful client instance, not a stub — all pass/fail
## decisions live in the orchestrator, which reads only the same public seam
## (NetworkClient.status, node positions in the scene tree) a real client
## exposes.
##
## CLI args (after `--`):
##   --state-file=<path>       required; where to write JSON state every tick.
##   --hold-input=<action>     optional; an input action to hold for the
##                             entire run (e.g. "move_back", "move_right").
##   --run-ticks=<n>           optional; physics ticks to run before exiting
##                             cleanly (disconnecting first). If omitted, runs
##                             until externally killed by the orchestrator
##                             (used to test disconnect cleanup on the *other*
##                             harness/observer).

const NetworkConfigScript: Script = preload("res://shared/network_config.gd")
const GameplayTestSessionScript: Script = preload("res://scripts/gameplay_test_session.gd")

var _state_file_path: String = ""
var _hold_input_action: String = ""
var _run_ticks: int = -1
var _gameplay_instance: Node3D
var _network_client: Node
var _startup_gate: String = ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_parse_args()
	if _state_file_path.is_empty():
		push_error("multi_peer_client_harness: --state-file= is required")
		quit(1)
		return

	while not _startup_gate.is_empty() and not FileAccess.file_exists(_startup_gate):
		await process_frame

	_network_client = root.get_node("NetworkClient")
	_gameplay_instance = load("res://client/gameplay.tscn").instantiate()
	root.add_child(_gameplay_instance)
	current_scene = _gameplay_instance
	await process_frame

	_network_client.connect_to_server(NetworkConfigScript.resolve_client_target_host(), NetworkConfigScript.SERVER_PORT)

	if not await GameplayTestSessionScript.enter_world(_network_client):
		push_error("Test client session admission failed")
		quit(1)
		return
	if not _hold_input_action.is_empty():
		Input.action_press(_hold_input_action)

	var ticks_run: int = 0
	while true:
		await physics_frame
		_write_state()
		ticks_run += 1
		if _run_ticks > 0 and ticks_run >= _run_ticks:
			break

	if not _hold_input_action.is_empty():
		Input.action_release(_hold_input_action)

	quit(0)


func _parse_args() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--state-file="):
			_state_file_path = argument.substr("--state-file=".length())
		elif argument.begins_with("--hold-input="):
			_hold_input_action = argument.substr("--hold-input=".length())
		elif argument.begins_with("--run-ticks="):
			_run_ticks = argument.substr("--run-ticks=".length()).to_int()
		elif argument.begins_with("--startup-gate="):
			_startup_gate = argument.substr("--startup-gate=".length())


## Writes this harness's currently observable public-seam state: connection
## status, own Player/NetworkedPlayer positions (if present), and every
## remote peer representation currently spawned under RemotePlayers, keyed by
## peer id. The orchestrator reads exactly this file — nothing here reaches
## into a private implementation detail unavailable to a real client.
func _write_state() -> void:
	var state: Dictionary = {
		"status": _network_client.status,
	}

	var player: Node3D = _gameplay_instance.get_node_or_null("Player")
	if player != null:
		state["player_position"] = _vector3_to_array(player.position)

	var networked_player: Node3D = _gameplay_instance.get_node_or_null("NetworkedPlayer")
	if networked_player != null:
		state["networked_player_position"] = _vector3_to_array(networked_player.position)

	var remote_players: Dictionary = {}
	var container: Node = _gameplay_instance.get_node_or_null("RemotePlayers")
	if container != null:
		for child: Node in container.get_children():
			remote_players[child.name] = _vector3_to_array(child.position)
	state["remote_players"] = remote_players

	var pending_path: String = _state_file_path + ".pending"
	var file: FileAccess = FileAccess.open(pending_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(state))
		file.close()
		var publish_error: Error = DirAccess.rename_absolute(pending_path, _state_file_path)
		if publish_error != OK:
			push_error("multi_peer_client_harness: state publication failed: %s" % error_string(publish_error))
			quit(1)
	else:
		push_error("multi_peer_client_harness: state file could not be opened")
		quit(1)


func _vector3_to_array(vector: Vector3) -> Array:
	return [vector.x, vector.y, vector.z]
