extends "res://server/server_main.gd"
## Test-only startup. The base does not call this resolver before #1450's fix.

const ListenerReadyScript: Script = preload("res://tests/fixtures/prediction_listener_ready.gd")
const READY_ROOT_ARG: String = "--listener-ready-root="
const RUN_ARG: String = "--listener-run-id="
const SOURCE_ARG: String = "--listener-source-revision="
const USER_DIRECTORY_ARG: String = "--listener-user-directory="


func _resolve_server_port() -> int:
	return 0


func _start_server() -> void:
	var directory: String = _unique_argument(READY_ROOT_ARG)
	var run_id: String = _unique_argument(RUN_ARG)
	var revision: String = _unique_argument(SOURCE_ARG)
	var user_directory: String = _unique_argument(USER_DIRECTORY_ARG)
	var chain: Array[String] = ListenerReadyScript.ordinary_chain(directory)
	if not ListenerReadyScript.valid_run_id(run_id) or not ListenerReadyScript.valid_revision(revision) \
		or revision != OS.get_environment("M4_SOURCE_REVISION") or chain.is_empty() \
		or directory.get_file() != "ready" \
		or ProjectSettings.globalize_path("user://").trim_suffix("/") != user_directory \
		or ListenerReadyScript.ordinary_chain(user_directory).is_empty():
		quit(1)
		return
	print("1450_LISTENER_ERROR_BEGIN:occupied_default")
	await super._start_server()
	print("1450_LISTENER_ERROR_END:occupied_default")
	# A failed base quit remains pending with its original nonzero code.
	if _peer == null or _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED \
		or root.multiplayer.multiplayer_peer != _peer or _peer.get_host() == null:
		return
	var actual_port: int = _peer.get_host().get_local_port()
	var bytes: String = ListenerReadyScript.encode_ready(run_id, revision, actual_port)
	if bytes.is_empty() or not ListenerReadyScript.publish_ready(directory, chain, bytes):
		_peer.close()
		quit(1)
		return
	print("1450_LISTENER_READY")


func _unique_argument(prefix: String) -> String:
	var found: String = ""
	var count: int = 0
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			count += 1
			found = argument.substr(prefix.length())
	return found if count == 1 else ""
