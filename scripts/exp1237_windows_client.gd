extends SceneTree
## Experiment #1237 packaged-client probe (SETSUJOKU). Runs in the Godot 4.7.2
## editor binary hosting the immutable package PCK. It authenticates with the
## private per-phase assertion and drives the real gameplay scene through
## physical key events (F = interact, W = move_forward), so the gate is
## unlocked/opened by the packaged LockedGate node and traversal goes through
## client prediction and server authority. Result fields match the headless
## #1234/#1235 client schema consumed by the okami oracles.
## User args: request.json role tokens.json observation.json result.json package.pck

const KEY_INTERACT: Key = KEY_F
const KEY_FORWARD: Key = KEY_W
const STEP_TIMEOUT_MSEC: int = 10000
const GATE_TIMEOUT_MSEC: int = 45000
const RESOLUTION_TIMEOUT_MSEC: int = 5000
const BLOCKED_PROBE_MSEC: int = 1500
const FIRST_POSITION_TIMEOUT_MSEC: int = 6000
const TRAVERSE_TIMEOUT_MSEC: int = 8000
const TRAVERSED_Z: float = -6.5

var _request: Dictionary = {}
var _role: String = ""
var _observation_path: String = ""
var _result_path: String = ""
var _network: Node
var _gameplay: Node3D
var _gate: Node
var _authoritative: Vector3 = Vector3.INF
var _received: Array[Dictionary] = []
var _result: Dictionary = {"client_mode": "godot-4.7.2-editor-hosting-package-pck", "connected": false, "entered": false,
	"sends": [], "geometry_ready": [], "failure": null}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.size() != 6:
		quit(2)
		return
	_request = JSON.parse_string(FileAccess.get_file_as_string(arguments[0])) if FileAccess.file_exists(arguments[0]) else {}
	_role = arguments[1]
	_observation_path = arguments[3]
	_result_path = arguments[4]
	_result.merge({"role": _role, "phase": _request.get("phase"), "case": _request.get("case"),
		"pck_sha256": FileAccess.get_sha256(arguments[5]), "client_version": load("res://shared/client_build_version.gd").CLIENT_BUILD_VERSION,
		"engine": Engine.get_version_info()["string"], "host": OS.get_environment("COMPUTERNAME")})
	var tokens: Variant = JSON.parse_string(FileAccess.get_file_as_string(arguments[2]))
	var token: String = String(tokens.get(_role, "")) if tokens is Dictionary else ""
	if _request.is_empty() or token.is_empty() or ClassDB.class_exists("SQLite"):
		await _finish("request, token or dependency boundary invalid")
		return
	_network = root.get_node_or_null("NetworkClient")
	_network.authoritative_position_received.connect(func(position: Vector3, _sequence: int) -> void: _authoritative = position)
	_network.environmental_interaction_resolution_received.connect(func(resolution: Dictionary) -> void: _received.append(resolution))
	_network.geometry_assembly_completed.connect(_on_geometry_assembly_completed)
	var session: Array[String] = []
	var world: Array[String] = []
	_network.session_established_received.connect(func(outcome: String) -> void: session.append(outcome))
	_network.world_entry_received.connect(func(outcome: String, _character: Dictionary) -> void: world.append(outcome))
	_gameplay = load("res://client/gameplay.tscn").instantiate() as Node3D
	root.add_child(_gameplay)
	current_scene = _gameplay
	_gate = _gameplay.get_node_or_null("LockedGate")
	_network.connect_to_server(String(_request["host"]), int(_request["port"]))
	if not await _wait(func() -> bool: return _network.status == "connected: player spawned", STEP_TIMEOUT_MSEC):
		await _finish("connect_timeout")
		return
	_result["connected"] = true
	_network.submit_present_assertion(token)
	if not await _wait(func() -> bool: return not session.is_empty(), STEP_TIMEOUT_MSEC) or session[0] != "ok":
		await _finish("session_rejected")
		return
	_network.submit_enter_world()
	if not await _wait(func() -> bool: return not world.is_empty(), STEP_TIMEOUT_MSEC) or world[0] != "ok":
		await _finish("enter_world_failed")
		return
	_result["entered"] = true
	_write()
	if not await _until(func(o: Dictionary) -> bool: return o.get("bound", {}).has("actor") and o.get("bound", {}).has("occluder")):
		await _finish("bound_roles_timeout")
		return
	if not await _wait(func() -> bool: return _result["geometry_ready"].has("starting_town_hub"), GATE_TIMEOUT_MSEC):
		await _finish("hub_geometry_not_ready")
		return
	if _request["phase"] == "establish":
		await _establish()
	else:
		await _return()


func _establish() -> void:
	if _role == "actor":
		await _press_interact(1)
	elif not await _until(func(o: Dictionary) -> bool: return o.has("barrier") if _request["case"] == "post_commit" else o.has("expected_snapshot")):
		await _finish("barrier_not_observed" if _request["case"] == "post_commit" else "commit_not_observed")
		return
	await _finish(null)


func _return() -> void:
	if not await _until(func(o: Dictionary) -> bool: return o.get("reload_events", []).size() >= 2):
		await _finish("reload_events_timeout")
		return
	_result["gate_unlocked_before_open"] = _gate.is_unlocked() if _gate != null else null
	_result["gate_opened_before_open"] = _gate.is_opened() if _gate != null else null
	if _role == "actor":
		_result["closed_gate_probe"] = await _move_forward(BLOCKED_PROBE_MSEC, -INF, FIRST_POSITION_TIMEOUT_MSEC)
	elif not await _until(func(o: Dictionary) -> bool: return _opened_by_actor(o)):
		await _finish("actor_open_not_observed")
		return
	await _press_interact(2)
	_result["gate_opened_after_open"] = _gate.is_opened() if _gate != null else null
	_result["traverse"] = await _move_forward(TRAVERSE_TIMEOUT_MSEC, TRAVERSED_Z)
	await _finish(null)


## Presses F through the input pipeline; the packaged LockedGate chooses and sends the verb.
func _press_interact(client_seq: int) -> void:
	var verb: String = "open" if _gate != null and _gate.is_unlocked() else "lock_pick"
	var before: int = _received.size()
	_key(KEY_INTERACT, true)
	await physics_frame
	await physics_frame
	_key(KEY_INTERACT, false)
	var deadline: int = Time.get_ticks_msec() + RESOLUTION_TIMEOUT_MSEC
	while _received.size() == before and Time.get_ticks_msec() < deadline:
		await process_frame
	_result["sends"].append({"verb": verb, "client_seq": client_seq, "resolution": _received[before] if _received.size() > before else null})
	_write()


## Holds W until the authoritative z reaches stop_z or the time runs out.
func _move_forward(duration_msec: int, stop_z: float, wait_first_msec: int = 0) -> Dictionary:
	var start: Vector3 = _authoritative
	var min_z: float = INF
	_key(KEY_FORWARD, true)
	var first_deadline: int = Time.get_ticks_msec() + wait_first_msec
	while wait_first_msec > 0 and not _authoritative.is_finite() and Time.get_ticks_msec() < first_deadline:
		await physics_frame
	var first_position: Variant = _vec(_authoritative)
	var deadline: int = Time.get_ticks_msec() + duration_msec
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if _authoritative.is_finite():
			min_z = minf(min_z, _authoritative.z)
			if min_z <= stop_z:
				break
	_key(KEY_FORWARD, false)
	for _tick: int in range(10):
		await physics_frame
	return {"start": _vec(start), "first_position": first_position, "end": _vec(_authoritative), "min_z": min_z if is_finite(min_z) else null}


func _key(physical: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = physical
	event.pressed = pressed
	Input.parse_input_event(event)


func _until(predicate: Callable) -> bool:
	var deadline: int = Time.get_ticks_msec() + GATE_TIMEOUT_MSEC
	while Time.get_ticks_msec() < deadline:
		var observation: Variant = JSON.parse_string(FileAccess.get_file_as_string(_observation_path)) if FileAccess.file_exists(_observation_path) else null
		if observation is Dictionary and predicate.call(observation):
			return true
		await process_frame
	return false


func _wait(condition: Callable, timeout_msec: int) -> bool:
	var deadline: int = Time.get_ticks_msec() + timeout_msec
	while not bool(condition.call()) and Time.get_ticks_msec() < deadline:
		await process_frame
	return bool(condition.call())


func _on_geometry_assembly_completed(sector_id: String, result: Dictionary) -> void:
	if result.get("outcome") == "valid" and not _result["geometry_ready"].has(sector_id):
		_result["geometry_ready"].append(sector_id)


static func _opened_by_actor(observation: Dictionary) -> bool:
	for record: Dictionary in observation.get("resolutions", []):
		if record.get("role") == "actor" and (record.get("resolution") if record.get("resolution") is Dictionary else {}).get("reason") == "opened":
			return true
	return false


func _finish(failure: Variant) -> void:
	_key(KEY_FORWARD, false)
	_result["failure"] = failure
	_write()
	if is_instance_valid(_network):
		_network.disconnect_from_server()
	await process_frame
	await process_frame
	quit(0 if failure == null else 1)


func _write() -> void:
	var file: FileAccess = FileAccess.open(_result_path + ".tmp", FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(_result, "\t"))
	file.close()
	DirAccess.rename_absolute(_result_path + ".tmp", _result_path)


static func _vec(value: Vector3) -> Variant:
	return [value.x, value.y, value.z] if value.is_finite() else null
