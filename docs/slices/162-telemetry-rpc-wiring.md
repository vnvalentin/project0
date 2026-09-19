# Slice 162 - Live telemetry RPC wiring

GitHub issue: #345

Status: **delivered**

Phase: 13 (Delivery workflow capabilities)

Feature: [F-038](../FEATURE-LIST.md#f-038-cross-cutting-telemetry-pipeline-envelope-transport-storage-dashboard)

## User outcome

A client can submit telemetry events that reach the dedicated telemetry
database over a live, rate-limited, unreliable RPC, with every
trust-sensitive field (peer identity, character identity, timestamp, server
tick) resolved authoritatively on the server — never taken from the client's
claim.

## Scope and non-goals

In scope: the live `receive_client_telemetry_batch_on_server` RPC and its
periodic-flush send path in `client/network_client.gd`; boot-wiring a
`TelemetrySink` + `TelemetryRateLimiter` in `server/server_main.gd`
(best-effort, non-fatal — a DB-open failure never refuses server start);
`server/telemetry_ingest_service.gd`, the new orchestration class that owns
rate limiting, envelope construction, and the write, keeping the RPC
handler itself a thin, testable-by-delegation dispatcher (mirroring
`server/character_service.gd`'s established seam pattern).

Out of scope (tracked under [F-038](../FEATURE-LIST.md#f-038-cross-cutting-telemetry-pipeline-envelope-transport-storage-dashboard),
see [issue #328](https://github.com/vnvalentin/project0/issues/328)):
connection-lifecycle and combat-outcome emission call sites (no code calls
`NetworkClient.queue_telemetry_event()` yet — the plumbing exists, nothing
produces events through it), and the dashboard `/telemetry` page.

## Public seam

Client: `NetworkClient.queue_telemetry_event(event_type, schema_version,
payload)`, drained automatically by `NetworkClient._process()` on the
~250ms cadence from `TelemetryBatchQueue` (Slice 161).

Server: `TelemetryIngestService.ingest_batch(peer_id, raw_events,
character_id, now_unix, server_tick) -> void`, called by
`server_main.gd::_on_client_telemetry_batch_received`, itself wired to
`NetworkClient.client_telemetry_batch_received`.

## Falsifiable hypothesis

If the RPC handler resolves `peer_id` from `multiplayer.get_remote_sender_id()`
and `character_id` from the server's own `_player_states` map, and
`TelemetryIngestService` only ever reads `event_type`/`schema_version`/
`payload` from the client-submitted Dictionary, then no client input can ever
forge another peer's identity, backdate an event, or claim a different
server tick — regardless of what the raw event Dictionary contains.

## BDD

1. A well-formed batch is written with the caller-supplied peer_id,
   character_id, timestamp, and server_tick — not read from the raw event.
2. A raw event that stuffs `peer_id`/`character_id`/`emitted_at_unix`/
   `server_tick` keys into itself has all of them ignored; the caller's
   values win.
3. A malformed raw event (wrong type, missing `event_type`, non-Dictionary
   entry) is skipped without aborting the rest of the batch.
4. A batch exceeding the rate limiter's per-peer budget writes nothing at
   all (matches Slice 161's whole-batch-rejected contract).
5. An empty batch is a no-op.
6. A server with no telemetry sink available (boot-time open failure) makes
   ingestion a silent no-op — never a crash, never a blocked game loop.

## TDD / validation

Focused public-seam tests in `tests/integration/test_telemetry_ingest_service.gd`
(6 tests, real temporary SQLite database via `TelemetrySink`) cover the
untrusted-input boundary directly. The RPC handler itself is a one-line
forwarder (mirroring this repo's established pattern of testing the
underlying service directly rather than the RPC-annotated function — see
`tests/integration/test_character_crud_rpc.gd`'s docstring). The full GUT
suite (which boots a real server via the existing e2e harnesses) and
record-sync check provide the remaining delivery evidence.

## Safety invariants

- The client can never claim its own `peer_id`, `character_id`,
  `emitted_at_unix`, or `server_tick` — every one of those fields is
  resolved server-side and any client-supplied value with those key names in
  the raw event Dictionary is silently ignored.
- A telemetry-unavailable server (DB open/schema failure at boot) degrades
  to a silent no-op rather than refusing to start or crashing at runtime —
  telemetry is diagnostic infrastructure, never a single point of failure
  for the authoritative game loop.
- The RPC is `unreliable`/`any_peer`; an over-budget or malformed batch is
  silently dropped and the peer is never disconnected over telemetry.

## Ownership note

Copilot is implementing this slice under the standing authorization
(reaffirmed by the user 2026-09-19) because the local Claude CLI is
unavailable/interactive-only on this Windows machine (see repository memory
`implementation-ownership.md`). This slice necessarily edits
`client/network_client.gd` and `server/server_main.gd`, both flagged as
shared hot-spot files in [PROJECT-TRACKER.md](../PROJECT-TRACKER.md) with
unrelated in-progress uncommitted work on another branch
(`docs/roadmap-wayfinder-reassessment`) in the primary working tree.
Implemented in an isolated git worktree
(`slice/162-telemetry-rpc-wiring`) to avoid touching that work; a future
merge of both branches may need manual conflict resolution in these two
files, noted here for awareness.

## Validation evidence

This slice depends on the `SQLite` GDExtension (via `TelemetrySink`), so it
has no fully Windows-runnable focused-test path; `client/network_client.gd`
and `server/telemetry_ingest_service.gd` were parse-checked cleanly on
Windows (`godot --headless --check-only -s <file>`), and the SQLite-free
`test_telemetry_batch_queue.gd`/`test_telemetry_rate_limiter.gd` from Slice
161 continue to pass on Windows unchanged.

Full validation on a fresh Linux-host clone of this branch (with the host's
already-built `godot-sqlite`/`wgnetstack` native binaries copied in): `bash
scripts/run_gut_validation.sh` — **111 scripts, 811/811 tests passing, 2528
asserts, exit 0** (includes the existing e2e harnesses, which boot a real
server process with this slice's boot-time telemetry wiring live). `bash
scripts/check_record_sync.sh` — **0 errors, 6 pre-existing warnings**
(Slices 002, 003, 009, 010, 038, 041 — unrelated to this slice).
