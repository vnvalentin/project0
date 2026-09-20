# Goal E Map: DM Guild and Semantic World Pipeline

Status: chartering
Governing issue: [#421](https://github.com/vnvalentin/project0/issues/421)

## Destination

Define how World, Party, and Personal Dungeon Master roles provide semantic
context and proposals while deterministic server systems validate and execute
all gameplay truth.

## What Good Looks Like

- [ ] World DM, Party DM, and Personal DM responsibilities and authority limits
  are explicit.
- [ ] The portable semantic World blueprint and deterministic builder boundary
  are defined without choosing a model runtime, renderer, or storage product.
- [ ] Proposal schemas, validation, fallback, timeout, revision, and rejection
  behavior are defined.
- [ ] Context retrieval is bounded by Character, Party, spatial, quest, and
  World relevance rather than passing unbounded history.
- [ ] World bulletins, cross-Player events, convergence opportunities, and
  Canon publication rules are defined.
- [ ] Fixture-backed proposals prove one quest, puzzle, location, or faction
  change without requiring live LLM inference.
- [ ] A handoff-ready spec and ADR exist before any Goal E feature or slice is
  allocated.

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
