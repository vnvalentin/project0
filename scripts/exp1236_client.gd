extends SceneTree
## Experiment #1236 client: a real authenticated NetworkClient. The observer
## keeps moving in the healthy hub until the stop file. The actor is admitted at
## the declared target position, records what the server sends about the
## target sector, then probes movement.

const NetworkConfigScript: Script = preload("res://shared/network_config.gd")
const GameplayTestSessionScript: Script = preload("res://scripts/gameplay_test_session.gd")
const TARGET: String = "sector-0-0"
const CONNECT_TIMEOUT_MSEC: int = 10000
const DECISION_TIMEOUT_MSEC: int = 10000
const PROBE_MSEC: int = 1500
const SETTLE_MSEC: int = 1000
const OBSERVER_MAX_MSEC: int = 120000
const OBSERVER_STRIDE_MSEC: int = 800

var _role: String = OS.get_environment("EXP1236_ROLE")
var _authoritative: Array = []
var _result: Dictionary = {"role": OS.get_environment("EXP1236_ROLE"), "phase": OS.get_environment("EXP1236_PHASE"),
	"connected": false, "entered": false, "denials": [], "blueprints": [], "failure": null}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var network: Node = root.get_node("NetworkClient")
	var gameplay: Node = load("res://client/gameplay.tscn").instantiate()
	root.add_child(gameplay)
	current_scene = gameplay
	await process_frame
	network.authoritative_position_received.connect(func(position: Vector3, _sequence: int) -> void: _authoritative.append([Time.get_ticks_msec(), position]))
	network.sector_entry_denied.connect(func(denial: Dictionary) -> void: _result["denials"].append({"msec": Time.get_ticks_msec(), "denial": denial}))
	network.sector_blueprint_received.connect(func(sector_id: String, outcome: String, tiles: int, structures: int) -> void: _result["blueprints"].append({"msec": Time.get_ticks_msec(), "sector_id": sector_id, "outcome": outcome, "tiles": tiles, "structures": structures}))
	network.connect_to_server(NetworkConfigScript.SERVER_ADDRESS, NetworkConfigScript.resolve_server_port())
	var deadline: int = Time.get_ticks_msec() + CONNECT_TIMEOUT_MSEC
	while network.status != "connected: player spawned" and Time.get_ticks_msec() < deadline:
		await process_frame
	_result["connected"] = network.status == "connected: player spawned"
	if not _result["connected"]:
		_finish("connect_timeout")
		return
	_result["entered"] = await GameplayTestSessionScript.enter_world(network)
	if not _result["entered"]:
		_finish("enter_world_failed")
		return
	_write()
	if _role == "observer":
		await _observe()
	else:
		await _enter_target()


func _observe() -> void:
	var started: int = Time.get_ticks_msec()
	var first_update: int = _authoritative.size()
	var direction: String = "move_right"
	var switch_at: int = started + OBSERVER_STRIDE_MSEC
	Input.action_press(direction)
	while not FileAccess.file_exists(OS.get_environment("EXP1236_STOP")) and Time.get_ticks_msec() - started < OBSERVER_MAX_MSEC:
		await physics_frame
		if Time.get_ticks_msec() >= switch_at:
			Input.action_release(direction)
			direction = "move_left" if direction == "move_right" else "move_right"
			Input.action_press(direction)
			switch_at = Time.get_ticks_msec() + OBSERVER_STRIDE_MSEC
	Input.action_release(direction)
	var updates: Array = _authoritative.slice(first_update)
	var max_gap: int = 0
	var path_length: float = 0.0
	for index: int in range(1, updates.size()):
		max_gap = maxi(max_gap, int(updates[index][0]) - int(updates[index - 1][0]))
		path_length += (updates[index][1] as Vector3).distance_to(updates[index - 1][1])
	_result["movement"] = {"duration_msec": Time.get_ticks_msec() - started, "updates": updates.size(),
		"max_gap_msec": max_gap if updates.size() > 1 else null, "path_length": path_length,
		"stopped_by_stop_file": FileAccess.file_exists(OS.get_environment("EXP1236_STOP"))}
	_finish(null)


func _enter_target() -> void:
	var deadline: int = Time.get_ticks_msec() + DECISION_TIMEOUT_MSEC
	while Time.get_ticks_msec() < deadline and _result["denials"].is_empty() and not _received_target_blueprint():
		await process_frame
	var start: Variant = _vec(_authoritative.back()[1]) if not _authoritative.is_empty() else null
	Input.action_press("move_forward")
	var probe_end: int = Time.get_ticks_msec() + PROBE_MSEC
	while Time.get_ticks_msec() < probe_end:
		await physics_frame
	Input.action_release("move_forward")
	var settle_end: int = Time.get_ticks_msec() + SETTLE_MSEC
	while Time.get_ticks_msec() < settle_end:
		await physics_frame
	_result["probe"] = {"start": start, "end": _vec(_authoritative.back()[1]) if not _authoritative.is_empty() else null,
		"updates": _authoritative.size()}
	_finish(null)


func _received_target_blueprint() -> bool:
	return _result["blueprints"].any(func(entry: Dictionary) -> bool: return entry["sector_id"] == TARGET)


func _finish(failure: Variant) -> void:
	_result["failure"] = failure
	_write()
	quit(0)


func _write() -> void:
	var path: String = OS.get_environment("EXP1236_RESULT")
	var file: FileAccess = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		push_error("EXP1236 client result write failed: %s" % path)
		return
	file.store_string(JSON.stringify(_result, "\t"))
	file.close()
	DirAccess.rename_absolute(path + ".tmp", path)


static func _vec(value: Vector3) -> Variant:
	return [value.x, value.y, value.z] if value.is_finite() else null
