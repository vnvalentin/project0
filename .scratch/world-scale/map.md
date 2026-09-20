# Map: World Scale & Measurement System

Governing issue: [#421](https://github.com/vnvalentin/project0/issues/421)

## Destination

A locked, handoff-ready **world-scale decision + Imperial measurement contract**:
an ADR, `CONTEXT.md` terms, and one server-owned versioned scale/tuning seam that
fixes **1 world unit = 1 yard** (Imperial), a three-level **world unit → Tile →
Sector** hierarchy, and a **Sector ≈ ¼ mile (440 yards = 440 units)** — ready for
downstream implementation slices to consume. Planning only: this map decides the
numbers and the contract shape; it does not re-scale the running code.

The map is complete when the unit anchor, grid resolution, Sector span, the
measurement-contract seam, the existing-constant reconciliation policy, and the
capstone ADR are all decided well enough to open implementation tickets safely.

## What Good Looks Like

- [x] The project has a single Imperial unit anchor and documented Tile/Sector hierarchy.
- [x] Sector span and grid-resolution policy are decided without forcing a generation rewrite.
- [x] A versioned `WorldScale` seam and existing-constant reconciliation policy are specified.
- [x] ADR/spec evidence exists so downstream implementation slices can consume the decision safely.

## Notes

- Domain: Godot 4 GDScript 2.0 strict typing; server-authoritative per
  [CLAUDE.md](../../CLAUDE.md). "Balance is versioned data" — scale must live in a
  bounded, versioned, server-owned tuning seam, not scattered magic numbers.
- **Standing constraint (user, 2026-09-13): Imperial measurement system.** The
  human/gameplay tier reads feet/yards; the world/region tier reads miles.
- Settled anchors (this map's premises, from the destination-naming grill):
  - **1 world unit = 1 yard** (≈ 0.914 m) — the honest Imperial relabel of the
    "meters" the monster code already assumes; preserves current tuned magnitudes.
  - The mile-scale concept is the **Sector** (a JIT-generated region); the **Tile**
    stays the fine walkable cell.
  - **Sector target ≈ ¼ mile = 440 yards = 440 units** (1 mile = 1760 units).
  - **Plan-not-do:** lock the spec; the code migration is downstream slices.
- Existing implicit scale to reconcile (go-and-see):
  - Tile = `1.0` unit — `shared/sector_geometry_lookup.gd` (`_TILE_FOOTPRINT`).
  - `AUTHORITATIVE_MOVE_SPEED = 5.0` units/s — `shared/network_config.gd`.
  - Monster `*_METERS` constants — `shared/monster_contracts.gd`.
  - Sector bounds `MAX_COORDINATE_ABS = 48`, `MAX_TILE_COUNT = 4096` —
    `shared/sector_blueprint_schema.gd`.
- Skills per ticket: `grilling` + `domain-modeling` for every decision ticket (keep
  the `CONTEXT.md` glossary in sync inline); `codebase-design` for the contract-seam
  ticket.
- Tracker: local markdown under `.scratch/world-scale/`; the Flow Dashboard reads
  this map + its issues.
- Deviation note: the research ticket's findings are captured as a Markdown file
  under `.scratch/world-scale/research/` rather than a throwaway git branch, because
  the working tree is dirty with concurrent Claude work and switching branches would
  be disruptive.

## Decisions so far

> **Status: COMPLETE** — all five tickets resolved 2026-09-13; the way is clear.
> Implementation (the `WorldScale` module + meters→yards rename) hands off to downstream
> slices per [ADR 0003](../../docs/adr/0003-imperial-world-scale.md).

<!-- one line per closed ticket: gist + link -->

- [01 — Grid resolution & Sector span](issues/01-grid-resolution-and-sector-span.md):
  **Region-container model** — a Sector is a 440-unit (¼-mile) region; the fine **Tile
  stays 1 unit = 1 yard** (detail grid, unchanged) describing only a bounded sub-area;
  Sector span is **tunable data, default 440 units**; blueprint bounds (±48 / 4096)
  **unchanged**. Three-tier: world unit → Tile → Sector.
- [02 — Godot physics unit-scale research](issues/02-godot-physics-unit-scale-research.md):
  Godot documents 1 unit = 1 m, but it is a labeling convention, not a hard dependency;
  **1 unit = 1 yard is low-risk** (every meter-tuned default stays within ~8.6 %), and
  `default_gravity` 9.8 relabels to 8.96 m/s². Store SI-reconciliation constants in the
  tuning seam. [Findings](research/02-godot-unit-scale.md).
- [03 — Measurement contract seam](issues/03-measurement-contract-seam.md): A pure
  versioned **`shared/world_scale.gd`** deep module (`class_name WorldScale`) — Imperial
  constants (`SCALE_VERSION`, `FEET_PER_YARD`, `YARDS_PER_MILE`, `TILE_EDGE_UNITS = 1`,
  `SECTOR_EDGE_UNITS = 440` tunable) + numeric conversions (`units_to_feet/miles`,
  `miles_to_units`); no Resource loader, no `format_distance()` yet; pure shared
  contract, no authority.
- [04 — Reconcile existing constants](issues/04-reconcile-existing-constants.md):
  **Relabel-only** — rename all meters→yards project-wide (monster `*_METERS`, combat
  `reach_meters`, `RESPAWN_AREA_RADIUS_METERS` + tests), magnitudes unchanged; base
  speeds/distances stay **literal** (no `WorldScale`-derived — conversion is identity);
  `default_gravity` left at 9.8 (SI ~10.72 deferred to future vertical mechanics); render
  heights left as-is. Full file/constant checklist in the ticket.
- [05 — World Scale ADR + spec](issues/05-world-scale-adr-and-spec.md): **Capstone —
  map complete.** Authored [ADR 0003](../../docs/adr/0003-imperial-world-scale.md)
  (Imperial 1 unit = 1 yard; world unit → Tile → Sector; Sector ≈ ¼ mile
  region-container; `WorldScale` seam; relabel-only reconciliation), added `CONTEXT.md`
  terms (World unit, Tile, Sector span), and the downstream-slice handoff brief.

## Not yet specified

- World-extent budget: how many Sectors compose the playable world, and whether
  there is a maximum extent (depends on the Sector span, ticket 01).
- Whether vertical scale (wall height, structure heights, future jump/fall/buoyancy)
  gets an explicit Imperial pass (depends on the unit anchor + the physics research).
- How the client HUD/UI presents distances to the player (feet/yards/miles readout)
  — downstream of the contract seam.
- What occupies the **non-detailed remainder** of a region-container Sector (flat
  ground vs void vs future procedural fill) — surfaced by ticket 01's region-container
  decision; a geometry/world-fill concern, downstream of this measurement map.

## Out of scope

- Re-tuning combat/movement *feel* (magnitudes are relabeled, not rebalanced).
- Changing the sector-generation algorithm or prompt.
- Infinite / streaming-world technology.
- SQLite / Canon world-extent persistence (Phase 9's own effort).
- The actual code migration / re-scaling — downstream implementation slices, not
  this planning map.
