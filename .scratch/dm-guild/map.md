# Theme Map: DM Guild and Semantic World Pipeline

Status: theme-chartered
Parent Hoshin (Vision): [#495](https://github.com/vnvalentin/project0/issues/495)
Theme issue: [#708](https://github.com/vnvalentin/project0/issues/708)

Vocabulary note (2026-09-21): this map uses the Hoshin/Theme/Feature/Epic/
Experiment vocabulary. It was previously "Goal E" (Vision/Goal/Feature/Slice
convention); #708 was relabeled `Goal` -> `tbp:theme` in place, same issue
number. Feature #452 predates this map and keeps its native `Feature` label
and delivered Slices untouched — only its parent-reference text changed.

## Handoff artifacts

- [Semantic World Pipeline specification](spec.md)
- [ADR 0009 — DM Guild semantic world pipeline](../../docs/adr/0009-dm-guild-semantic-world-pipeline.md)

## Problem Statement

World, Party, and Personal DM proposals for structures and points of interest
cannot yet become client-rendered geometry without hand-authored content.
Phase 8 already procedurally generates sector-level terrain from an Ollama
proposal, but structure placement today is enum + hand-authored prefab
selection (`sector_geometry_lookup.gd`), not generation, and POIs have no
schema at all.

## Measurable Outcome

- **What:** An accepted DM proposal for world content (sector, structure, or
  POI) is deterministically realized as client geometry, and the same
  accepted directive + version reproduces an identical result on replay.
- **How much:** 100% of accepted proposals render as geometry; 0 divergent
  replays of the same accepted directive/version.
- **Who:** Server telemetry is the standing validation signal going forward;
  an operator performs initial manual verification before telemetry-only
  validation is trusted; a playtester can confirm the expected geometry
  appears at the documented triggering condition.
- **By when:** No fixed date — gated on fixture-backed evidence (a
  playtester observing accepted-proposal-to-geometry for at least one
  non-sector content type) plus telemetry evidence of deterministic replay.

## Features

- [x] [#452](https://github.com/vnvalentin/project0/issues/452) — F-040
  Server-only normalized World directive validation (in progress; delivered
  the validator/ordering/feasibility foundation other Features build on).
- [ ] [#710](https://github.com/vnvalentin/project0/issues/710) — Procedural
  house geometry from schema fields (footprint + style).

## Remaining gaps with no Feature yet

- Deterministic builder for POI-level (non-structure) content.
- Bounded context retrieval (Character/Party/spatial/quest relevance) for
  proposals.
- World Director tick / multi-DM ordering running in server code (design
  closed in #432/#435; no shipped Feature yet beyond what #452 covers).
- Accepted DM-originated mutations persisting to Canon as replayable history.
- Bounded rejection/fallback telemetry for LLM-originated proposals.

## Dependencies

Goal E consumes the Character, Party, item, quest, Canon, telemetry, spatial,
and authority contracts. It must never replace server ownership of outcomes or
run inside frame-critical simulation loops.

## Decision questions

- What semantic decisions belong to each DM role?
- When does a proposal become a shared World event?
- How are simultaneous or contradictory proposals resolved?
- Which blueprint fields are semantic intent versus deterministic parameters?
- What context is required for a useful proposal while keeping latency bounded?
- How does the game remain playable when inference is slow, unavailable, or
  rejected?

## Non-goals

- No live multi-agent service yet.
- No model, vector store, message bus, or cloud dependency selection.
- No LLM-authored physics, combat, inventory, persistence, or multiplayer truth.
- No full quest, dungeon, faction, or content implementation before this map
  produces a stable contract.

The decision route is complete. Fixture-backed proofs and bounded
implementation slices remain future delivery work under the handoff artifacts.

## Implementation frontier

- [Normalized World Directive Schema and Validator](https://github.com/vnvalentin/project0/issues/444) (closed, decision-stage only): defined the seam design, resolved into #452's shipped Slices.
- [#710](https://github.com/vnvalentin/project0/issues/710) Procedural house geometry (open): replaces the fixed house prefab with a schema-driven deterministic mesh generator. Broken into 3 Epics, in dependency order:
  - [#713](https://github.com/vnvalentin/project0/issues/713) — schema has no parametric fields. **Resolved:** [#717](https://github.com/vnvalentin/project0/issues/717) passed — `shared/sector_blueprint_schema.gd` now validates house `footprint_width`/`footprint_depth` ([3,12] units) + `roof_style` (gable_roof/hip_roof/flat_roof) at a new schema v4, with GUT coverage for 3 valid combos, out-of-bounds, unsupported style, missing fields, and v3/non-house backward compatibility (all passing on Windows, verified against the pre-existing 13 unrelated sqlite-extension failures).
  - [#714](https://github.com/vnvalentin/project0/issues/714) — translator has no procedural mesh builder (unblocked now that #713 is resolved)
  - [#715](https://github.com/vnvalentin/project0/issues/715) — no determinism/replay proof (depends on #714)
  - Next step: grill #714 (translator) into its first Experiment.
