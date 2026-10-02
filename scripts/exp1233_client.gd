extends "res://scripts/exp1232_client.gd"
## Experiment #1233 client. The actor's first request always fails (validation
## or rollback); later requests are gated on the server's resolution record.


func _run_case(network: Node) -> void:
	var retry: bool = _case == "rollback_then_same_actor_retry"
	if _role == "actor":
		await _send(network, RESOLUTION_TIMEOUT_MSEC)
		if retry:
			await _send(network, RESOLUTION_TIMEOUT_MSEC)
		_finish(null)
		return
	var needed: int = 2 if retry else 1
	if not await _until(func(observation: Dictionary) -> bool: return observation.get("resolutions", []).size() >= needed):
		_finish("prior_resolution_timeout")
		return
	await _send(network, RESOLUTION_TIMEOUT_MSEC)
	_finish(null)
