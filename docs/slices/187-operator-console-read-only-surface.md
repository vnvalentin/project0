# Slice 187 - Read-only operator console surface

GitHub issue: #165

Status: **delivered**

Phase: 17 (Fleet operations console)

Feature: [F-041](../FEATURE-LIST.md#f-041-fleet-operations-console)

## Outcome

A standalone LAN-bound stdlib HTTP service renders a fleet overview and a
per-server detail view from the read-only registry scanner. It exposes healthz
only; no control or gameplay mutation exists yet.

## Public seam

`operator_console/app.py` serves `/`, `/server/<server_id>`, and `/healthz`.
The Compose `operator-console` service is profile-scoped as an auxiliary
operator surface, uses a separate port, and mounts config/snapshots read-only.

## Non-goals

Control actions, operator authentication, server-side snapshot emitters, and
HTTP transport for server telemetry are later slices.

## Validation

- `python -m pytest dashboard/tests/test_ops_registry.py operator_console/tests/test_app.py -q`: 4 passed.
- `python -m py_compile dashboard/ops_registry.py operator_console/app.py`: passed.
- `git diff --check`: passed.
- Local Docker was unavailable; Compose was not started.

## Safety and rollback

The surface is read-only and LAN-bound by default. It has no credential or
control path. Rollback is reverting the slice and removing the auxiliary
Compose service.

## Root-cause learning

The first UI test fixture used an old timestamp and correctly rendered stale;
the fixture was corrected to use an explicit current timestamp. The focused suite
then passed 4/4.
