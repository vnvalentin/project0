extends "res://scripts/exp1232_client.gd"
## Experiment #1234 client. Phase "establish": the actor unlocks the gate and both
## players leave after the commit. Phase "return": both players re-enter, wait for
## both Canon reloads, prove the gate is still closed, open it with the separate
## authoritative interaction, and walk through it.

const GATE_FACE_LIMIT_Z: float = -4.6
const TRAVERSED_Z: float = -6.5
const BLOCKED_PROBE_MSEC: int = 1500
const TRAVERSE_TIMEOUT_MSEC: int = 8000
## The closed-gate probe measures only after the server has reported a position.
const FIRST_POSITION_TIMEOUT_MSEC: int = 6000

var _phase: String = OS.get_environment("EXP1234_PHASE")
var _authoritative: Array[Vector3] = [Vector3.INF]


func _run_case(network: Node) -> void:
	network.authoritative_position_received.connect(func(position: Vector3, _sequence: int) -> void: _authoritative[0] = position)
	_result["phase"] = _phase
	if _phase == "establish":
		if _role == "actor":
			await _send_verb(network, InteractionScript.VERB_LOCK_PICK, 1)
		elif not await _until(func(observation: Dictionary) -> bool: return observation.has("expected_snapshot")):
			_finish("commit_not_observed")
			return
		_finish(null)
		return
	if not await _until(func(observation: Dictionary) -> bool: return observation.get("reload_events", []).size() >= 2):
		_finish("reload_events_timeout")
		return
	if _role == "actor":
		_result["closed_gate_probe"] = await _move_forward(BLOCKED_PROBE_MSEC, -INF, FIRST_POSITION_TIMEOUT_MSEC)
		await _send_verb(network, InteractionScript.VERB_OPEN, 2)
	else:
		if not await _until(func(observation: Dictionary) -> bool: return _opened_by_actor(observation)):
			_finish("actor_open_not_observed")
			return
		await _send_verb(network, InteractionScript.VERB_OPEN, 2)
	_result["traverse"] = await _move_forward(TRAVERSE_TIMEOUT_MSEC, TRAVERSED_Z)
	_finish(null)


func _send_verb(network: Node, verb: String, client_seq: int) -> void:
	var guid: String = CanonEntityGuidScript.derive(HUB, CanonEntityGuidScript.ENTITY_CLASS_STRUCTURE, "gate_01")
	var intent: Dictionary = InteractionScript.build_intent(HUB, guid, verb, 0, Vector3(0.0, 0.0, -1.0), client_seq)
	var before: int = _received.size()
	network.submit_environmental_interaction_intent(intent)
	var deadline: int = Time.get_ticks_msec() + RESOLUTION_TIMEOUT_MSEC
	while _received.size() == before and Time.get_ticks_msec() < deadline:
		await process_frame
	_result["sends"].append({"verb": verb, "client_seq": client_seq, "resolution": _received[before] if _received.size() > before else null})
	_write()


## Holds forward (-z) until the authoritative z reaches stop_z or the time runs out.
## With wait_first_msec, the duration starts at the first authoritative position.
func _move_forward(duration_msec: int, stop_z: float, wait_first_msec: int = 0) -> Dictionary:
	var start: Vector3 = _authoritative[0]
	var min_z: float = INF
	Input.action_press("move_forward")
	var first_wait_deadline: int = Time.get_ticks_msec() + wait_first_msec
	while wait_first_msec > 0 and not _authoritative[0].is_finite() and Time.get_ticks_msec() < first_wait_deadline:
		await physics_frame
	var first_position: Variant = _vec(_authoritative[0])
	var deadline: int = Time.get_ticks_msec() + duration_msec
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if _authoritative[0].is_finite():
			min_z = minf(min_z, _authoritative[0].z)
			if min_z <= stop_z:
				break
	Input.action_release("move_forward")
	for _tick: int in range(10):
		await physics_frame
	return {"start": _vec(start), "first_position": first_position, "end": _vec(_authoritative[0]), "min_z": min_z if is_finite(min_z) else null}


static func _opened_by_actor(observation: Dictionary) -> bool:
	for record: Dictionary in observation.get("resolutions", []):
		if record.get("role") == "actor" and (record.get("resolution") if record.get("resolution") is Dictionary else {}).get("reason") == "opened":
			return true
	return false


static func _vec(value: Vector3) -> Variant:
	return [value.x, value.y, value.z] if value.is_finite() else null
