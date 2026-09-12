Type: task
Status: resolved
Blocked by: 04, 07

## Question
What is the smallest safe JIT-generation contract that sends an asynchronous request to local Ollama, validates a versioned sector blueprint, and reports bounded success/failure without creating world geometry or persistent Canon state?

## Decision boundary
- Define a versioned JSON blueprint schema for one small sector response.
- Validate required fields, coordinate bounds, supported tile/entity kinds, and schema version before any gameplay use.
- Return structured outcomes for success, malformed JSON, schema mismatch, HTTP failure, and timeout.
- Preserve request correlation/provenance in memory and emit observable outcome telemetry.
- Keep the request asynchronous so the multiplayer loop remains responsive.
- Use local Ollama server-side only; the Windows client never calls Ollama.

## Non-goals
- No generated geometry in the live scene.
- No SQLite persistence or Canon state.
- No sector boundary detection, quest generation, world mutation, retries beyond one bounded policy decision, or production prompt tuning.

## Acceptance evidence
- A valid blueprint parses and validates.
- Malformed, incomplete, unsupported, and wrong-version blueprints fail closed.
- HTTP failure and timeout return bounded structured errors.
- A real or fixture-backed asynchronous public-seam test proves the multiplayer loop is not blocked.

## Handoff workflow
Copilot owns the contract and acceptance criteria. Claude Code CLI owns the bounded implementation and executable validation. Copilot reviews the schema, failure states, and evidence before any world integration.

## Answer

Slice 008 is implemented as a versioned schema validator and asynchronous
server-side request service. The fixture-backed public-seam test covers valid,
malformed, incomplete, unsupported-kind, wrong-version, out-of-bounds,
HTTP failure, timeout, non-blocking, and correlation/provenance outcomes. No
geometry, gameplay, or Canon persistence is introduced.

The broader regression suite is not fully green because the previously
validated `scripts/test_authoritative_movement.gd` file is missing from the
working tree. That is a separate delivery repair and is not silently counted
as Slice 008 evidence.
