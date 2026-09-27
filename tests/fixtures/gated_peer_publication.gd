extends "res://scripts/multi_peer_client_harness.gd"


func _write_state() -> void:
	if _hold_input_action == "move_back" and FileAccess.file_exists(_movement_gate) and not FileAccess.file_exists(_movement_gate + ".publication"):
		var published_path: String = _state_file_path
		_state_file_path += ".unpublished"
		super._write_state()
		_state_file_path = published_path
		return
	super._write_state()