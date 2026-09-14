"""Operator job model and append-only audit log.

Every mutating operator action is wrapped in a Job with a bounded lifecycle
(requested -> running -> succeeded/failed), a correlation id, operator identity,
target, timestamps, and a bounded outcome. The AuditLog is append-only. A
durable sink (sqlite/file) is a follow-up; this keeps the model testable.
"""
from __future__ import annotations

import enum
from dataclasses import asdict, dataclass


class JobState(str, enum.Enum):
    REQUESTED = "requested"
    RUNNING = "running"
    SUCCEEDED = "succeeded"
    FAILED = "failed"


@dataclass
class Job:
    job_id: str
    action: str
    target: str
    operator: str
    requested_at: float
    state: JobState = JobState.REQUESTED
    started_at: float | None = None
    finished_at: float | None = None
    outcome: str = ""
    detail: str = ""

    def to_dict(self) -> dict:
        data = asdict(self)
        data["state"] = self.state.value
        return data


class AuditLog:
    """Append-only in-memory record of completed operator jobs."""

    def __init__(self) -> None:
        self._jobs: list[Job] = []

    def record(self, job: Job) -> None:
        self._jobs.append(job)

    def recent(self, limit: int = 50) -> list[Job]:
        return list(self._jobs[-limit:])
