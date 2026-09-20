from infra.operator.control_contract import (
    AuditRecord,
    ControlAction,
    ControlOutcome,
    ControlRequest,
    ControlResult,
)


def test_request_accepts_bounded_catalog_and_scope() -> None:
    request = ControlRequest("req-1", ControlAction.RESTART, "project0-game", "operator", ("lifecycle",))
    assert request.validate() is None
    result = ControlResult(request.request_id, ControlOutcome.ACCEPTED, "already_running")
    audit = AuditRecord(request.request_id, request.operator_identity, request.action, request.target, result.outcome, 100, result.reason)
    assert result.idempotent is True
    assert audit.outcome is ControlOutcome.ACCEPTED


def test_request_rejects_unbounded_payload() -> None:
    request = ControlRequest("req-1", ControlAction.SET_DEGRADED, "game", "operator", payload=(("reason", "x" * 257),))
    assert request.validate() == "invalid payload"
