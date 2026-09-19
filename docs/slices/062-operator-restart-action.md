# Slice 062 — Operator control plane: job/audit model + service restart action
GitHub issue: #95

Status: **delivered**

Phase: 10 (Authoritative runtime and action input), advancing
[P-014](../FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)
and the [operator control-plane decision](../../.scratch/container-platform/issues/04-operator-control-plane-and-telemetry.md).
Eighth delivery of the
[container-platform map](../../.scratch/container-platform/map.md); it adds the
first *mutating* operator action (service restart) behind the decision's
required job lifecycle and audit trail, on top of the Slice 061 read-only
foundation.

## User outcome

An operator can restart an allowlisted host service through one private,
authenticated endpoint, and every attempt is recorded as an auditable job
(requested → running → succeeded/failed) with a correlation id, operator
identity, target, timestamps, and a bounded outcome — never an arbitrary
command.

## Scope and non-goals

In scope: a `Job`/`JobState` model and an append-only `AuditLog`
(`infra/operator/jobs.py`); a `ServiceController` Protocol +
`RealServiceController` running fixed `systemctl restart` / `docker restart`
against allowlisted identifiers (`infra/operator/control.py`); an
`OperationsService` that wraps a restart in a job, records it, and exposes
recent jobs (`infra/operator/operations.py`); `POST /services/{name}/restart`
(bearer-authed, allowlisted, 404 on unknown) and `GET /jobs` (bearer-authed) in
`app.py`; and pytest against a fake controller.

Out of scope (later slices): other mutating actions (`/invites`,
`/peers/{key}/revoke`, `/update`, start/stop); a durable (sqlite/file) audit
sink — this slice keeps the append-only log in memory and validates the model
and lifecycle, with durability a follow-up; live systemd-restart privilege
(running `systemctl restart` as the non-root service user needs a polkit/sudoers
grant — an ops prerequisite, so this slice validates the logic against a fake
controller exactly as Slice 049 validated revocation against a fake OPNsense
client, without a live call). No game `.gd` change; the GUT suite is unaffected.

## Public seam

- `infra/operator/jobs.py` (`JobState`, `Job` with `to_dict`, `AuditLog` with
  `record`/`recent`).
- `infra/operator/control.py` (`ServiceController` Protocol,
  `RealServiceController.restart_systemd`/`restart_docker`).
- `infra/operator/operations.py` (`OperationsService.restart(name, operator)` →
  `Job`, `recent_jobs(limit)`), fail-closed on an unknown service.
- `infra/operator/app.py`: `POST /services/{name}/restart` (optional
  `X-Operator` header for identity), `GET /jobs`; `create_app` now also takes
  the operations service.

## Safety invariant

Every mutating action is allowlisted, authenticated, and audited, and is a fixed
argument vector (`systemctl restart <unit>` / `docker restart <container>`) —
no shell, no caller-supplied command. An unknown service is 404 (fail-closed and
unaudited — nothing ran). A controller failure produces a `failed` job with a
bounded detail, never a stack trace or unbounded text. The audit record is
append-only.

## ADR rationale

No new ADR. The job lifecycle, correlation id, audit trail, allowlisting, and
token auth are already fixed by the accepted operator control-plane decision.

## BDD / TDD

`infra/operator/tests/test_operations.py`: a restart on an allowlisted systemd
service calls `restart_systemd` and yields a `succeeded` job; a docker service
uses `restart_docker`; a controller failure yields a `failed` job with the
detail; an unknown service is fail-closed (`UnknownServiceError`); the audit log
records each completed job and `recent_jobs` returns them.
`infra/operator/tests/test_restart_api.py`: `POST /services/{name}/restart` is
401 without a token, 403 with a wrong token, 404 for an unknown service, 200 with
a `succeeded` job for a healthy controller (and the `X-Operator` identity
recorded), 200 with a `failed` job when the controller fails; `GET /jobs` lists
the recorded job. Existing status tests stay green (the `create_app` fixture is
updated to pass the operations service). No real systemctl/docker call is made.

## Validation

- Focused: `python -m pytest infra/operator/tests` on the Linux host (reusing
  `.venv-enrollment`).
- `scripts/check_record_sync.sh` (exit 0); GUT unaffected (Python-only).
  Recorded on completion.

### Result (Linux host `192.168.1.254`, 2026-09-14)

`.venv-enrollment/bin/python -m pytest infra/operator/tests` passed **24 tests**
(13 read-only status from Slice 061 + 11 new: 5 `test_operations` + 6
`test_restart_api`), 0 failures — covering the audited restart lifecycle
(succeeded/failed), fail-closed unknown service, `X-Operator` identity capture,
and `GET /jobs`. `scripts/check_record_sync.sh` reported 0 errors, exit 0. The
GUT suite is unaffected (no `.gd` change).

## Root-cause learning

None yet.
