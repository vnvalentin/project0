"""Operator operations: wrap a mutating action in an audited job.

Fail-closed on an unknown service (nothing runs, nothing is audited). A
controller failure yields a `failed` job with a bounded detail. The clock and id
factory are injectable so job records are deterministic in tests.
"""
from __future__ import annotations

import time
import uuid

from .control import ServiceController
from .invites import InviteAdmin
from .jobs import AuditLog, Job, JobState
from .peers import PeerAdmin, PeerRevocationError
from .services import UnknownServiceError


class OperationsService:
    def __init__(
        self,
        services: dict[str, tuple[str, str]],
        controller: ServiceController,
        audit: AuditLog,
        clock=time.time,
        id_factory=lambda: uuid.uuid4().hex,
        invite_admin: InviteAdmin | None = None,
        peer_admin: PeerAdmin | None = None,
    ) -> None:
        self._services = dict(services)
        self._controller = controller
        self._audit = audit
        self._clock = clock
        self._id = id_factory
        self._invites = invite_admin
        self._peers = peer_admin

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

    def mint_invite(self, operator: str, expires_in_seconds: int | None) -> tuple[Job, str]:
        """Mints a single-use invite as an audited job. Returns (job, code); the
        code is a SECRET returned to the caller only — it is never placed in the
        job detail or the audit log. Fail-closed: an absent or failing admin
        yields a `failed` job and an empty code."""
        job = Job(
            job_id=self._id(),
            action="mint_invite",
            target="invite",
            operator=operator,
            requested_at=self._clock(),
        )
        job.state = JobState.RUNNING
        job.started_at = self._clock()
        code = ""
        if self._invites is None:
            job.detail = "invite admin unavailable"
        else:
            try:
                code = self._invites.mint_invite(expires_in_seconds)
            except Exception as exc:  # a job runner converts any failure into a bounded failed job
                job.detail = "mint failed: %s" % type(exc).__name__
        job.finished_at = self._clock()
        if code:
            job.state = JobState.SUCCEEDED
            job.outcome = "ok"
            job.detail = "minted invite"  # never the code
        else:
            job.state = JobState.FAILED
            job.outcome = "failed"
        self._audit.record(job)
        return job, code

    def revoke_peer(self, operator: str, public_key: str) -> Job:
        """Revokes an enrolled peer as an audited job. The public key is public
        (not a secret) and is recorded as the job target. Fail-closed: an absent
        admin, a bounded revocation rejection, or any error yields a `failed`
        job with a bounded reason."""
        job = Job(
            job_id=self._id(),
            action="revoke_peer",
            target=public_key,
            operator=operator,
            requested_at=self._clock(),
        )
        job.state = JobState.RUNNING
        job.started_at = self._clock()
        if self._peers is None:
            job.state = JobState.FAILED
            job.outcome = "failed"
            job.detail = "peer admin unavailable"
        else:
            try:
                outcome = self._peers.revoke_peer(public_key)
                job.state = JobState.SUCCEEDED
                job.outcome = outcome
                job.detail = outcome
            except PeerRevocationError as exc:
                job.state = JobState.FAILED
                job.outcome = "failed"
                job.detail = exc.reason
            except Exception as exc:  # a job runner converts any failure into a bounded failed job
                job.state = JobState.FAILED
                job.outcome = "failed"
                job.detail = "revoke failed: %s" % type(exc).__name__
        job.finished_at = self._clock()
        self._audit.record(job)
        return job
