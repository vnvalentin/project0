# Map: Starting Town

Governing issue: [#495](https://github.com/vnvalentin/project0/issues/495)

## Destination

A handoff-ready spec (SDD/BDD-shaped) describing how the starting town becomes
a JIT-generated, single-sector hub containing facade-only House, Smithy,
Armor Shop, and Inn/Tavern buildings — with each connecting player allocated
their own unique house at a unique position in town — ready to become an
implementation slice under Phase 8 (JIT world generation) / Phase 9 (Canon
persistence). See [Project Tracker](../../docs/PROJECT-TRACKER.md) and
[CLAUDE.md](../../CLAUDE.md).

## What Good Looks Like

- [x] The starting town sector schema accepts validated structures and spawn points while preserving older schemas.
- [x] The client can translate the validated town blueprint into visible facade geometry.
- [x] A stable hub sector fixture is materialized and replicated to clients through the real server/client seam.
- [x] Players receive unique session-scoped house allocation and facade proximity presentation without claiming interiors or economy.

## Notes

- Domain: Godot 4 GDScript, server-authoritative per CLAUDE.md's Runtime
  Ownership rules. Existing pattern to match:
  `shared/sector_blueprint_schema.gd` (v1 fail-closed, bounded validation
  style) and `server/provisional_sector_generator.gd` (async, in-memory,
  non-blocking).
- Skills to consult per ticket: `domain-modeling` (keep `CONTEXT.md` glossary
  in sync with any new terms like "hub sector", "facade entity"),
  `codebase-design` (seam placement for a new geometry-translation module).
- Standing preference: every new schema field follows v1's fail-closed
  validation style (reject on ambiguity, bounded counts/coordinates).
- Standing requirement (user direction, 2026-09-12, applies across both this
  effort's maps): build in structured, bounded telemetry from the start for
  anything future balancing/operations may need (e.g. hub materialization
  outcome, house allocation accept/reject, facade proximity counts if ever
  useful) rather than bolting it on later; reuse CLAUDE.md's existing
  "Telemetry And Andon Signals" seam.
- Standing requirement (user direction, 2026-09-12): every implementation
  slice from this map follows this repo's SDD/BDD/TDD workflow (public-seam
  failing test first, unit tests, GUT integration tests, regression tests
  for safety-relevant invariants), matching
  `docs/slices/012-authoritative-melee-strike.md` as the existing template.
- Full SQLite Canon persistence (Phase 9) and player identity/save
  persistence across restarts are external dependencies this map hands off
  to, not effort this map builds itself.

## Decisions so far

- [01 — Schema v2: structures and spawn points](issues/01-schema-v2-structures-and-spawn-points.md): New `structures` and `spawn_points` arrays alongside `tiles`; Structure has `structure_id`/`kind` (house, smithy, armor_shop, inn)/anchor `x`,`y`/`facing_degrees`, no footprint; spawn points are `{spawn_id, x, y}` only, monster kind deferred to Basic Monsters; v1 and v2 both stay accepted (non-town sectors keep generating v1).
- [02 — Geometry translation strategy](issues/02-geometry-translation-strategy.md): Client-side translation only (server never renders); tiles become procedural per-kind boxes extending the `FlatPlane` pattern; structures become authored per-kind prefab scenes instanced like `target_dummy.tscn`, placeholder boxes acceptable now.
- [03 — Hub sector identity and pinning](issues/03-hub-sector-identity-and-pinning.md): The hub is a hard-coded fixture Dictionary (not live Ollama output) at reserved `sector_id = "starting_town_hub"` / origin `{0,0}`, validated/translated through the real pipeline, materialized eagerly at server boot, fail-closed on its own validation failure.
- [04 — Facade representation and enter/exit](issues/04-facade-representation-and-enter-exit.md): Automatic-proximity `Area3D` per facade shows a UI label (no interact keypress, no interior); purely client-observed/cosmetic, no server authority needed; no exclusivity between players.
- [05 — Player house allocation](issues/05-player-house-allocation.md): Fixed pool of 10 house Structures (matching the 10-player max) baked into the hub fixture; over-capacity handled only as a defensive fail-closed fallback; house slot frees immediately on disconnect, first-available reassignment, no reconnect reservation.
- [06 — Blueprint replication contract](issues/06-blueprint-replication-contract.md): Server sends the validated hub `Dictionary` via a new `reliable` authority RPC (`receive_sector_blueprint`) to each peer on connect, before player spawns; client re-validates through `SectorBlueprintSchema.validate()` then invokes the Slice 015 translator into a dedicated `SectorGeometry` node (leaving `FlatPlane`/`Player`/UI untouched); invalid payload renders nothing; send + receive telemetry; one bounded reliable RPC means no partial-transfer case.

## Not yet specified

- Whether future shop economy (buy/sell) reuses the facade entity positions
  decided here, once P-006-style economy work is scoped — too far downstream
  to ticket now.

## Out of scope

- Full SQLite Canon persistence engine — Phase 9's own effort
  ([P-011](../../docs/FEATURE-LIST.md#p-011-canonical-history-archive),
  [P-012](../../docs/FEATURE-LIST.md#p-012-one-time-blueprint-canonicalization)).
  This map's hub-pinning ticket (03) only decides a lightweight in-memory
  workaround until that Phase exists.
- Shop economy / buy-sell / inventory / currency — user decision 2026-09-12:
  facades + enter/exit only.
- Building interior scenes/rooms.
- Player identity/save persistence across server restarts (no save system
  exists yet; house ownership here is session-scoped only).
