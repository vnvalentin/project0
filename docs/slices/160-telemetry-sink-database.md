# Slice 160 - Telemetry sink + dedicated database

GitHub issue: #332

Status: **delivered**

Phase: 13 (Delivery workflow capabilities)

Feature: [F-038](../FEATURE-LIST.md#f-038-cross-cutting-telemetry-pipeline-envelope-transport-storage-dashboard)

## User outcome

A validated telemetry event can be durably written to a dedicated
server-owned database, distinct from Canon, with automatic bounding so the
raw event table never grows without limit on a home-server deployment.

## Scope and non-goals

In scope: `server/telemetry_sink.gd` — schema creation (`ensure_schema()`),
validated writes (`emit()`, using `shared/telemetry_event.gd`'s `validate()`
from Slice 159), and opportunistic retention/row-ceiling enforcement.

Out of scope (tracked under [F-038](../FEATURE-LIST.md#f-038-cross-cutting-telemetry-pipeline-envelope-transport-storage-dashboard),
see [issue #328](https://github.com/vnvalentin/project0/issues/328)): wiring
a live `TelemetrySink` into the server boot sequence, the client-to-server
transport RPC, the connection-lifecycle and combat-outcome emission call
sites, and the dashboard `/telemetry` page.

## Public seam

`TelemetrySink._init(store: SqliteStore, row_ceiling: int =
MAX_ROW_CEILING)`, `ensure_schema() -> Dictionary`, and `emit(event:
Dictionary) -> Dictionary`. `resolve_db_path()` honors
`PROJECT0_TELEMETRY_DB_PATH`, matching the `PROJECT0_CANON_DB_PATH`
convention, for whichever future slice wires this into server boot.

## Falsifiable hypothesis

If every write goes through `TelemetrySink.emit()`, which validates before
insert and opportunistically enforces a 30-day retention window plus a hard
row ceiling on every call, then the `events` table can never contain a
rejected event and can never grow past its bounds regardless of emission
volume.

## BDD

1. `ensure_schema()` is idempotent — calling it twice on the same store
   succeeds both times.
2. A structurally valid event is written and readable back with its payload
   intact (JSON round-trip).
3. An event that fails `TelemetryEvent.validate()` is rejected and nothing is
   written.
4. `emit()` on a closed store fails closed (`OUTCOME_NOT_OPEN`) rather than
   crashing or silently no-op'ing.
5. An event older than the 30-day retention window is deleted by the next
   `emit()` call, while a recent event survives.
6. When the row count exceeds the configured ceiling, the oldest rows are
   trimmed first, down to the ceiling.

## TDD / validation

Focused public-seam tests in `tests/integration/test_telemetry_sink.gd`
(a real temporary `user://` SQLite database via `SqliteStore`, mirroring
`tests/integration/test_vessel_repository.gd`) cover all six BDD scenarios,
then the full GUT suite and record-sync check provide delivery evidence.

## Safety invariants

- Every write path validates through `shared/telemetry_event.gd` first; the
  sink never writes an event `validate()` would reject.
- Retention and row-ceiling enforcement run on every `emit()` (write-time,
  not a scheduled job), so bounding cannot silently stop happening.
- `_row_ceiling` is only overridable via the constructor (for tests); the
  production default is the documented 2,000,000-row `MAX_ROW_CEILING`.

## Ownership note

Copilot is implementing this slice under the standing authorization
(reaffirmed by the user 2026-09-19) because the local Claude CLI is
unavailable/interactive-only on this Windows machine (see repository memory
`implementation-ownership.md`). Implemented in an isolated git worktree
(`slice/160-telemetry-sink-database`) alongside unrelated in-progress
uncommitted work already present in the primary working tree.

## Root-cause learning

Two focused-test failures surfaced during validation, both test-fixture bugs
rather than production defects:

- **Symptom**: `test_valid_event_is_written_and_readable` reported 0 rows
  written even though `emit()` returned `OUTCOME_OK`.
- **Falsifiable hypothesis**: the test's default fixed timestamp (an old,
  arbitrary constant) was older than the 30-day retention cutoff computed
  against the real current clock, so `_enforce_retention()`'s write-time
  `DELETE` removed the row immediately after insert.
- **Discriminating check**: re-ran with a current-time default timestamp;
  the row persisted.
- **Confirmed root cause**: test fixture used a stale hardcoded timestamp
  instead of deriving it from `Time.get_unix_time_from_system()`.
- **Why existing tests missed it**: this was the first test exercising
  retention deletion at all — Slice 159 had no sink/retention code yet.
- **Countermeasure**: `_event()`'s default `emitted_at_unix` now derives from
  the real clock; only the retention/ceiling tests pass explicit
  now-relative offsets.
- **Regression evidence**: `test_valid_event_is_written_and_readable` and
  `test_row_ceiling_trims_oldest_rows_first` both pass in the final run
  (791/791 total).
- **Remaining limitation**: none — this was fixture-only, no production
  code changed as a result.

A second, unrelated failure (`test_multi_peer_replication_e2e.gd`,
timing-sensitive disconnect-propagation assertion) appeared in one run and
passed cleanly when re-run in isolation immediately after — confirmed as
pre-existing E2E flakiness, not a regression introduced by this slice (no
production code in this slice touches networking, replication, or
disconnect handling).

## Validation evidence

This slice's `server/telemetry_sink.gd` depends on the `SQLite`
GDExtension, so it has no Windows-runnable focused-test path (per repository
memory: `godot-sqlite` has no Windows native library in this checkout).

Full validation on a fresh Linux-host clone of this branch (with the
host's already-built `godot-sqlite`/`wgnetstack` native binaries copied in):
`bash scripts/run_gut_validation.sh` — **108 scripts, 791/791 tests passing,
2490 asserts, exit 0**. `bash scripts/check_record_sync.sh` — **0 errors, 6
pre-existing warnings** (Slices 002, 003, 009, 010, 038, 041 — unrelated to
this slice).
