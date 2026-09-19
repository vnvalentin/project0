# Slice 161 - Telemetry transport contracts (client batch queue + server rate limiter)

GitHub issue: #334

Status: **delivered**

Phase: 13 (Delivery workflow capabilities)

Feature: [F-038](../FEATURE-LIST.md#f-038-cross-cutting-telemetry-pipeline-envelope-transport-storage-dashboard)

## User outcome

The two independent, testable pieces the client-to-server telemetry
transport needs — a client-side batching cadence and a server-side per-peer
rate limiter — exist and behave correctly in isolation, before any RPC or
scene-tree wiring commits either codebase's shared hot-spot files
(`client/network_client.gd`, `server/server_main.gd`) to that shape.

## Scope and non-goals

In scope: `client/telemetry_batch_queue.gd` (accumulate events, report a
~250ms flush cadence, drain on demand) and `server/telemetry_rate_limiter.gd`
(per-peer token bucket; a whole over-budget batch is silently dropped and
counted, never partially trimmed, and the peer is never disconnected).

Out of scope (tracked under [F-038](../FEATURE-LIST.md#f-038-cross-cutting-telemetry-pipeline-envelope-transport-storage-dashboard),
see [issue #328](https://github.com/vnvalentin/project0/issues/328)): the
actual `receive_client_telemetry_batch_on_server` RPC declaration, wiring the
batch queue into `client/network_client.gd`'s send path, wiring the rate
limiter into the server's RPC entry point and peer-disconnect cleanup, and
any connection/combat emission call sites. This mirrors the existing
version-handshake precedent: [Slice 145](145-version-handshake-contract.md)
delivered the pure contract; [Slice 146](146-version-gate-enforcement.md)
wired it live. `client/network_client.gd` and `server/server_main.gd` are
also flagged as shared hot-spot files in
[PROJECT-TRACKER.md](../PROJECT-TRACKER.md) with unrelated in-progress work
already touching them; keeping this slice out of those files avoids
conflict.

## Public seam

`TelemetryBatchQueue.new(now_msec)`, `.enqueue(event)`, `.should_flush(
now_msec) -> bool`, `.take_batch(now_msec) -> Array[Dictionary]`,
`.pending_count() -> int`.

`TelemetryRateLimiter.new()`, `.try_consume(peer_id, event_count, now_unix)
-> bool`, `.rate_limited_count(peer_id) -> int`, `.forget_peer(peer_id)`.

## Falsifiable hypothesis

If the client queue only reports "flush now" once its interval has elapsed
AND at least one event is pending, and the server limiter only admits a
batch when its per-peer bucket holds enough tokens (refilling over real
time, capped at capacity, and reset on `forget_peer`), then a live RPC
wiring slice can adopt both without reimplementing timing or budget logic.

## BDD

1. An empty queue never reports a flush, however much time has passed.
2. A queue with pending events reports no flush before the interval elapses,
   and reports a flush once it has.
3. Draining a queue returns every pending event and resets its pending count
   and flush clock.
4. A batch within a peer's remaining token budget is admitted and deducts
   tokens; a batch exceeding it is rejected as a whole (no partial
   admission) and increments that peer's rejected-batch count without
   touching its tokens.
5. Tokens refill over elapsed real time, bounded at capacity even after a
   very long idle gap.
6. Distinct peers have fully independent buckets and rejection counts.
7. Forgetting a peer resets both its bucket (to a fresh full bucket) and its
   rejection count.

## TDD / validation

Focused public-seam tests in `tests/unit/test_telemetry_batch_queue.gd` (6
tests) and `tests/unit/test_telemetry_rate_limiter.gd` (8 tests) cover all
BDD scenarios; then the full GUT suite and record-sync check provide
delivery evidence.

## Safety invariants

- Neither class reads the engine clock itself; callers always supply
  `now_msec`/`now_unix`, keeping both deterministic and testable.
- The rate limiter never disconnects a peer or partially admits a batch —
  an over-budget batch is rejected as a whole, matching decision #284's
  "silent drop, never disconnect" rule.
- `forget_peer` exists specifically so a future live-wiring slice can call
  it on peer disconnect and avoid unbounded bucket-dictionary growth across
  reconnects.

## Ownership note

Copilot is implementing this slice under the standing authorization
(reaffirmed by the user 2026-09-19) because the local Claude CLI is
unavailable/interactive-only on this Windows machine (see repository memory
`implementation-ownership.md`). Implemented in an isolated git worktree
(`slice/161-telemetry-transport-contracts`) to avoid touching
`client/network_client.gd`/`server/server_main.gd`, which carry unrelated
in-progress uncommitted work in the primary working tree.

## Validation evidence

Neither new file depends on the `SQLite` GDExtension, so both were fully
validated on Windows: `godot --headless -s addons/gut/gut_cmdln.gd
-gselect=test_telemetry_batch_queue -gdisable_colors -gexit` — **6/6 tests
passed**; `godot --headless -s addons/gut/gut_cmdln.gd
-gselect=test_telemetry_rate_limiter -gdisable_colors -gexit` — **8/8 tests
passed**.

Full validation on a fresh Linux-host clone of this branch (with the host's
already-built `godot-sqlite`/`wgnetstack` native binaries copied in): `bash
scripts/run_gut_validation.sh` — **110 scripts, 805/805 tests passing, 2515
asserts, exit 0**. `bash scripts/check_record_sync.sh` — **0 errors, 6
pre-existing warnings** (Slices 002, 003, 009, 010, 038, 041 — unrelated to
this slice).
