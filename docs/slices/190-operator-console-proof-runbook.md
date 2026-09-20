# Slice 190 - Operator console proof and runbook

GitHub issue: #165

Status: **in progress**

Phase: 17 (Fleet operations console)

Feature: [F-041](../FEATURE-LIST.md#f-041-fleet-operations-console)

## Outcome

The fleet-operations design and implementation slices have a durable operator
runbook and a final proof boundary. Read-only telemetry is ready for an
end-to-end deployment proof; privileged control remains explicitly gated on the
host helper and authoritative Godot seam.

## Evidence boundary

Slices 184-188 are focused-tested. Slice 189 verifies the Python assertion,
scope seam, and fixed-allowlist host helper. The private `/control` adapter now
routes lifecycle actions through the audited operator service and fails closed
with `executor_unavailable` for gameplay actions until the Godot transport is
wired. The authoritative `OperatorControlService` and `OperatorControlAdapter`
are covered by focused tests for drain, degraded state, peer-target validation,
assertion rejection, scope rejection, and authorized dispatch. The remaining
proof must wire that adapter to the running server and show the LAN console reads real
world/login snapshots, stale/unreadable states remain non-authoritative, and
each privileged executor independently rejects invalid or under-scoped
assertions.

### Deployment evidence

On 2026-09-20, the merged control transport was deployed on `okami` with the
paired Project0/Nakama stack. All five services passed the deployment health
gate and the enrollment smoke checks returned HTTP 401 and HTTP 200 as
expected. The game server logged `Operator control HTTP endpoint listening on
internal port 8097`. A request with an invalid operator assertion reached
`/internal/control` and returned HTTP 403 with no action execution.

The operator-console forwarding service was not enabled during this proof, and
no privileged action was executed. The remaining gap is an operator-managed
`OPERATOR_TOKEN`/assertion configuration plus a live authorized action proof.

## Runbook

See [fleet-operator-runbook.md](../fleet-operator-runbook.md) for bind/mount,
secret, rollback, Nakama migration, and current validation rules.

## Non-goals

This record does not claim privileged control or a production operator-console
cutover. Those require the remaining executor implementation and live proof.

## Root-cause learning

No unexpected runtime failure occurred in this planning/runbook increment.
