# Slice 165 - Dashboard telemetry page

GitHub issue: #353

Status: **delivered**

Phase: 13 (Delivery workflow capabilities)

Feature: [F-038](../FEATURE-LIST.md#f-038-cross-cutting-telemetry-pipeline-envelope-transport-storage-dashboard)

## User outcome

An operator/developer opens `/telemetry` on the existing dashboard and sees
top-line counters plus a filterable raw-event browser over the live
`telemetry.db`, without needing direct host/SSH access to the game server's
data directory. This is the last slice in the telemetry pipeline's original
route: the full envelope-to-storage-to-consumption path is now live.

## Scope and non-goals

In scope: `dashboard/app.py` gains `telemetry_model()` (read-only query
layer) and `render_telemetry()` (the page), wired to a new `/telemetry`
route; `deploy/compose.yml`'s dashboard service gains a new read-only mount
of the game server's data directory so the container can reach
`telemetry.db` (which lives outside the read-only `/repo` mount already
used for tracker files).

Out of scope: writing to telemetry.db (the dashboard has no write endpoint
anywhere and this page does not become the exception), aggregation/rollup
views (fog per the map), and any change to the telemetry emission pipeline
itself (Slices 159-164).

## Public seam

`GET /telemetry` — optional query params `event_type`, `account_id`,
`peer_id` filter the raw-event table; omitting all three shows the most
recent events across every family.

## Falsifiable hypothesis

If the event-type filter dropdown is populated by `SELECT DISTINCT
event_type FROM events` rather than a hardcoded list, then the page
requires zero code changes when a new event family (e.g. the still-fogged
client-UI or login/auth families) starts writing to `telemetry.db`.

## BDD

1. The page loads successfully when `telemetry.db` exists and is reachable,
   showing total-event, event-type, and row-ceiling-percentage counters.
2. The page degrades to a visible source warning (matching the existing
   `/tests` page's pattern) rather than crashing when the database is
   missing or unreadable.
3. Selecting an `event_type` in the filter form narrows the table to only
   that type; an empty filter shows the most recent events across every
   type.
4. The event-type filter dropdown lists exactly the types present in the
   data (verified with a database containing 4 event types across 2
   families) — never a hardcoded family list.
5. The page opens the database strictly read-only (`file:...?mode=ro`); no
   write path exists on this route.

## TDD / validation

`dashboard/app.py` has no existing automated test suite (validated via
manual smoke-check + the `project0-dashboard` CI image-build job, matching
this file's established practice — there is no `dashboard/tests/`
directory to extend). This slice was validated by running the dashboard
locally against a real sample `telemetry.db` (matching the exact schema
`server/telemetry_sink.gd` creates) and inspecting the rendered HTML
directly for both the unfiltered and filtered cases.

## Safety invariants

- The database connection is opened with SQLite's `mode=ro` URI parameter,
  the same "no write endpoint" invariant the rest of the dashboard already
  holds — a read-only bind mount reinforces this at the container level
  too.
- A missing or corrupt database degrades to a visible warning, never a
  crash, matching the `/tests` page's `source unavailable` precedent.
- All rendered values pass through the existing `esc()` HTML-escaping
  helper — no unescaped telemetry payload content reaches the page.

## Ownership note

Copilot is implementing this slice under the standing authorization
(reaffirmed by the user 2026-09-19) because the local Claude CLI is
unavailable/interactive-only on this Windows machine (see repository memory
`implementation-ownership.md`). This slice edits `dashboard/app.py`, which
had unrelated in-progress uncommitted work on another branch in the primary
working tree. Implemented in an isolated git worktree
(`slice/165-dashboard-telemetry-page`).

## Validation evidence

`python -m py_compile dashboard/app.py` — no syntax errors.

Manual end-to-end check: created a sample `telemetry.db` (same schema as
`server/telemetry_sink.gd`) with 4 rows across `connection.*`/`combat.*`
families, ran `dashboard/app.py` locally against it via
`TELEMETRY_DB_PATH`, and fetched both `/telemetry` (unfiltered) and
`/telemetry?event_type=combat.hit` (filtered) over real HTTP:

- Both requests returned HTTP 200.
- Unfiltered page showed `4` total events, `4` event types, `0.0%` of the
  row ceiling, and one pill per event type with its count.
- Filtered page's table contained exactly 1 row (`combat.hit` /
  `target_dummy_0`), confirming the filter narrows correctly.

CI's `project0-dashboard` image-build job (unchanged) provides container
build validation; `bash scripts/check_record_sync.sh` — **0 errors, 6
pre-existing warnings** (Slices 002, 003, 009, 010, 038, 041 — unrelated to
this slice).
