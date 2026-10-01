extends "res://scripts/exp1234_gate_return_experiment.gd"
## Experiment #1237 (okami side): #1234's reconnect and orderly-restart return
## cases on a LAN-bound owned server, with each client phase answered by two
## packaged Windows clients from the SETSUJOKU coordinator.
##   EXP1237_CLIENT_VERSION=... EXP1237_CLIENT_SHA256=... godot --headless --path . -s scripts/exp1237_return_experiment.gd

const Remote: Script = preload("res://scripts/exp1237_remote.gd")

var _remote_phases: Array[Dictionary] = []


func _experiment_id() -> int:
	return 1237


func _free_port() -> int:
	return Remote.free_lan_port()


func _apply_environment(values: Dictionary) -> Dictionary:
	return super(Remote.lan_environment(values))


func _run_case(case: Dictionary, timestamp_ms: int) -> Dictionary:
	_remote_phases.clear()
	return await super(case, timestamp_ms)


func _run_phase(phase: String, case_dir: String, observation: String, actor_token: String, occluder_token: String) -> void:
	_remote_phases.append(await Remote.publish_phase(self, phase, case_dir, observation, actor_token, occluder_token))


func _report_1234(case: Dictionary, timestamp_ms: int, server1: Variant, server2: Variant, results: Dictionary, lifecycle: Dictionary, runtime_errors: Array) -> Dictionary:
	var input: Dictionary = super(case, timestamp_ms, server1, server2, results, lifecycle, runtime_errors)
	input["experiment_id"] = 1237
	input["scenario"]["clients"] = "two packaged Windows clients (SETSUJOKU)"
	Remote.client_checks(input["case_assertions"], Callable(self, "_check"), results, _remote_phases, true)
	input["observations"]["lifecycle"]["remote_phases"] = _remote_phases.duplicate(true)
	return input
