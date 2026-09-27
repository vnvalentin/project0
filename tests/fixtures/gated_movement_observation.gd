extends "res://scripts/test_multi_peer_replication.gd"

var _movement_reads: int = 0
var _released: bool = false
var _publication_started_msec: int = 0


func _initialize() -> void:
	_client_harness_script = "tests/fixtures/gated_peer_publication.gd"
	super._initialize()


func _read_state(path: String) -> Dictionary:
	if path == _state_file_a and FileAccess.file_exists(_movement_gate):
		_movement_reads += 1
		if _movement_reads == 1:
			_publication_started_msec = Time.get_ticks_msec()
			print("MOVEMENT_PUBLICATION_HELD ", JSON.stringify({"published": super._read_state(path), "unpublished": super._read_state(path + ".unpublished"), "a_alive": OS.is_process_running(_client_a_process_id)}))
		if not _released and OS.get_cmdline_user_args().has("--stop-observer-client"):
			_assert(OS.kill(_client_a_process_id) == OK, "owned observer client stops during movement")
			_released = true
		if not _released and not OS.get_cmdline_user_args().has("--never-release") and _movement_reads > 300:
			var gate: FileAccess = FileAccess.open(_movement_gate + ".publication", FileAccess.WRITE)
			_assert(gate != null, "owned publication gate opens")
			if gate != null:
				gate.close()
				_released = true
				print("MOVEMENT_PUBLICATION_RELEASE ", JSON.stringify({"a_reads": _movement_reads, "elapsed_msec": Time.get_ticks_msec() - _publication_started_msec, "a_alive": OS.is_process_running(_client_a_process_id), "unpublished": super._read_state(path + ".unpublished")}))
	return super._read_state(path)


func _cleanup_processes() -> void:
	print("MOVEMENT_PUBLICATION_FINAL ", JSON.stringify({"a_reads": _movement_reads, "released": _released, "published": super._read_state(_state_file_a), "unpublished": super._read_state(_state_file_a + ".unpublished")}))
	super._cleanup_processes()
	for path: String in [_movement_gate + ".publication", _state_file_a + ".unpublished", _state_file_a + ".unpublished.pending"]:
		if FileAccess.file_exists(path):
			_assert(DirAccess.remove_absolute(path) == OK, "owned publication fixture removed")