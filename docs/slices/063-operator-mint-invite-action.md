# Slice 063 — Operator control plane: audited mint-invite action

Status: **in progress**

Phase: 10 (Authoritative runtime and action input), advancing
[P-014](../FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)
and the [operator control-plane decision](../../.scratch/container-platform/issues/04-operator-control-plane-and-telemetry.md)
("invite minting … reuse the existing enrollment CLI seams through the
adapter"). Ninth delivery of the
[container-platform map](../../.scratch/container-platform/map.md).

## User outcome

An operator can mint a single-use enrollment invite through the private,
authenticated control plane; the action is an auditable job, and the secret
invite code is returned to the operator but never written to the audit log.

## Scope and non-goals

In scope: an `InviteAdmin` adapter (`infra/operator/invites.py`) that reuses the
enrollment store for persistence and a CSPRNG code (mirroring
`infra/enrollment/cli.py`); `OperationsService.mint_invite(operator,
expires_in_seconds)` returning an audited `Job` plus the code (the code is NOT
in the job/audit — only the response carries it); `POST /invites` (bearer-authed,
optional `expires_in_seconds` body + `X-Operator` header) in `app.py`; and
pytest against a fake invite admin.

Out of scope (later slices): peer revocation (`POST /peers/{key}/revoke`, needs
the OPNsense client — a separate slice); `/update`; start/stop; a durable audit
sink; changing the enrollment service. The mint action shares the enrollment
SQLite DB with the enrollment service (a low-frequency second writer); WAL/locking
hardening is an ops follow-up. No game `.gd` change; the GUT suite is unaffected.

## Public seam

- `infra/operator/invites.py` (`InviteAdmin` Protocol, `RealInviteAdmin(store)`:
  `mint_invite(expires_in_seconds) -> code`).
- `infra/operator/operations.py` (`OperationsService.mint_invite(operator,
  expires_in_seconds) -> tuple[Job, str]`): fail-closed to a `failed` job with a
  bounded detail and no code when the admin is absent or raises.
- `infra/operator/app.py` (`POST /invites` → `{ "job": {...}, "invite_code":
  "..." }`; the code is present only on success).

## Safety invariant

The invite code is a single-use credential: it is returned in the response over
the private, authenticated loopback channel but is NEVER placed in the `Job`
detail, the append-only audit log, or any log line. Every mint is an
allowlisted, authenticated, audited job. A mint failure yields a `failed` job
with a bounded reason (the exception type name only) and no code.

## ADR rationale

No new ADR. Reusing the enrollment seam for invite minting and wrapping it in
the job/audit model are already fixed by the accepted operator control-plane
decision.

## BDD / TDD

`infra/operator/tests/test_invites.py`: `mint_invite` returns a `succeeded` job
and a non-empty code; the audit log records the job but its detail does NOT
contain the code; a failing admin yields a `failed` job with no code.
`infra/operator/tests/test_invites_api.py`: `POST /invites` is 401 without a
token, 403 with a wrong token, 200 with an `invite_code` and a recorded job on
success; and `GET /jobs` never exposes the code. A fake invite admin is used —
no real enrollment DB is touched.

## Validation

- Focused: `python -m pytest infra/operator/tests` on the Linux host (reusing
  `.venv-enrollment`).
- `scripts/check_record_sync.sh` (exit 0); GUT unaffected (Python-only).
  Recorded on completion.

## Root-cause learning

None yet.
