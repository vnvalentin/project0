---
status: accepted for downstream implementation
---

# Server admin and telemetry console

## Context

Project0 needs current operator visibility and bounded repair actions across its
single-host services without turning the dashboard, Nakama, or the game server
into an unaudited authority. The console is LAN-only and current-state only;
long-term metrics, paging, GM actions, and Canon/progression mutation are out of
scope.

## Decision

Create a standalone Python stdlib `http.server` operator console. Servers emit a
pure, versioned `OpsSnapshot` that composes the existing `ServerHealth` core and
a bounded typed extension. Each server writes one atomic snapshot file under
`/var/lib/project0/ops-snapshots/<server_id>/`; the console mounts that tree
read-only and scans a small manifest-backed registry.

Tier 1 is read-only telemetry. Tier 2 uses versioned `ControlAction` and
`ControlResult` contracts. Systemd lifecycle actions run through an independently
authenticated host helper. Kick, drain, tuning reload, and degraded-state
changes run through an independently authenticated, authoritative Godot seam.
Both executors verify an operator token derived from the existing assertion
primitive. The token carries identity and scopes so later RBAC changes issuance,
not action semantics. All actions are idempotent and audit-logged.

Known world/login extensions expose only bounded, present-day fields. Unknown
extensions are display-only. Incompatible core snapshots are unreadable rather
than interpreted. Enrollment and host-firewall begin as systemd-status-only
entries.

## Consequences

The file boundary keeps the first implementation simple, local, and read-only
from the console's perspective. Atomic writes and freshness thresholds make
stale state explicit. A future HTTP read transport is allowed only as a bounded
follow-up when file transport cannot satisfy freshness, multi-host, or access
control requirements.

The console is a separate release surface and cannot silently gain public
traffic. Gameplay authority remains in Project0; Nakama remains identity/session
and realtime infrastructure.

## Downstream handoff

See `.scratch/server-admin-console/spec.md`. Implement in this order:

1. Slice 184: pure OpsSnapshot contract and tests.
2. Slice 185: atomic snapshot writers and emitters.
3. Slice 186: registry and freshness scanner.
4. Slice 187: read-only console surface/container.
5. Slice 188: control contracts/audit.
6. Slice 189: authenticated Godot seam and host helper.
7. Slice 190: end-to-end proof and runbook.

The first failing-test seam is `OpsSnapshot.build/validate` with valid world and
login extensions, unknown extension display, incompatible core schema rejection,
and bounded-field rejection.
