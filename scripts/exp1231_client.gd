extends SceneTree
## Experiment #1231 client: a real authenticated NetworkClient. The occluder
## enters the world and idles; the actor submits one environmental intent and
## records the authoritative resolution it receives.

const NetworkConfigScript: Script = preload("res://shared/network_config.gd")
const GameplayTestSessionScript: Script = preload("res://scripts/gameplay_test_session.gd")
const InteractionScript: Script = preload("res://shared/environmental_interaction_contract.gd")
const CanonEntityGuidScript: Script = preload("res://shared/canon_entity_guid.gd")
const HUB: String = "starting_town_hub"
const CONNECT_TIMEOUT_MSEC: int = 10000
const BOUND_TIMEOUT_MSEC: int = 15000
const RESOLUTION_TIMEOUT_MSEC: int = 5000
const OCCLUDER_HOLD_MSEC: int = 60000

var _role: String = OS.get_environment("EXP1231_ROLE")
var _case: String = OS.get_environment("EXP1231_CASE")
var _result: Dictionary = {"role": OS.get_environment("EXP1231_ROLE"), "case": OS.get_environment("EXP1231_CASE"),
	"connected": false, "entered": false, "submitted": false, "resolution": null, "failure": null}


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
	if not (_role == "actor" and _case == "unbound_actor"):
		_result["entered"] = await GameplayTestSessionScript.enter_world(network)
		if not _result["entered"]:
			_finish("enter_world_failed")
			return
	_write()
	if _role == "occluder":
		deadline = Time.get_ticks_msec() + OCCLUDER_HOLD_MSEC
		while not FileAccess.file_exists(OS.get_environment("EXP1231_STOP")) and Time.get_ticks_msec() < deadline:
			await process_frame
		_finish(null)
		return
	if not await _wait_for_bound_roles():
		_finish("bound_roles_timeout")
		return
	var received: Array[Dictionary] = []
	network.environmental_interaction_resolution_received.connect(func(resolution: Dictionary) -> void: received.append(resolution))
	var intent: Dictionary = _case_intent()
	_result["intent"] = var_to_str(intent)
	network.submit_environmental_interaction_intent(intent)
	_result["submitted"] = true
	deadline = Time.get_ticks_msec() + RESOLUTION_TIMEOUT_MSEC
	while received.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	_result["resolution"] = received[0] if not received.is_empty() else null
	_finish(null)


func _wait_for_bound_roles() -> bool:
	var needed: Array = ["occluder"] if _case == "unbound_actor" else ["actor", "occluder"]
	var deadline: int = Time.get_ticks_msec() + BOUND_TIMEOUT_MSEC
	while Time.get_ticks_msec() < deadline:
		var observation: Variant = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("EXP1231_OBSERVATION")))
		if observation is Dictionary:
			var bound: Dictionary = observation.get("bound", {})
			if needed.all(func(role: String) -> bool: return bound.has(role)):
				return true
		await process_frame
	return false


func _case_intent() -> Dictionary:
	var target: String = "gate_01"
	if _case == "nonexistent_target":
		target = "exp1231_missing_gate"
	elif _case == "not_lockable_target":
		target = "tavern_01"
	var guid: String = CanonEntityGuidScript.derive(HUB, CanonEntityGuidScript.ENTITY_CLASS_STRUCTURE, target)
	var intent: Dictionary = InteractionScript.build_intent(HUB, guid, InteractionScript.VERB_LOCK_PICK, 0, Vector3(0.0, 0.0, -1.0), 1)
	if _case == "malformed_intent":
		intent["success"] = true
	elif _case == "wrong_owner":
		intent["actor_player_id"] = OS.get_environment("EXP1231_OCCLUDER_CID")
	return intent


func _finish(failure: Variant) -> void:
	_result["failure"] = failure
	_write()
	quit(0)


func _write() -> void:
	var path: String = OS.get_environment("EXP1231_RESULT")
	var file: FileAccess = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		push_error("EXP1231 client result write failed: %s" % path)
		return
	file.store_string(JSON.stringify(_result, "\t"))
	file.close()
	DirAccess.rename_absolute(path + ".tmp", path)
