from __future__ import annotations

import itertools

from infra.operator.jobs import AuditLog, JobState
from infra.operator.operations import OperationsService
from infra.operator.tests.fakes import FakePeerAdmin, FakeServiceController

PUBKEY = "AbCdEf0123456789AbCdEf0123456789AbCdEf01234="


def _ops(peer_admin) -> tuple[OperationsService, AuditLog]:
    audit = AuditLog()
    clock = itertools.count(1000).__next__
    ids = itertools.count(1)
    ops = OperationsService(
        {}, FakeServiceController(), audit,
        clock=clock, id_factory=lambda: f"job-{next(ids)}", peer_admin=peer_admin,
    )
    return ops, audit


def test_revoke_peer_succeeds_and_audits():
    admin = FakePeerAdmin(outcome="REVOKED")
    ops, audit = _ops(admin)
    job = ops.revoke_peer("alice", PUBKEY)
    assert job.state is JobState.SUCCEEDED
    assert job.action == "revoke_peer"
    assert job.target == PUBKEY
    assert job.operator == "alice"
    assert job.outcome == "REVOKED"
    assert admin.calls == [PUBKEY]
    assert [j.job_id for j in audit.recent()] == [job.job_id]


def test_revoke_absent_peer_is_success_already_absent():
    ops, _ = _ops(FakePeerAdmin(outcome="ALREADY_ABSENT"))
    job = ops.revoke_peer("operator", PUBKEY)
    assert job.state is JobState.SUCCEEDED
    assert job.outcome == "ALREADY_ABSENT"


def test_revocation_rejection_yields_failed_job_with_bounded_reason():
    ops, audit = _ops(FakePeerAdmin(reject_reason="UPSTREAM_DELETE_FAILED"))
    job = ops.revoke_peer("operator", PUBKEY)
    assert job.state is JobState.FAILED
    assert job.outcome == "failed"
    assert job.detail == "UPSTREAM_DELETE_FAILED"
    assert audit.recent()[-1].state is JobState.FAILED


def test_revoke_without_admin_is_failed():
    ops, _ = _ops(None)
    job = ops.revoke_peer("operator", PUBKEY)
    assert job.state is JobState.FAILED
    assert job.detail == "peer admin unavailable"
