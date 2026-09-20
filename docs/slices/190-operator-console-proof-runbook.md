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
wired. The authoritative `OperatorControlService` is covered by focused tests
for drain, degraded state, and peer-target validation. The remaining proof must
wire that adapter to the running server and show the LAN console reads real
world/login snapshots, stale/unreadable states remain non-authoritative, and
each privileged executor independently rejects invalid or under-scoped
assertions.

## Runbook

See [fleet-operator-runbook.md](../fleet-operator-runbook.md) for bind/mount,
secret, rollback, Nakama migration, and current validation rules.

## Non-goals

This record does not claim privileged control or a production operator-console
cutover. Those require the remaining executor implementation and live proof.

## Root-cause learning

No unexpected runtime failure occurred in this planning/runbook increment.
