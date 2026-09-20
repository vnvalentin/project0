# Server Admin and Telemetry Console Handoff

Status: handoff-ready, planning only
Governing goal: server-admin-console (#165)
ADR: [ADR 0010](../../docs/adr/0010-server-admin-console.md)

## Outcome

A standalone LAN operator console reads current, bounded state from every
registered Project0 server and exposes a separately authenticated tier-2 control
plane. It never becomes a gameplay or Canon authority.

## OpsSnapshot contract

`OpsSnapshot` is a pure server-only contract that composes the existing
`ServerHealth` core without changing `ServerHealth`:

```json
{
  "snapshot_schema_version": 1,
  "server_id": "project0-game",
  "server_type": "world",
  "server_version": "git-sha-or-release",
  "status": "healthy",
  "degraded_reason": "",
  "tick_rate": 60.0,
  "uptime_seconds": 123,
  "server_tick": 4567,
  "connected_peers": 2,
  "max_peers": 64,
  "app_schema_version": 1,
  "timestamp": 0,
  "extension_schema_version": 1,
  "extension": {}
}
```

Core fields are finite and bounded. `server_type` is an enum (`world`, `login`);
unknown types are displayed as unknown and never executed. An incompatible core
schema is shown as unreadable. Unknown extensions are retained as bounded raw
fields for display only; they are never interpreted as authority.

Known extensions are small and present-focused:

- `world`: peer/action counts and bounded sector-generation queue/outcome state.
- `login`: account database health, active-session count, and bounded auth
  accept/reject counters.
- Enrollment and host-firewall appear as systemd-status-only entries initially.
  Canon, progression, magic, and Meridian counters remain future fog.

## Transport and registry

Each server writes one atomic `ops_snapshot.json` into the fixed host directory
`/var/lib/project0/ops-snapshots/<server_id>/`. The console mounts that
 directory read-only. Writes occur with the existing health cadence (about 0.5
seconds). The console polls at 2 seconds and marks a snapshot stale after 3
consecutive missed cadences; it cross-checks systemd state where available.

The live registry is the directory scan keyed by `server_id`. A small static
manifest supplies `server_type`, systemd unit, and control target metadata. A
new server must emit a valid snapshot, write to the directory, and add one
manifest row. Duplicate ids and unknown manifest types are rejected.

Promote to an HTTP read endpoint only if the shared read-only file cannot meet
freshness, multi-host, or access-control needs; that promotion is a separate
versioned slice.

## Control plane

Tier 1 is read-only telemetry. Tier 2 uses one versioned `ControlAction` request
and `ControlResult` response. The bounded catalog is:

- host helper: `start`, `stop`, `restart` systemd units;
- authoritative Godot seam: `kick_peer`, `drain`, `reload_tuning`,
  `set_degraded`.

Every action is idempotent, bounded, audited, and returns an enum result. The
console is never trusted to authorize itself. Both the host helper and Godot
seam independently verify an operator token derived from the existing assertion
primitive, carrying `operator_identity` and `granted_scopes`. Today one LAN
operator has all scopes; RBAC can replace issuance later without changing the
control contract.

## Console surface

The standalone Python stdlib `http.server` service has:

- a fleet view with one row per registry entry, status, freshness, and key gauges;
- a server detail view with core snapshot, known extension, raw unknown extension,
  and bounded action controls;
- two-second polling and explicit stale/unreadable states;
- confirmation for stop/restart; no gameplay or Canon mutation controls.

It uses its own Dockerfile/port, LAN binding, read-only snapshot/manifest mounts,
and no new web framework dependency.

## Implementation sequence

1. Slice 184: pure `OpsSnapshot` contract, validation, and GUT tests.
2. Slice 185: health reporter atomic snapshot writer and world/login emitters.
3. Slice 186: registry manifest and directory scanner with freshness handling.
4. Slice 187: read-only console fleet/detail surface and container packaging.
5. Slice 188: versioned ControlAction/ControlResult contracts and audit records.
6. Slice 189: authenticated Godot control seam and host helper.
7. Slice 190: end-to-end console read/control proof and operational runbook.

No slice above claims implementation until its own public-seam validation passes.
