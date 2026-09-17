# Slice 009: Asynchronous provisional sector generation
GitHub issue: #95

Tracker context: Phase 8 — JIT world generation and local inference; advances
[P-008](../FEATURE-LIST.md#p-008-just-in-time-sector-generation).
Planning ticket: [game-vision issue 16](../.scratch/game-vision/issues/16-provisional-sector-generation.md).

## SDD

Goal: Provide the smallest public seam that accepts a sector-generation
request, drives the existing, unchanged Slice 008 `SectorBlueprintService`,
keeps the SceneTree/multiplayer loop responsive, and exposes an in-memory
provisional result/outcome — without generating geometry, detecting sector
boundaries, or persisting anything.

Public seam:

- `server/provisional_sector_generator.gd` — accepts a request keyed by
  sector id and prompt (`request_provisional_sector`), returns a correlation
  id synchronously without the caller awaiting generation, and exposes
  `get_status`, `get_correlation_id`, `get_provisional_result`, and the
  `provisional_sector_ready` completion signal.
- `tests/integration/test_provisional_sector_generation.gd` — fixture-backed
  public-seam GUT integration test using Slice 008's fake Ollama HTTP
  harness.

Contract: `request_provisional_sector(sector_id, prompt)` records a
`pending` in-memory entry and returns its correlation id immediately. The
actual `SectorBlueprintService.request_sector_blueprint()` request runs in a
deferred coroutine on a short-lived, per-request `SectorBlueprintService`
instance (a fresh instance per request, since a shared instance's single
child `HTTPRequest` node cannot run two requests at once). When the request
resolves — success, validation failure, transport error, or timeout — the
sector id's status becomes `ready`, its result Dictionary is stored in
memory (this seam's own `SectorBlueprintService` result shape), and
`provisional_sector_ready` is emitted. A second request for a sector id that
is already pending or ready returns the existing correlation id instead of
starting a duplicate request.

Safety invariant: no provisional result is converted into geometry, gameplay
state, SQLite data, or Canon state by this slice. Sector-boundary detection
(deciding *when* a sector needs generating) is out of scope. Ollama is
reached only through the unchanged, server-side-only
`SectorBlueprintService`/`LocalLLMClient` path; the client never calls
Ollama. All state is in-memory only, keyed by sector id, and lost on process
exit.

## BDD

### Request acceptance

Given a caller invokes `request_provisional_sector` with a new sector id
When the call returns
Then it returns a non-empty correlation id, the sector id's status is
`pending`, and no provisional result exists yet — all without the caller
awaiting the call.

### Success outcome

Given a fake Ollama response that returns a valid version-one blueprint
When the deferred request resolves
Then the sector id's status becomes `ready` and its stored result carries
the validated blueprint and `REQUEST_OUTCOME_VALIDATED`.

### Validation/transport/timeout failure

Given a fake Ollama response that is schema-invalid, returns an HTTP error,
or never responds
When the deferred request resolves
Then the sector id's status becomes `ready` with a structured failure
outcome (`validation_outcome` or `REQUEST_OUTCOME_TRANSPORT_ERROR` /
`REQUEST_OUTCOME_TIMEOUT`) and no blueprint, within a bounded window.

### Non-blocking behavior

Given a fake Ollama server that never responds
When a request is in flight
Then the SceneTree continues processing frames, and the request eventually
resolves to a bounded timeout outcome.

### Correlation and request state

Given two requests for different sector ids, and a repeated request for the
same sector id
When requests are accepted and resolved
Then each distinct sector id keeps its own stable correlation id and
independently retrievable state, and the repeated request for an existing
sector id does not start a second concurrent request.

### No persistence

Given any outcome of a provisional request
When the request resolves
Then no SQLite file or Canon record is created; the result is retrievable
only from this node's in-memory state for its lifetime.

## TDD evidence

`tests/integration/test_provisional_sector_generation.gd` exercises the
seam's public methods and signal through GUT: acceptance/pending state,
success, validation failure, transport failure, timeout, non-blocking
SceneTree processing, independent concurrent requests, repeated-request
dedup, and absence of any SQLite/db file at the project root. Slice 008's
fixtures and fake Ollama HTTP harness are reused unchanged.

## ADR decision

No new ADR. This slice adds a thin, in-memory request-orchestration seam
in front of an already-decided async service (Slice 008); it introduces no
new persistence mechanism, world-state ownership boundary, or runtime
authority change. Canonicalization, geometry translation, and
sector-boundary detection remain future decisions with their own ADRs if
warranted.

## Validation

- Focused: `godot --headless -s addons/gut/gut_cmdln.gd
  -gdir=res://tests/integration -gselect=test_provisional_sector_generation
  -gexit` — PASS, 9/9 tests, 32 assertions, exit 0.
- Full suite: `scripts/run_gut_validation.sh` — PASS, 23/23 tests, 70
  assertions, exit 0; telemetry written to `build/validation/gut.xml` and
  `build/validation/validation-summary.json`.
- No `.db`/`.sqlite` file is created anywhere in the repository by this
  seam or its tests (asserted directly in
  `test_result_state_is_in_memory_only_and_unknown_before_any_request`).

## Implementation notes and fixes made during delivery

Three defects were found and fixed by the focused tests before this slice
was considered complete, and are recorded here rather than left implicit:

1. Setting `SectorBlueprintService`'s `ollama_host`/`model_name`/
   `request_timeout_sec` *after* `add_child()` was too late, because its
   `_ready()` copies those into its own child `LocalLLMClient` synchronously
   on entering the tree. `ProvisionalSectorGenerator` now exposes its own
   `@export` passthrough properties, set before the underlying service is
   added as a child, matching Slice 008's own test convention of configuring
   before `add_child_autofree`.
2. A single shared `SectorBlueprintService` instance cannot run two
   concurrent requests — its one child `HTTPRequest` node fails a second
   `request()` call while the first is in flight. Each
   `request_provisional_sector` call now creates and frees its own
   short-lived `SectorBlueprintService` instance.
3. Overwriting the seam-level correlation id (returned at acceptance time)
   with `SectorBlueprintService`'s own internal correlation id on
   completion made the two ids diverge silently. The seam-level id is now
   preserved for the life of the entry, and a dedicated
   `get_correlation_id()` accessor avoids ambiguity with the nested service
   result's own `correlation_id` field.

## Explicit non-goals and next boundary

This slice does not generate geometry, detect sector boundaries, create
quests, retry model calls beyond `SectorBlueprintService`'s own bound, write
SQLite, create Canon state, or perform client-side Ollama calls or hardware/
inference deployment work. The next generation slice must decide how (and
when) an unexplored sector boundary triggers a provisional request, and how
a `ready` provisional result is eventually translated into Canon-eligible
content without blocking active multiplayer sessions.
