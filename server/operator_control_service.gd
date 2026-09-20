extends RefCounted
class_name OperatorControlService

const OUTCOME_ACCEPTED: String = "accepted"
const OUTCOME_REJECTED: String = "rejected"
const REASON_ALREADY_APPLIED: String = "already_applied"
const REASON_INVALID_TARGET: String = "invalid_target"

var _draining: bool = false
var _degraded: bool = false
var _degraded_reason: String = ""

func apply(action: String, target: String, payload: Dictionary = {}) -> Dictionary:
	if action == "drain":
		return _set_draining(bool(payload.get("enabled", true)))
	if action == "set_degraded":
		return _set_degraded(bool(payload.get("enabled", true)), String(payload.get("reason", "")))
	if action == "reload_tuning":
		return _accepted(action, target, "reload_requested")
	if action == "kick_peer":
		if not target.is_valid_int() or int(target) < 1:
			return _rejected(action, target, REASON_INVALID_TARGET)
		return _accepted(action, target, "kick_requested")
	return _rejected(action, target, "unsupported_action")

func is_draining() -> bool:
	return _draining

func is_degraded() -> bool:
	return _degraded

func degraded_reason() -> String:
	return _degraded_reason

func _set_draining(enabled: bool) -> Dictionary:
	if _draining == enabled:
		return _accepted("drain", "server", REASON_ALREADY_APPLIED)
	_draining = enabled
	return _accepted("drain", "server", "drain_enabled" if enabled else "drain_disabled")

func _set_degraded(enabled: bool, reason: String) -> Dictionary:
	if reason.length() > 160:
		return _rejected("set_degraded", "server", "reason_too_long")
	if _degraded == enabled and _degraded_reason == reason:
		return _accepted("set_degraded", "server", REASON_ALREADY_APPLIED)
	_degraded = enabled
	_degraded_reason = reason if enabled else ""
	return _accepted("set_degraded", "server", "degraded_enabled" if enabled else "degraded_disabled")

func _accepted(action: String, target: String, reason: String) -> Dictionary:
	return {"outcome": OUTCOME_ACCEPTED, "action": action, "target": target, "reason": reason, "idempotent": true}

func _rejected(action: String, target: String, reason: String) -> Dictionary:
	return {"outcome": OUTCOME_REJECTED, "action": action, "target": target, "reason": reason, "idempotent": true}
