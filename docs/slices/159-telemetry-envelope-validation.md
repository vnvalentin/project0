# Slice 159 - Telemetry envelope + validation

GitHub issue: #329

Status: **delivered**

Phase: 13 (Delivery workflow capabilities)

Feature: [F-038](../FEATURE-LIST.md#f-038-cross-cutting-telemetry-pipeline-envelope-transport-storage-dashboard)

## User outcome

Every future telemetry event (client interaction, connection lifecycle,
combat outcome, or network communication) is shaped and screened by one
shared contract before it can reach a sink, so no future emission slice has
to reinvent field shape, versioning, size bounds, or privacy screening.

## Scope and non-goals

In scope: `shared/telemetry_event.gd` — envelope construction (`build()`) and
mechanical validation (`validate()`): required-field shape, per-event_type
`schema_version` handling, a ~2KB estimated-size cap, and a privacy denylist
over payload keys and free-text-length values.

Out of scope (tracked separately under [F-038](../FEATURE-LIST.md#f-038-cross-cutting-telemetry-pipeline-envelope-transport-storage-dashboard),
see [issue #328](https://github.com/vnvalentin/project0/issues/328)):
the client-to-server transport RPC, the dedicated `telemetry.db` sink and
retention policy, the connection-lifecycle and combat-outcome emission call
sites, and the dashboard `/telemetry` page.

## Public seam

`TelemetryEvent.build(event_type, schema_version, emitted_at_unix,
server_tick, peer_id, payload, account_id, character_id, session_id) ->
Dictionary` and `TelemetryEvent.validate(event: Dictionary) -> {outcome,
detail}`.

## Falsifiable hypothesis

If every telemetry event is shaped through one `build()`/`validate()` pair
with a per-event_type `schema_version` and a mechanical privacy denylist,
then a malformed, oversized, or privacy-violating event can never reach a
sink, while an event with an unrecognized (but future) `schema_version` is
still accepted rather than silently dropped.

## BDD

1. A structurally valid event with a small, non-denylisted payload is
   accepted.
2. An event missing a required field, or with a wrong-typed field, is
   rejected as malformed.
3. An event whose payload contains a denylisted key (password/token/secret/
   credential/ip/cookie, case-insensitive) is rejected for privacy.
4. An event whose payload contains a string value at or above the free-text
   length threshold is rejected for privacy, even under a non-denylisted key.
5. An event whose estimated serialized size exceeds the size cap is rejected
   for size.
6. An event carrying an unrecognized `schema_version` is still accepted —
   `validate()` never treats "unknown version" as a rejection reason.

## TDD / validation

Focused public-seam tests in `tests/unit/test_telemetry_event.gd` cover all
six BDD scenarios, then the full GUT suite and record-sync check provide
delivery evidence.

## Safety invariants

- `validate()` is pure and side-effect free: no database, RPC, or system
  clock access. Callers supply `emitted_at_unix` (always server wall-clock).
- Privacy screening is mechanical (a denylist function), not left to
  emission-site convention.
- An unrecognized `schema_version` is a future sink concern (store raw), not
  a validation failure — validation never silently drops forward-compatible
  data.

## Ownership note

Copilot is implementing this slice under the standing authorization because
the local Claude CLI is unavailable/interactive-only on this Windows machine
(see repository memory `implementation-ownership.md`). This slice was
implemented in an isolated git worktree
(`slice/159-telemetry-envelope-validation`) to avoid disturbing unrelated
in-progress uncommitted work already present in the primary working tree.

## Validation evidence

Focused validation on Windows: `godot --headless -s addons/gut/gut_cmdln.gd
-gselect=test_telemetry_event -gdisable_colors -gexit` — **11/11 tests
passed, 24 asserts**.

Full validation on the Linux host (fresh clone of this branch, plus the
host's already-built `godot-sqlite`/`wgnetstack` native binaries copied in):
`bash scripts/run_gut_validation.sh` — **107 scripts, 785/785 tests passing,
2475 asserts, exit 0**. `bash scripts/check_record_sync.sh` — **0 errors, 6
pre-existing warnings** (Slices 002, 003, 009, 010, 038, 041 — unrelated to
this slice).
