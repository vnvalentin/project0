# Slice 184 - Server admin console OpsSnapshot contract

GitHub issue: #165

Status: **delivered**

Phase: 17 (Fleet operations console)

Feature: [F-040](../FEATURE-LIST.md#f-040-fleet-operations-console)

## User outcome

The future operator console has a pure, versioned, bounded read-model contract
that can compose existing ServerHealth data without changing gameplay authority.

## Public seam

`server/ops_snapshot.gd` exposes `OpsSnapshot.build()` and
`OpsSnapshot.from_wire_dict()`. The seam validates server identity/type, bounded
metadata, the composed ServerHealth core, schema version, and bounded extension
fields.

## Non-goals

This slice does not write files, change HealthReporter, add a console service,
add control actions, or expose an HTTP endpoint.

## Validation

- Focused GUT: `test_ops_snapshot.gd`, 5/5 passing.
- `get_errors` reported no errors in the implementation or test file.
- Record synchronization and full-suite validation are required at merge.

## Safety and rollback

The module is pure and server-only. Rollback is reverting the slice; no runtime,
database, network, permission, or external side effect is introduced.

## Root-cause learning

No unexpected runtime failure occurred in this slice.
