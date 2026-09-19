"""Durable SQLite audit sink for operator jobs.

Append-only and WAL-backed; survives control-plane restarts. Mirrors the
in-memory AuditLog interface (record/recent) so it drops in wherever the
OperationsService expects an audit sink. Never stores a secret: the invite code
is already kept out of the Job (Slice 063), so persisting the Job is safe.
"""
from __future__ import annotations

import os
import sqlite3

from .jobs import Job, JobState

_SCHEMA = """
CREATE TABLE IF NOT EXISTS audit_jobs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id TEXT NOT NULL,
    action TEXT NOT NULL,
    target TEXT NOT NULL,
    operator TEXT NOT NULL,
    requested_at REAL NOT NULL,
    state TEXT NOT NULL,
    started_at REAL,
    finished_at REAL,
    outcome TEXT NOT NULL,
    detail TEXT NOT NULL
);
"""


class SqliteAuditLog:
    def __init__(self, db_path: str) -> None:
        if db_path != ":memory:":
            parent = os.path.dirname(db_path)
            if parent:
                os.makedirs(parent, exist_ok=True)
        # check_same_thread=False: FastAPI dispatches sync endpoints to a worker
        # threadpool; every write is a single committed statement.
        self._conn = sqlite3.connect(db_path, check_same_thread=False)
        self._conn.execute("PRAGMA journal_mode=WAL")
        self._conn.executescript(_SCHEMA)
        self._conn.commit()

    def close(self) -> None:
        self._conn.close()

    def record(self, job: Job) -> None:
        self._conn.execute(
            "INSERT INTO audit_jobs "
            "(job_id, action, target, operator, requested_at, state, started_at, finished_at, outcome, detail) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (
                job.job_id, job.action, job.target, job.operator, job.requested_at,
                job.state.value, job.started_at, job.finished_at, job.outcome, job.detail,
            ),
        )
        self._conn.commit()

    def recent(self, limit: int = 50) -> list[Job]:
        rows = self._conn.execute(
            "SELECT job_id, action, target, operator, requested_at, state, started_at, finished_at, outcome, detail "
            "FROM audit_jobs ORDER BY id DESC LIMIT ?",
            (limit,),
        ).fetchall()
        jobs = [self._row_to_job(row) for row in rows]
        jobs.reverse()  # chronological within the window, matching the in-memory log
        return jobs

    @staticmethod
    def _row_to_job(row) -> Job:
        return Job(
            job_id=row[0], action=row[1], target=row[2], operator=row[3],
            requested_at=row[4], state=JobState(row[5]), started_at=row[6],
            finished_at=row[7], outcome=row[8], detail=row[9],
        )
