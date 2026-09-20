from __future__ import annotations

import itertools

from infra.operator.audit_store import SqliteAuditLog
from infra.operator.jobs import Job, JobState
from infra.operator.operations import OperationsService
from infra.operator.tests.fakes import FakeServiceController


def _job(job_id: str, *, state: JobState = JobState.SUCCEEDED, detail: str = "") -> Job:
    return Job(
        job_id=job_id, action="restart", target="game-server", operator="alice",
        requested_at=1000.0, state=state, started_at=1000.0, finished_at=1001.0,
        outcome="ok", detail=detail,
    )


def test_record_then_recent_returns_jobs_in_order(tmp_path):
    store = SqliteAuditLog(str(tmp_path / "audit.sqlite3"))
    try:
        store.record(_job("job-1"))
        store.record(_job("job-2"))
        assert [j.job_id for j in store.recent()] == ["job-1", "job-2"]
    finally:
        store.close()


def test_audit_persists_across_reopen(tmp_path):
    db_path = str(tmp_path / "audit.sqlite3")
    store = SqliteAuditLog(db_path)
    store.record(_job("job-1", state=JobState.FAILED, detail="systemd boom"))
    store.record(_job("job-2"))
    store.close()

    reopened = SqliteAuditLog(db_path)
    try:
        jobs = reopened.recent()
        assert [j.job_id for j in jobs] == ["job-1", "job-2"]
        assert jobs[0].state is JobState.FAILED
        assert jobs[0].detail == "systemd boom"
    finally:
        reopened.close()

def test_recent_respects_limit_and_returns_newest_window_in_order(tmp_path):
    store = SqliteAuditLog(str(tmp_path / "audit.sqlite3"))
    try:
        for n in range(5):
            store.record(_job(f"job-{n}"))
        window = store.recent(limit=2)
        assert [j.job_id for j in window] == ["job-3", "job-4"]
    finally:
        store.close()


def test_parent_directory_is_created(tmp_path):
    db_path = str(tmp_path / "nested" / "dir" / "audit.sqlite3")
    store = SqliteAuditLog(db_path)
    try:
        store.record(_job("job-1"))
        assert [j.job_id for j in store.recent()] == ["job-1"]
    finally:
        store.close()


def test_operations_audit_survives_store_reopen(tmp_path):
    db_path = str(tmp_path / "audit.sqlite3")
    clock = itertools.count(1000).__next__
    ids = itertools.count(1)

    store = SqliteAuditLog(db_path)
    ops = OperationsService(
        {"game-server": ("systemd", "project0-server")},
        FakeServiceController(systemd_ok=True), store,
        clock=clock, id_factory=lambda: f"job-{next(ids)}",
    )
    job = ops.restart("game-server", "alice")
    assert job.state is JobState.SUCCEEDED
    store.close()

    reopened = SqliteAuditLog(db_path)
    try:
        recorded = reopened.recent()
        assert [j.job_id for j in recorded] == [job.job_id]
        assert recorded[0].action == "restart"
        assert recorded[0].state is JobState.SUCCEEDED
    finally:
        reopened.close()
