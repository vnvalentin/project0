# Slice 046 — Authoritative sector-boundary detection for JIT generation
GitHub issue: #95

Status: **delivered**

Phase: 8 (JIT world generation and local inference), advancing IP-008.
This slice consumes the Canon lookup seam from Slice 045 and the provisional
generation seam from Slice 009.

## User outcome

When an authoritative Player crosses into a new sector, the server identifies
that sector once and requests a provisional blueprint only when Canon does not
already contain it. The detector is synchronous and cheap; generation remains
asynchronous and never blocks movement or the multiplayer loop.

## Scope and non-goals

In scope: floor-based X/Z sector mapping, per-peer sector transition state,
Canon suppression, duplicate-request suppression, and a bounded request signal.

Out of scope: client position authority, geometry, retries, boundary padding,
async result canonicalization, mutation events, and account flow.

## Public seam

`server/sector_boundary_detector.gd` exposes `observe_position(peer_id,
position)`, `set_canon_lookup(Callable)`, and `set_request_callback(Callable)`.
It emits `sector_generation_requested(peer_id, sector_id, position)` only for
an unseen sector transition. A lookup returning true suppresses generation.

## BDD / TDD

`tests/unit/test_sector_boundary_detector.gd` covers origin mapping, negative
coordinates, per-peer transitions, Canon suppression, and duplicate requests.

## Safety invariant

The detector uses only server-authoritative positions and never accepts or
creates a client-supplied blueprint. It does not write Canon state.

## ADR rationale

No new ADR. Server authority and non-blocking JIT generation are already
normative in `CLAUDE.md`, Slice 009, and the accepted IP-008 planning ticket.

## Validation

Focused validation: unit GUT path passed 184/184 tests across 22 scripts,
exit 0. `server/server_main.gd` check-only passed, exit 0. Full validation:
`scripts/run_gut_validation.sh` passed 278/278 tests across 38/38 scripts and
1063 assertions, exit 0. The record-sync gate remains required after this
record update.
