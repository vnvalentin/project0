# Slice 065 — Operator control plane: durable SQLite audit sink
GitHub issue: #95

Status: **delivered**

Phase: 10 (Authoritative runtime and action input), advancing
[P-014](../FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)
and the [operator control-plane decision](../../.scratch/container-platform/issues/04-operator-control-plane-and-telemetry.md)
("audit records … durable and append-only"). Eleventh delivery of the
[container-platform map](../../.scratch/container-platform/map.md); it replaces
the in-memory operator audit log with a durable SQLite sink so the audit trail
survives restarts.

## User outcome

The operator's audit trail of jobs (restart, mint-invite, revoke-peer) survives
a control-plane restart — every action stays recorded and queryable via
`GET /jobs` after the service comes back up.

## Scope and non-goals

In scope: a `SqliteAuditLog` (`infra/operator/audit_store.py`) that mirrors the
in-memory `AuditLog` interface (`record`/`recent`) but persists append-only to
SQLite (WAL); an `OPERATOR_AUDIT_DB_PATH` config value (default under
`infra/operator/.data/`, overridable to `/var/lib/project0/operator/` in
production); `build_production_app` wiring the durable sink; and pytest proving
persistence across reopen and end-to-end through `OperationsService`.

Out of scope (later slices): retention/rotation of old audit rows; querying by
time/operator/action; exporting audit to external telemetry; other operator
actions. Tests continue to use the in-memory `AuditLog`; the durable sink is a
drop-in with the same interface. No game `.gd` change; the GUT suite is
unaffected.

## Public seam

- `infra/operator/audit_store.py` (`SqliteAuditLog(db_path)`: `record(job)`,
  `recent(limit)`, `close()`), append-only, WAL, parent-dir auto-created.
- `infra/operator/config.py` (`OperatorConfig.audit_db_path`, `load_config`
  reads `OPERATOR_AUDIT_DB_PATH`).
- `infra/operator/app.py` (`build_production_app` constructs
  `SqliteAuditLog(config.audit_db_path)`).

## Safety invariant

The durable sink is append-only and never stores a secret: the invite code was
already kept out of the `Job` (Slice 063), so persisting the job is safe. The
audit DB lives outside the image on a host path; the operator service remains
loopback-bound and token-authed. A `recent()` window reads back in chronological
order, matching the in-memory log.

## ADR rationale

No new ADR. A durable, append-only audit trail is already required by the
accepted operator control-plane decision; SQLite mirrors the enrollment
service's storage choice.

## BDD / TDD

`infra/operator/tests/test_audit_store.py`: `record` then `recent` returns the
jobs in order; the log persists across a close/reopen of the same DB path
(durability); `recent(limit)` bounds and orders the window; an
`OperationsService` wired to a `SqliteAuditLog` still shows a restart job after
the store is reopened; and a persisted mint-invite job never contains the secret
code. `test_config` gains an `audit_db_path` default assertion.

## Validation

- Focused: `python -m pytest infra/operator/tests` on the Linux host (reusing
  `.venv-enrollment`) — **48 passed** (41 + 7 new: audit-store record/recent,
  durability across reopen, limit/order, parent-dir, `OperationsService`
  end-to-end, secret redaction, and the config-override test).
- `scripts/check_record_sync.sh` exit 0 (6 pre-existing WARN about slices with
  no named feature). GUT suite unaffected (Python-only change).

## Root-cause learning

None yet.
