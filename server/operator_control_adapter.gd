extends RefCounted
class_name OperatorControlAdapter

const OperatorControlServiceScript: Script = preload("res://server/operator_control_service.gd")

const OUTCOME_ACCEPTED: String = "accepted"
const OUTCOME_REJECTED: String = "rejected"

var _validator: Object
var _service: Object

func _init(validator: Object, service: Object) -> void:
	_validator = validator
	_service = service

func handle_request(token: String, request: Dictionary, now_unix: int) -> Dictionary:
	if _validator == null or _service == null:
		return _reject("adapter_unavailable")
	var validation: Dictionary = _validator.validate(token, now_unix)
	if validation.get("outcome") != "ok":
		return _reject("operator_assertion_rejected")
	var claims: Dictionary = validation.get("claims", {})
	if String(claims.get("aud", "")) != "project0-console":
		return _reject("wrong_operator_audience")
	var scopes: Variant = claims.get("scp", ["*"])
	if not (scopes is Array) or (not scopes.has("*") and not scopes.has("control")):
		return _reject("operator_scope_denied")
	var action: String = String(request.get("action", ""))
	if not ["kick_peer", "drain", "reload_tuning", "set_degraded"].has(action):
		return _reject("unsupported_action")
	var result: Dictionary = _service.apply(action, String(request.get("target", "")), request.get("payload", {}))
	result["operator_identity"] = String(claims.get("aid", ""))
	return result

func _reject(reason: String) -> Dictionary:
	return {"outcome": OUTCOME_REJECTED, "reason": reason, "idempotent": true}
