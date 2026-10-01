extends SceneTree
## Experiment #1232 client: both roles are real authenticated actors. Send order
## is gated on the server's recorded receive sequence, never on client clocks.

const NetworkConfigScript: Script = preload("res://shared/network_config.gd")
const GameplayTestSessionScript: Script = preload("res://scripts/gameplay_test_session.gd")
const InteractionScript: Script = preload("res://shared/environmental_interaction_contract.gd")
const CanonEntityGuidScript: Script = preload("res://shared/canon_entity_guid.gd")
const HUB: String = "starting_town_hub"
const CONNECT_TIMEOUT_MSEC: int = 10000
const GATE_TIMEOUT_MSEC: int = 15000
const RESOLUTION_TIMEOUT_MSEC: int = 5000
const WITHHELD_WINDOW_MSEC: int = 1500

var _role: String = OS.get_environment("EXP1231_ROLE")
var _case: String = OS.get_environment("EXP1231_CASE")
var _received: Array[Dictionary] = []
var _result: Dictionary = {"role": OS.get_environment("EXP1231_ROLE"), "case": OS.get_environment("EXP1231_CASE"),
	"connected": false, "entered": false, "sends": [], "failure": null}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var network: Node = root.get_node("NetworkClient")
	var gameplay: Node = load("res://client/gameplay.tscn").instantiate()
	root.add_child(gameplay)
	current_scene = gameplay
	await process_frame
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
	network.environmental_interaction_resolution_received.connect(func(resolution: Dictionary) -> void: _received.append(resolution))
	if not await _until(func(observation: Dictionary) -> bool: return observation.get("bound", {}).has("actor") and observation.get("bound", {}).has("occluder")):
		_finish("bound_roles_timeout")
		return
	var first: String = "occluder" if _case == "order_b_first" else "actor"
	if _case == "retry_after_withheld_confirmation":
		await _run_retry_case(network)
		return
	if _role != first and not await _until(func(observation: Dictionary) -> bool: return _received_roles(observation).has(first)):
		_finish("receive_order_gate_timeout")
		return
	await _send(network, RESOLUTION_TIMEOUT_MSEC)
	_finish(null)


func _run_retry_case(network: Node) -> void:
	if _role == "actor":
		await _send(network, WITHHELD_WINDOW_MSEC)
		if not await _until(func(observation: Dictionary) -> bool: return _committed(observation)):
			_finish("commit_not_observed")
			return
		await _send(network, RESOLUTION_TIMEOUT_MSEC)
		_finish(null)
		return
	if not await _until(func(observation: Dictionary) -> bool: return observation.get("resolutions", []).size() >= 2):
		_finish("retry_not_observed")
		return
	await _send(network, RESOLUTION_TIMEOUT_MSEC)
	_finish(null)


func _send(network: Node, wait_msec: int) -> void:
	var guid: String = CanonEntityGuidScript.derive(HUB, CanonEntityGuidScript.ENTITY_CLASS_STRUCTURE, "gate_01")
	var intent: Dictionary = InteractionScript.build_intent(HUB, guid, InteractionScript.VERB_LOCK_PICK, 0, Vector3(0.0, 0.0, -1.0), 1)
	var before: int = _received.size()
	network.submit_environmental_interaction_intent(intent)
	var deadline: int = Time.get_ticks_msec() + wait_msec
	while _received.size() == before and Time.get_ticks_msec() < deadline:
		await process_frame
	_result["sends"].append({"client_seq": 1, "resolution": _received[before] if _received.size() > before else null})
	_write()


func _until(predicate: Callable) -> bool:
	var deadline: int = Time.get_ticks_msec() + GATE_TIMEOUT_MSEC
	while Time.get_ticks_msec() < deadline:
		var observation: Variant = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("EXP1231_OBSERVATION")))
		if observation is Dictionary and predicate.call(observation):
			return true
		await process_frame
	return false


static func _received_roles(observation: Dictionary) -> Array:
	return observation.get("received", []).map(func(entry: Dictionary) -> String: return String(entry.get("role", "")))


static func _committed(observation: Dictionary) -> bool:
	for record: Dictionary in observation.get("resolutions", []):
		if record.get("role") == "actor" and int(record.get("after", {}).get("revision", 0)) >= 1:
			return true
	return false


func _finish(failure: Variant) -> void:
	_result["failure"] = failure
	_write()
	quit(0)


func _write() -> void:
	var path: String = OS.get_environment("EXP1231_RESULT")
	var file: FileAccess = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		push_error("EXP1232 client result write failed: %s" % path)
		return
	file.store_string(JSON.stringify(_result, "\t"))
	file.close()
	DirAccess.rename_absolute(path + ".tmp", path)
