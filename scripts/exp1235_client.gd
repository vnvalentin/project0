extends "res://scripts/exp1234_client.gd"
## Experiment #1235 client. Establish: the actor sends the unlock (the server
## crashes before any confirmation) and the second player leaves once the server
## barrier is published. Return: post_commit reuses #1234's open-and-traverse
## path; pre_commit proves the recovered gate is still locked.


func _run_case(network: Node) -> void:
	if _phase == "establish":
		network.authoritative_position_received.connect(func(position: Vector3, _sequence: int) -> void: _authoritative[0] = position)
		_result["phase"] = _phase
		if _role == "actor":
			await _send_verb(network, InteractionScript.VERB_LOCK_PICK, 1)
		elif not await _until(func(observation: Dictionary) -> bool: return observation.has("barrier")):
			_finish("barrier_not_observed")
			return
		_finish(null)
		return
	if _case != "pre_commit":
		await super(network)
		return
	network.authoritative_position_received.connect(func(position: Vector3, _sequence: int) -> void: _authoritative[0] = position)
	_result["phase"] = _phase
	if not await _until(func(observation: Dictionary) -> bool: return observation.get("reload_events", []).size() >= 2):
		_finish("reload_events_timeout")
		return
	if _role == "actor":
		_result["closed_gate_probe"] = await _move_forward(BLOCKED_PROBE_MSEC, -INF, FIRST_POSITION_TIMEOUT_MSEC)
		await _send_verb(network, InteractionScript.VERB_OPEN, 2)
	_finish(null)
