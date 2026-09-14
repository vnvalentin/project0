"""Operator operations: wrap a mutating action in an audited job.

Fail-closed on an unknown service (nothing runs, nothing is audited). A
controller failure yields a `failed` job with a bounded detail. The clock and id
factory are injectable so job records are deterministic in tests.
"""
from __future__ import annotations

import time
import uuid

from .control import ServiceController
from .jobs import AuditLog, Job, JobState
from .services import UnknownServiceError


class OperationsService:
    def __init__(
        self,
        services: dict[str, tuple[str, str]],
        controller: ServiceController,
        audit: AuditLog,
        clock=time.time,
        id_factory=lambda: uuid.uuid4().hex,
    ) -> None:
        self._services = dict(services)
        self._controller = controller
        self._audit = audit
        self._clock = clock
        self._id = id_factory

    def restart(self, name: str, operator: str) -> Job:
        if name not in self._services:
            raise UnknownServiceError(name)
        kind, identifier = self._services[name]

        job = Job(
            job_id=self._id(),
            action="restart",
            target=name,
            operator=operator,
            requested_at=self._clock(),
        )
        job.state = JobState.RUNNING
        job.started_at = self._clock()

        if kind == "systemd":
            ok, detail = self._controller.restart_systemd(identifier)
        elif kind == "docker":
            ok, detail = self._controller.restart_docker(identifier)
        else:
            ok, detail = False, "unknown service kind"

        job.finished_at = self._clock()
        job.state = JobState.SUCCEEDED if ok else JobState.FAILED
        job.outcome = "ok" if ok else "failed"
        job.detail = detail
        self._audit.record(job)
        return job

    def recent_jobs(self, limit: int = 50) -> list[Job]:
        return self._audit.recent(limit)
