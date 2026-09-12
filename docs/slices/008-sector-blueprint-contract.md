# Slice 008: Async validated sector blueprint contract

Tracker context: Phase 8 — JIT world generation and local inference; advances
[IP-004](../FEATURE-LIST.md#ip-004-structured-sector-blueprint-translation).
Planning ticket: [game-vision issue 15](../.scratch/game-vision/issues/15-sector-blueprint-contract.md).

## SDD

Goal: Define and validate a versioned JSON sector blueprint returned by the
server-side local Ollama request seam without generating geometry, blocking the
multiplayer loop, or persisting Canon state.

Public seams:

- `shared/sector_blueprint_schema.gd` — validates parsed blueprint data.
- `server/sector_blueprint_service.gd` — performs an asynchronous Ollama
  request, records correlation/provenance, and returns structured outcomes.
- `tests/integration/test_sector_blueprint_contract.gd` — fixture-backed
  public-seam GUT integration test using a local fake HTTP harness.

Contract: a valid blueprint contains `schema_version: 1`, a non-empty
`sector_id`, an origin coordinate, and at least one tile whose coordinates are
bounded by `MAX_COORDINATE_ABS` and whose kind is one of `floor`, `wall`, or
`corridor`. The validator returns an explicit outcome and never partially
accepts invalid data.

Safety invariant: no blueprint is converted into geometry, gameplay state,
SQLite data, or Canon state by this slice. Ollama is called server-side only.
A request carries an in-memory correlation id and provenance; no secrets or
responses are persisted.

## BDD

### Valid blueprint

Given a parsed version-one blueprint with a sector id, origin, and supported
bounded tiles
When the schema validator runs
Then it returns `valid` and the validated blueprint.

### Invalid blueprint

Given malformed, incomplete, wrong-version, over-sized, or unsupported-kind
or out-of-bounds data
When the schema validator runs
Then it returns a specific failure outcome and no blueprint.

### Bounded async failure

Given a fake Ollama response that returns HTTP failure, malformed envelope, or
no response
When the service request runs
Then it returns a structured transport/timeout outcome within the configured
request timeout and the SceneTree continues processing frames.

### Correlation

Given two requests issued through the service
When both complete
Then each result has a unique correlation id and retrievable in-memory
provenance.

## TDD evidence

`tests/integration/test_sector_blueprint_contract.gd` exercises the validator
and async service at their public seams through GUT. The fake HTTP harness
makes valid, malformed, HTTP-error, timeout, non-blocking, and correlation
cases deterministic without requiring Ollama to be running.

## ADR decision

No new ADR. This slice introduces no world-state ownership, persistence, or
runtime gameplay boundary. It defines a validation contract and an async
server-side request seam; canonicalization and geometry remain future decisions.

## Validation

- `godot --headless --path . --editor --quit`: PASS, exit 0.
- `scripts/run_gut_validation.sh`: PASS, 14/14 tests and 38 assertions, exit
  0; telemetry written to `build/validation/gut.xml` and
  `build/validation/validation-summary.json`, including origin/tile
  coordinate-bound assertions.
- Existing slices remain the required regression suite. A missing
  `scripts/test_authoritative_movement.gd` was detected during this delivery
  review and is tracked as a repair item under
  [DT-006](../TECHNICAL-DEBT-TRACKER.md#dt-006-remaining-hand-rolled-smoke-tests-not-yet-migrated-to-gut);
  Slice 004's documentation still describes the seven-assertion public-seam
  test that must be restored before the full regression suite can be called
  green. Restoring it is outside Slice 008's public seam and is not
  remediated by this slice.

## Explicit non-goals and next boundary

This slice does not detect unexplored boundaries, create sector meshes, add
quests, retry model calls, write SQLite, or create Canon. The next generation
slice must decide how a validated blueprint is translated into provisional
world content without blocking active multiplayer sessions.
