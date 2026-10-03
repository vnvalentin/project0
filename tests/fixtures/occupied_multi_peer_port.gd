extends "res://scripts/test_multi_peer_replication.gd"

var _foreign_listener: PacketPeerUDP
var _observed_endpoints: Dictionary = {}
var _owned_database: String = ""


func _publish_progress(phase: String) -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report-file="):
			var report_path: String = argument.substr("--report-file=".length())
			var output: FileAccess = FileAccess.open(report_path + ".pending", FileAccess.WRITE)
			if output == null:
				quit(1)
				return
			output.store_string(JSON.stringify({"phase": phase, "process_id": OS.get_process_id(), "children": [_server_process_id, _client_a_process_id, _client_b_process_id], "paths": [_state_file_a, _state_file_b, _server_ready_file, _movement_gate], "database": ProjectSettings.globalize_path("user://" + OS.get_environment("PROJECT0_ACCOUNTS_DB_PATH"))}))
			output.close()
			if DirAccess.rename_absolute(report_path + ".pending", report_path) != OK:
				quit(1)


func _wait_for_owned_server() -> bool:
	_publish_progress("starting")
	return await super._wait_for_owned_server()


func _wait_for_state_with_deadline(path: String, predicate: Callable, max_wait_msec: int, process_id: int) -> Dictionary:
	if OS.get_cmdline_user_args().has("--hold-owned-processes") and path == _state_file_a:
		_publish_progress("held")
		while true:
			await process_frame
	_publish_progress("observing")
	return await super._wait_for_state_with_deadline(path, predicate, max_wait_msec, process_id)


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
			output.store_string(JSON.stringify({"process_id": OS.get_process_id(), "children": [_server_process_id, _client_a_process_id, _client_b_process_id], "failures": _failures, "endpoints": _observed_endpoints, "state_a": _state_file_a, "state_b": _state_file_b, "identity": _run_identity, "paths_removed": paths_removed, "paths": [_state_file_a, _state_file_b, _server_ready_file, _movement_gate], "database": _owned_database}))
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
	_owned_database = ProjectSettings.globalize_path("user://" + OS.get_environment("PROJECT0_ACCOUNTS_DB_PATH"))
	if _foreign_listener != null:
		print("HARNESS_COLLISION_PROBE ", JSON.stringify({"packets": _foreign_listener.get_available_packet_count(), "clients_started": _client_a_process_id != -1 or _client_b_process_id != -1}))
		_foreign_listener.close()
	super._cleanup_processes()