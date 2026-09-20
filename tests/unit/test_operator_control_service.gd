extends GutTest

const ControlServiceScript: Script = preload("res://server/operator_control_service.gd")

func test_drain_is_idempotent_and_stateful() -> void:
	var service: RefCounted = ControlServiceScript.new()
	var first: Dictionary = service.apply("drain", "server", {"enabled": true})
	var second: Dictionary = service.apply("drain", "server", {"enabled": true})
	assert_eq(first["outcome"], ControlServiceScript.OUTCOME_ACCEPTED)
	assert_eq(first["reason"], "drain_enabled")
	assert_eq(second["reason"], ControlServiceScript.REASON_ALREADY_APPLIED)
	assert_true(service.is_draining())

func test_degraded_reason_is_bounded_and_clears() -> void:
	var service: RefCounted = ControlServiceScript.new()
	var rejected: Dictionary = service.apply("set_degraded", "server", {"enabled": true, "reason": "x".repeat(161)})
	assert_eq(rejected["outcome"], ControlServiceScript.OUTCOME_REJECTED)
	service.apply("set_degraded", "server", {"enabled": true, "reason": "maintenance"})
	assert_true(service.is_degraded())
	service.apply("set_degraded", "server", {"enabled": false})
	assert_false(service.is_degraded())
	assert_eq(service.degraded_reason(), "")

func test_kick_peer_rejects_invalid_target() -> void:
	var service: RefCounted = ControlServiceScript.new()
	var result: Dictionary = service.apply("kick_peer", "not-a-peer")
	assert_eq(result["outcome"], ControlServiceScript.OUTCOME_REJECTED)
	assert_eq(result["reason"], ControlServiceScript.REASON_INVALID_TARGET)
