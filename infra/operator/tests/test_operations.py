from __future__ import annotations

import itertools

import pytest

from infra.operator.jobs import AuditLog, JobState
from infra.operator.operations import OperationsService
from infra.operator.services import UnknownServiceError
from infra.operator.tests.fakes import FakeServiceController


def _services() -> dict[str, tuple[str, str]]:
    return {
        "game-server": ("systemd", "project0-server"),
        "dashboard": ("docker", "project0-flow"),
    }


def _ops(controller: FakeServiceController) -> tuple[OperationsService, AuditLog]:
    audit = AuditLog()
    clock = itertools.count(1000).__next__  # deterministic monotonic timestamps
    ids = itertools.count(1)
    ops = OperationsService(_services(), controller, audit, clock=clock, id_factory=lambda: f"job-{next(ids)}")
    return ops, audit


def test_restart_systemd_service_succeeds_and_audits():
    controller = FakeServiceController(systemd_ok=True)
    ops, audit = _ops(controller)
    job = ops.restart("game-server", "alice")
    assert job.state is JobState.SUCCEEDED
    assert job.action == "restart"
    assert job.target == "game-server"
    assert job.operator == "alice"
    assert job.outcome == "ok"
    assert controller.calls == [("systemd", "project0-server")]
    assert [j.job_id for j in audit.recent()] == [job.job_id]


def test_restart_docker_service_uses_docker_controller():
    controller = FakeServiceController(docker_ok=True)
    ops, _ = _ops(controller)
    job = ops.restart("dashboard", "operator")
    assert job.state is JobState.SUCCEEDED
    assert controller.calls == [("docker", "project0-flow")]


def test_controller_failure_yields_failed_job_with_detail():
    controller = FakeServiceController(systemd_ok=False)
    ops, audit = _ops(controller)
    job = ops.restart("game-server", "operator")
    assert job.state is JobState.FAILED
    assert job.outcome == "failed"
    assert job.detail == "systemd boom"
    assert audit.recent()[-1].state is JobState.FAILED


def test_unknown_service_is_fail_closed_and_unaudited():
    controller = FakeServiceController()
    ops, audit = _ops(controller)
    with pytest.raises(UnknownServiceError):
        ops.restart("not-allowlisted", "operator")
    assert controller.calls == []
    assert audit.recent() == []


def test_recent_jobs_returns_completed_jobs_in_order():
    ops, _ = _ops(FakeServiceController())
    first = ops.restart("game-server", "operator")
    second = ops.restart("dashboard", "operator")
    assert [j.job_id for j in ops.recent_jobs()] == [first.job_id, second.job_id]
