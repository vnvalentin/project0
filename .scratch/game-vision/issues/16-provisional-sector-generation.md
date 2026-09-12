Type: task
Status: resolved
Blocked by: 15

## Question
What is the smallest public seam that accepts a sector-generation request, drives the existing asynchronous SectorBlueprintService, keeps the SceneTree/multiplayer loop responsive, and exposes an in-memory provisional result without generating geometry, detecting sector boundaries, or persisting anything?

## Decision boundary
- Accept a request identified by a caller-supplied sector id and prompt.
- Return acceptance (a correlation id and pending status) to the caller immediately, without the caller awaiting blueprint generation.
- Internally drive the existing, unchanged `SectorBlueprintService.request_sector_blueprint()` seam.
- Track each sector id's request state (`pending` -> `ready`) and its outcome Dictionary in memory only, for this node's lifetime.
- Expose a query seam (`get_provisional_result`/`get_status`) and a completion signal so a caller can observe the outcome once ready.
- Keep the SceneTree/multiplayer physics loop responsive while a request is in flight (same non-blocking property Slice 008 already proved for the underlying service).

## Non-goals
- No geometry generation, mesh building, or scene instancing of any kind.
- No SQLite persistence and no Canon state; results live only in this node's memory and are lost on process exit.
- No sector-boundary detection (deciding *when* a sector needs generating is a future slice).
- No quest generation.
- No retries beyond whatever LocalLLMClient/SectorBlueprintService already bound in Slice 008.
- No client-side Ollama calls; this seam is server-only, same as Slice 008.
- No hardware or inference deployment work (P-009 remains separately planned).

## Acceptance evidence
- A request for a new sector id is accepted synchronously (no await required by the caller) and immediately reports a `pending` status.
- The SceneTree continues processing frames while the request is in flight.
- On success, the sector id's status becomes `ready` and the stored result carries the validated blueprint and the correlation id used against SectorBlueprintService.
- On transport, malformed-envelope, or timeout failure, the sector id's status becomes `ready` with a structured failure outcome (no exception, no crash, no partial state).
- Two concurrent requests for different sector ids do not interfere: each has its own correlation id and independently retrievable state.
- No SQLite file, Canon table, or geometry node is created or referenced anywhere in the new seam.

## Handoff workflow
Copilot owns the decision and acceptance criteria. Claude Code CLI owns the bounded implementation and executable validation. Copilot reviews the in-memory state shape before any future slice adds persistence or boundary detection.

## Answer

Slice 009 is implemented as `server/provisional_sector_generator.gd`, a thin
orchestration `Node` in front of the unchanged Slice 008
`SectorBlueprintService`. `request_provisional_sector(sector_id, prompt)`
records a `pending` in-memory entry and returns its correlation id
synchronously; the actual `SectorBlueprintService.request_sector_blueprint()`
await happens in a background coroutine kicked off via `call_deferred` against
a fresh, short-lived `SectorBlueprintService` instance per request (a shared
instance cannot run two concurrent requests, since its one child
`HTTPRequest` node rejects a second in-flight request), so the caller never
awaits generation to get acceptance. `get_status(sector_id)`,
`get_correlation_id(sector_id)`, and `get_provisional_result(sector_id)`
expose the in-memory state, and `provisional_sector_ready(sector_id, result)`
signals completion. No geometry, SQLite, Canon, boundary detection, quest,
retry, client-Ollama, or hardware work is introduced. Full details, including
two other timing/state bugs found and fixed during focused testing, are in
[Slice 009](../../../docs/slices/009-provisional-sector-generation.md).
