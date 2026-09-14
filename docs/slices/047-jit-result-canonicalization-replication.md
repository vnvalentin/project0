# Slice 047 — JIT result canonicalization and sector replication

Status: **delivered**

Phase: 8 (JIT world generation and local inference) and Phase 9 (Canon
persistence and world mutation), advancing IP-008, P-011, and P-012.

## User outcome

When asynchronous generation succeeds, the server stores the blueprint as
immutable Canon and reliably sends the stored blueprint to connected clients.
Transport failures, schema failures, and conflicting regeneration never become
visible world state.

## Scope and non-goals

In scope: structured generator-result finalization, Canon delegation, replay
handling, and reliable broadcast to currently connected peers.

Out of scope: geometry changes, client authority, mutation events, retries,
LLM prompt policy, and account flow.

## Public seam

`server/canon_generation_coordinator.gd` exposes
`accept_generation_result(sector_id, result)` and emits
`canonical_sector_ready(sector_id, blueprint)` only for `ok` or `idempotent`
Canon outcomes. `server/server_main.gd` connects that signal and calls the
existing reliable `receive_sector_blueprint` RPC for each connected peer.

## Safety invariant

Clients receive only the blueprint returned by Canon storage, never the raw
provisional generator payload. A failed or conflicting result emits nothing.

## BDD / TDD

`tests/unit/test_canon_generation_coordinator.gd` covers successful first-write,
idempotent replay, transport failure, schema failure, and Canon conflict.

## ADR rationale

No new ADR. Server authority, strict validation, immutable Canon, and reliable
blueprint replication are already established by `CLAUDE.md` and Slices 017,
045, and 046.

## Validation

Focused coordinator validation passed after forced Godot import: 188/188 unit
tests, exit 0. Server parse check passed, exit 0. Full validation telemetry:
`scripts/run_gut_validation.sh` passed 282/282 tests across 39/39 scripts and
1073 assertions, exit 0. Record sync passed with 0 errors and 6 pre-existing
warnings.