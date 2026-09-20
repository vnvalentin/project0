extends GutTest

const AdapterScript: Script = preload("res://server/operator_control_adapter.gd")
const ServiceScript: Script = preload("res://server/operator_control_service.gd")

class FakeValidator:
	var result: Dictionary
	func _init(p_result: Dictionary) -> void:
		result = p_result
	func validate(_token: String, _now: int) -> Dictionary:
		return result

func test_adapter_rejects_invalid_assertion_before_dispatch() -> void:
	var service: RefCounted = ServiceScript.new()
	var adapter: RefCounted = AdapterScript.new(FakeValidator.new({"outcome": "bad_signature"}), service)
	var result: Dictionary = adapter.handle_request("bad", {"action": "drain", "target": "server"}, 100)
	assert_eq(result["outcome"], AdapterScript.OUTCOME_REJECTED)
	assert_eq(result["reason"], "operator_assertion_rejected")

func test_adapter_delegates_authorized_drain() -> void:
	var service: RefCounted = ServiceScript.new()
	var claims: Dictionary = {"outcome": "ok", "claims": {"aud": "project0-console", "aid": "operator", "scp": ["control"]}}
	var adapter: RefCounted = AdapterScript.new(FakeValidator.new(claims), service)
	var result: Dictionary = adapter.handle_request("valid", {"action": "drain", "target": "server", "payload": {"enabled": true}}, 100)
	assert_eq(result["outcome"], AdapterScript.OUTCOME_ACCEPTED)
	assert_eq(result["operator_identity"], "operator")
	assert_true(service.is_draining())

func test_adapter_rejects_unsupported_action() -> void:
	var service: RefCounted = ServiceScript.new()
	var claims: Dictionary = {"outcome": "ok", "claims": {"aud": "project0-console", "aid": "operator", "scp": ["control"]}}
	var adapter: RefCounted = AdapterScript.new(FakeValidator.new(claims), service)
	var result: Dictionary = adapter.handle_request("valid", {"action": "start", "target": "server"}, 100)
	assert_eq(result["outcome"], AdapterScript.OUTCOME_REJECTED)
	assert_eq(result["reason"], "unsupported_action")
