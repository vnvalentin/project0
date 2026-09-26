extends "res://scripts/test_multi_peer_replication.gd"

var _observations: int = 0
var _released: bool = false
var _started_msec: int = 0
var _last_a: Dictionary = {}


func _initialize() -> void:
	_client_startup_gate = ProjectSettings.globalize_path("user://peer_start_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	_started_msec = Time.get_ticks_msec()
	super._initialize()


func _read_state(path: String) -> Dictionary:
	if path == _state_file_a:
		_observations += 1
	if not _released and OS.get_cmdline_user_args().has("--stop-client-before-ready") and _observations > 300:
		_assert(OS.kill(_client_a_process_id) == OK, "owned client stops before readiness")
		_released = true
	if not _released and not OS.get_cmdline_user_args().has("--never-release") and (_observations > 300 or path == _state_file_b):
		var gate: FileAccess = FileAccess.open(_client_startup_gate, FileAccess.WRITE)
		_assert(gate != null, "owned startup gate opens")
		if gate != null:
			gate.close()
			_released = true
			print("READINESS_RELEASE ", JSON.stringify({"a_reads": _observations, "elapsed_msec": Time.get_ticks_msec() - _started_msec, "a_alive": OS.is_process_running(_client_a_process_id)}))
	var state: Dictionary = super._read_state(path)
	if path == _state_file_a:
		_last_a = state
	return state


func _cleanup_processes() -> void:
	print("READINESS_FINAL ", JSON.stringify({"a_reads": _observations, "elapsed_msec": Time.get_ticks_msec() - _started_msec, "last_a": _last_a, "current_a": super._read_state(_state_file_a), "a_alive": _client_a_process_id > 0 and OS.is_process_running(_client_a_process_id), "b_alive": _client_b_process_id > 0 and OS.is_process_running(_client_b_process_id)}))
	if not OS.get_cmdline_user_args().has("--never-release"):
		_assert(_released, "delayed real client startup was released")
	super._cleanup_processes()
	if FileAccess.file_exists(_client_startup_gate):
		_assert(DirAccess.remove_absolute(_client_startup_gate) == OK, "owned startup gate removed")