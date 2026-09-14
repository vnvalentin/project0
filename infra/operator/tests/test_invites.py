from __future__ import annotations

import itertools

from infra.operator.jobs import AuditLog, JobState
from infra.operator.operations import OperationsService
from infra.operator.tests.fakes import FakeInviteAdmin, FakeServiceController


def _ops(invite_admin) -> tuple[OperationsService, AuditLog]:
    audit = AuditLog()
    clock = itertools.count(1000).__next__
    ids = itertools.count(1)
    ops = OperationsService(
        {}, FakeServiceController(), audit,
        clock=clock, id_factory=lambda: f"job-{next(ids)}", invite_admin=invite_admin,
    )
    return ops, audit


def test_mint_invite_returns_succeeded_job_and_code():
    admin = FakeInviteAdmin(code="secret-code-xyz")
    ops, audit = _ops(admin)
    job, code = ops.mint_invite("alice", 3600)
    assert job.state is JobState.SUCCEEDED
    assert job.action == "mint_invite"
    assert job.operator == "alice"
    assert code == "secret-code-xyz"
    assert admin.calls == [3600]
    assert [j.job_id for j in audit.recent()] == [job.job_id]


def test_mint_invite_never_puts_the_code_in_the_audit():
    admin = FakeInviteAdmin(code="secret-code-xyz")
    ops, audit = _ops(admin)
    job, code = ops.mint_invite("operator", None)
    assert code == "secret-code-xyz"
    # The secret must not leak into the job detail or the audit record.
    assert "secret-code-xyz" not in job.detail
    for recorded in audit.recent():
        assert "secret-code-xyz" not in recorded.detail
        assert "secret-code-xyz" not in recorded.to_dict().values()


def test_mint_invite_failure_yields_failed_job_and_no_code():
    ops, audit = _ops(FakeInviteAdmin(fail=True))
    job, code = ops.mint_invite("operator", None)
    assert job.state is JobState.FAILED
    assert code == ""
    assert "boom" not in job.detail  # only the bounded exception type name, not the message
    assert audit.recent()[-1].state is JobState.FAILED


def test_mint_invite_without_admin_is_failed():
    ops, _ = _ops(None)
    job, code = ops.mint_invite("operator", None)
    assert job.state is JobState.FAILED
    assert code == ""
