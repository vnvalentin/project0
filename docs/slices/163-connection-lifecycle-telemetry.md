# Slice 163 - Connection-lifecycle telemetry emission

GitHub issue: #347

Status: **delivered**

Phase: 13 (Delivery workflow capabilities)

Feature: [F-038](../FEATURE-LIST.md#f-038-cross-cutting-telemetry-pipeline-envelope-transport-storage-dashboard)

## User outcome

Every connection-lifecycle transition (connect, version-gate pass/reject,
house assignment/exhaustion, disconnect) is now durably captured in the
telemetry database with its decided per-event fields, giving both
engineering diagnosis and future player-behavior analysis real data to work
from instead of only ephemeral stdout `print()` lines.

## Scope and non-goals

In scope: a new `_emit_connection_telemetry()` direct-emission helper in
`server/server_main.gd`, and wiring it into the 6 events decided in
[#285](https://github.com/vnvalentin/project0/issues/285):
`connection.peer_connected`, `connection.version_gate_rejected`/`passed`,
`connection.house_assigned`/`house_unavailable`, `connection.peer_disconnected`.

Out of scope (tracked under [F-038](../FEATURE-LIST.md#f-038-cross-cutting-telemetry-pipeline-envelope-transport-storage-dashboard),
see [issue #328](https://github.com/vnvalentin/project0/issues/328)):
combat-outcome emission and the dashboard `/telemetry` page. Login/auth
events (on the separate login server process) remain fog, per the map.

## Public seam

`_emit_connection_telemetry(event_type: String, peer_id: int, payload:
Dictionary) -> void` (private to `server_main.gd`) — a direct, non-rate-
limited emission path for events the server itself observes, distinct from
Slice 162's `TelemetryIngestService` path for untrusted client batches.

## Falsifiable hypothesis

If `_emit_connection_telemetry` resolves `character_id` from the server's
own `_player_states` map (never trusted from anywhere else, since these are
server-observed events with no client input at all) and is called at the
exact 6 lifecycle points decided in #285, then a real connect→gate→house→
disconnect cycle produces exactly those 4-6 rows (depending on whether the
gate passes) in `telemetry.db`, in event order, with the fields #285
specified.

## BDD

1. A peer connecting emits `connection.peer_connected` with an empty
   payload.
2. A peer failing the version gate emits `connection.version_gate_rejected`
   with `{outcome, detail, client_version}`; a peer passing it emits
   `connection.version_gate_passed` with `{client_version}`.
3. A peer assigned a house emits `connection.house_assigned` with
   `{house_id, houses_free_after}`; a peer finding the pool exhausted emits
   `connection.house_unavailable` with `{houses_free}` instead.
4. A disconnecting peer emits `connection.peer_disconnected` with
   `{had_house, houses_free_after}`, where `had_house` reflects whether that
   peer actually held a house immediately before release.
5. `_emit_connection_telemetry` is a silent no-op when the server has no
   telemetry sink available (matching Slice 162's degrade-gracefully rule).

## TDD / validation

This slice's logic lives inside `server_main.gd`'s connection-lifecycle
handlers, which (like the rest of that file's RPC/lifecycle dispatch) are
exercised through the full GUT suite's existing e2e harnesses rather than a
new isolated unit test — matching how the original `print()` call sites
were themselves untested before this slice. As direct behavioral evidence
beyond "the suite still passes", a manual end-to-end check (documented
below under Validation evidence) booted a real server, drove a real
ENet client connect→handshake→disconnect cycle through it, and confirmed
the exact 4 resulting rows and payload shapes in `telemetry.db`.

## Safety invariants

- `character_id` is resolved from the server's own peer→Player state
  mapping, matching the same rule Slice 162 established for client-
  submitted telemetry (never trust an external source for identity).
- No rate limiting applies to server-authored events (there is no
  untrusted input volume to bound) — this path is intentionally simpler
  than `TelemetryIngestService`'s.
- A telemetry-unavailable server degrades this to a silent no-op, per the
  established "telemetry never blocks the core game loop" invariant.

## Ownership note

Copilot is implementing this slice under the standing authorization
(reaffirmed by the user 2026-09-19) because the local Claude CLI is
unavailable/interactive-only on this Windows machine (see repository memory
`implementation-ownership.md`). This slice edits `server/server_main.gd`,
flagged as a shared hot-spot file in [PROJECT-TRACKER.md](../PROJECT-TRACKER.md)
with unrelated in-progress uncommitted work on another branch
(`docs/roadmap-wayfinder-reassessment`). Implemented in an isolated git
worktree (`slice/163-connection-lifecycle-telemetry`) to avoid touching that
work.

## Validation evidence

Windows: `godot --headless --check-only -s server/server_main.gd` produces
only the pre-existing SQLite-GDExtension-unavailable cascade (no new parse
errors attributable to this slice's edits).

Full validation on a fresh Linux-host clone of this branch (with the host's
already-built `godot-sqlite`/`wgnetstack` native binaries copied in): `bash
scripts/run_gut_validation.sh` — **111 scripts, 811/811 tests passing, 2528
asserts, exit 0**. `bash scripts/check_record_sync.sh` — **0 errors, 6
pre-existing warnings** (Slices 002, 003, 009, 010, 038, 041 — unrelated to
this slice).

Manual end-to-end confirmation (throwaway scripts, not committed): booted
`server/server_main.gd` directly on the Linux host, drove a real client
connection through `NetworkClient.connect_to_server()`, then disconnected.
Reading `telemetry.db` afterward showed exactly the expected 4 rows in
order:

```
connection.peer_connected        {}
connection.version_gate_passed   {"client_version":"0.6.0"}
connection.house_assigned        {"house_id":"house_01","houses_free_after":9}
connection.peer_disconnected     {"had_house":true,"houses_free_after":10}
```
