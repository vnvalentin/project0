# Slice 186 - OpsSnapshot registry and freshness scanner

GitHub issue: #165

Status: **delivered**

Phase: 17 (Fleet operations console)

Feature: [F-041](../FEATURE-LIST.md#f-041-fleet-operations-console)

## Outcome

The operator-console boundary can scan a manifest-backed server registry and
classify each entry as healthy, stale, absent, or unreadable without executing
snapshot metadata.

## Public seam

`dashboard/ops_registry.py::scan_registry` reads a JSON manifest and a
read-only snapshot directory. It accepts an explicit clock for deterministic
freshness tests, rejects unknown server types and identity mismatches, and keeps
unknown/unreadable entries non-authoritative.

## Non-goals

No HTTP surface, Docker mount, control action, or server-side snapshot emitter
is added here; those remain later slices.

## Validation

- `python -m pytest dashboard/tests/test_ops_registry.py -q`: 3 passed.
- `python -m py_compile dashboard/ops_registry.py`: passed.
- `git diff --check`: passed.

## Safety and rollback

The scanner is read-only and uses no network or external side effect. Rollback
is reverting the slice.

## Root-cause learning

No unexpected runtime failure occurred in this slice.
