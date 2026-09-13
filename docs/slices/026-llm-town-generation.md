# Slice 026: LLM town generation with a required-structure guarantee

Tracker context: Phase 8 — JIT world generation and local inference; advances
[F-026](../FEATURE-LIST.md#f-026-organic-districted-starting-city) and exercises
the local-inference path behind
[IP-008](../FEATURE-LIST.md#ip-008-just-in-time-sector-generation). Planning
ticket: [Organic LLM Village map](../../.scratch/organic-village/map.md)
(decision Q2 — hybrid LLM + validated guarantee + fixture fallback).

## SDD

Goal: Let the local LLM propose the town layout while the server guarantees a
usable town — validate the candidate against the schema, require the fixed
structures (10-house pool + smithy + armor shop + inn), and fall back to the
hand-authored hub fixture when the candidate is invalid or incomplete. "The LLM
proposes; it never authorizes" (CLAUDE.md law 5); the town is never unusable
(map Q2).

Public seam — `server/town_layout_provider.gd` (`class_name TownLayoutProvider`,
`RefCounted`):

- `meets_required_structures(blueprint) -> {ok, detail}` — pure: at least
  `REQUIRED_HOUSE_COUNT` (10) houses and at least one of each
  `REQUIRED_SINGLETON_KINDS` (smithy/armor_shop/inn).
- `resolve(candidate, fallback) -> {source, outcome, detail, blueprint}` — the
  pure guarantee: validate `candidate` through `SectorBlueprintSchema`; if valid
  **and** complete, `source == SOURCE_LLM` with the validated candidate;
  otherwise `source == SOURCE_FALLBACK` with `fallback` returned as-is and a
  reason (a schema `OUTCOME_*` or `OUTCOME_MISSING_REQUIRED_STRUCTURES`).
- `default_town_prompt() -> String` — the strict JSON town-generation prompt
  documenting the schema-v3 town contract the model must satisfy.
- `request_town(llm_client, fallback) -> {…}` (coroutine, emits `town_resolved`)
  — awaits any injected `generate_json(prompt) -> Dictionary` client (the real
  `LocalLLMClient` or a test stub), routes the raw candidate through `resolve()`,
  and falls back on a transport/parse failure. Non-blocking; never blocks the
  SceneTree.

Behavior:

- A valid, complete LLM candidate becomes the town (`source == llm`).
- A schema-invalid candidate, a schema-valid-but-incomplete candidate (e.g. 9
  houses or no smithy), or a transport failure all fall back to the fixture
  (`source == fallback`) with a bounded reason.
- The returned town always validates and always meets the guarantee — even on
  fallback — so downstream (house allocation, monster spawns, replication) is
  never handed an unusable town.

Implementation decisions:

- **Guarantee is a pure function.** The accept/fallback decision is
  `resolve(candidate, fallback)` with no I/O, so the "never an unusable town"
  property is fully unit-tested with plain Dictionaries — the untrusted LLM
  candidate is just data until it passes.
- **Injected async client.** `request_town` takes the client as a parameter, so
  the non-blocking request path is exercised end-to-end with a fake client (no
  live Ollama), mirroring how the rest of the pipeline stays testable.
- **Boot wiring deferred, on purpose.** The reliable hub fixture stays the boot
  default (`server/server_main.gd` is unchanged). Turning LLM generation on at
  boot has its own tradeoffs — boot latency and Ollama availability — and is a
  separate decision; this slice delivers and proves the guarantee seam that such
  a switch will call, exactly as Slice 009 delivered the provisional-generation
  seam ahead of its live trigger.

## BDD

### A valid complete LLM town is used

Given an LLM candidate that validates and has the required structures
When it is resolved against the fixture fallback
Then the resolved town is the LLM candidate (`source == llm`).

### An unusable LLM town falls back

Given an LLM candidate that fails schema validation, is missing required
structures, or a client transport failure
When it is resolved / requested against the fixture fallback
Then the resolved town is the fixture (`source == fallback`) with a bounded
reason, and it still validates and meets the guarantee.

### The shipped fixture is always a valid fallback

Given the hand-authored hub fixture
When it is checked against the required-structure guarantee
Then it passes (the fallback can never itself be unusable).

## TDD

- `tests/unit/test_town_layout_provider.gd` (8) — the fixture meets the
  guarantee; too-few-houses and missing-singleton fail; `resolve` accepts a
  valid complete candidate and falls back on invalid/incomplete; the fallback
  town always validates and meets the guarantee; the prompt documents the
  contract.
- `tests/integration/test_town_layout_provider_request.gd` (4) — with a fake
  `generate_json` client: a valid candidate is used; transport failure and
  invalid output fall back; `town_resolved` fires once with the resolution.

## Validation

- `godot --headless --check-only -s server/town_layout_provider.gd` → exit 0.
- `test_town_layout_provider` 8/8, `test_town_layout_provider_request` 4/4 — exit 0.
- Full suite `scripts/run_gut_validation.sh` → 22 scripts, 168/168 tests, 667
  assertions, exit 0. Only the known-expected fail-closed rejection diagnostics
  and the pre-existing benign headless `Parameter "m" is null` lines remain.

## Non-goals (this slice)

- No boot wiring — the server still materializes the reliable fixture at boot;
  switching the hub to LLM generation (and its boot-latency/Ollama-availability
  tradeoffs) is a separate decision.
- No live Ollama round trip in tests (the client is injected/faked); a live
  end-to-end run requires a running Ollama and is out of scope here.
- No persistence / Canon — a generated town is in-memory only, exactly like the
  fixture.
- No prompt-tuning or regeneration/repair loop when the model omits a structure
  (the guarantee simply falls back); an iterative repair policy is future work.
- No monster-exclusion-from-bounds (Slice 027).
