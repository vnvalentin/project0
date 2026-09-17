# Slice 066 — Operator control plane: audited start/stop lifecycle actions
GitHub issue: #95

Status: **delivered**

Phase: 10 (Authoritative runtime and action input), advancing
[P-014](../FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)
and the [operator control-plane decision](../../.scratch/container-platform/issues/04-operator-control-plane-and-telemetry.md)
(the admin interface must control the service lifecycle, not just restart it).
Twelfth delivery of the [container-platform map](../../.scratch/container-platform/map.md);
it completes the basic service-lifecycle controls (`start`, `stop`) alongside
the existing `restart`.

## User outcome

An operator can start and stop an allowlisted service through the control plane,
each as an audited job, using the same token-authed private surface as restart.

## Scope and non-goals

In scope: generalize the `ServiceController` seam to a single
`run(kind, action, identifier)` verb (`start`/`stop`/`restart`); a shared
`OperationsService._lifecycle` used by `restart`/`start`/`stop`; two new routes
`POST /services/{name}/start` and `POST /services/{name}/stop`; and pytest for
the unit + API paths.

Out of scope (later slices): `/update` (image pull + redeploy), status polling
after an action, scheduled/timed actions. The allowlist and fixed-argument-vector
guarantee are unchanged. No game `.gd` change; the GUT suite is unaffected.

## Public seam

- `infra/operator/control.py` (`ServiceController.run(kind, action, identifier)`;
  `RealServiceController` runs a fixed `systemctl <action> <unit>` /
  `docker <action> <container>` vector, rejecting any non-lifecycle action).
- `infra/operator/operations.py` (`OperationsService.start`, `.stop`; shared
  `_lifecycle`).
- `infra/operator/app.py` (`POST /services/{name}/start`,
  `POST /services/{name}/stop`).

## Safety invariant

Only the three lifecycle verbs (`start`, `stop`, `restart`) reach the controller,
and only over allowlisted names; the action and identifier are fixed argument
vectors — no shell, no caller-supplied command. An unknown service is fail-closed
(nothing runs, nothing is audited). Every action is an audited job.

## ADR rationale

No new ADR. Lifecycle control is already implied by the accepted operator
control-plane decision; this generalizes the existing restart seam rather than
adding a parallel one.

## BDD / TDD

`test_operations.py`: `start`/`stop` succeed and audit with the correct action
verb and controller call `(kind, action, identifier)`; unknown service is
fail-closed and unaudited. `test_restart_api.py`: `POST /start` and `/stop`
return the audited job (200) and require the token; unknown service → 404.
`test_control.py` (if present) / unit: `RealServiceController.run` rejects a
non-lifecycle action.

## Validation

- Focused: `python -m pytest infra/operator/tests` on the Linux host (reusing
  `.venv-enrollment`) — **62 passed** (48 + 14 new: start/stop unit + API,
  action-verb call assertions, and the non-lifecycle-action controller guard).
- `scripts/check_record_sync.sh` exit 0 (6 pre-existing WARN about slices with
  no named feature). GUT suite unaffected (Python-only change).

## Root-cause learning

None yet.
