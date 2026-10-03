extends "res://scripts/test_multi_peer_replication.gd"

var _foreign_listener: PacketPeerUDP
var _observed_endpoints: Dictionary = {}


func _run() -> void:
	await super._run()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report-file="):
			var report_path: String = argument.substr("--report-file=".length())
			var paths_removed: bool = true
			for path: String in [_state_file_a, _state_file_b, _server_ready_file, _movement_gate]:
				paths_removed = paths_removed and not FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".pending")
			var output: FileAccess = FileAccess.open(report_path + ".pending", FileAccess.WRITE)
			if output == null:
				quit(1)
				return
			output.store_string(JSON.stringify({"failures": _failures, "endpoints": _observed_endpoints, "state_a": _state_file_a, "state_b": _state_file_b, "identity": _run_identity, "paths_removed": paths_removed}))
			output.close()
			if DirAccess.rename_absolute(report_path + ".pending", report_path) != OK:
				quit(1)


func _allocate_game_port() -> int:
	var port: int = super._allocate_game_port()
	if port > 0 and OS.get_cmdline_user_args().has("--occupy-selected-port"):
		_foreign_listener = PacketPeerUDP.new()
		var occupied: Error = _foreign_listener.bind(port, "127.0.0.1")
		_assert(occupied == OK, "controlled foreign listener owns the selected port before server bind")
		if occupied != OK:
			return -1
	return port


func _cleanup_processes() -> void:
	_observed_endpoints = _read_state(_server_ready_file)
	if _foreign_listener != null:
		print("HARNESS_COLLISION_PROBE ", JSON.stringify({"packets": _foreign_listener.get_available_packet_count(), "clients_started": _client_a_process_id != -1 or _client_b_process_id != -1}))
		_foreign_listener.close()
	super._cleanup_processes()