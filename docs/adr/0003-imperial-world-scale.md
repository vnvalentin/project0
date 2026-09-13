---
status: accepted
---

# Imperial world scale: one world unit is one yard

Project0 adopts an explicit **Imperial** world scale anchored at **1 world unit =
1 yard**, with a three-tier spatial model — **world unit → Tile → Sector** — where a
Sector is a ≈¼-mile region. This replaces the previously implicit, inconsistent scale
(a 1-unit tile, bare "units/second" movement, and monster constants silently labeled
"meters").

## Context

Scale lived implicitly and inconsistently in code: the blueprint Tile was 1.0 world
unit (`shared/sector_geometry_lookup.gd`), player movement was bare "units/second"
(`shared/network_config.gd`), and the monster contracts silently assumed 1 unit ≈ 1
meter (`DETECTION_RADIUS_METERS`, `CHASE_SPEED_METERS_PER_SEC`, `MONSTER_REACH_METERS`
in `shared/monster_contracts.gd`). No canonical measurement contract existed, and
`CONTEXT.md` had no scale term. The user asked for a measurement system to define
scale (region-scale tiles feeling "massive" at ~1 mile, starting at ¼ mile) and
directed an Imperial system. Charted via
[the World Scale map](../../.scratch/world-scale/map.md) (tickets 01–05).

## Decision

**Anchor.** One world unit = **1 yard** (≈ 0.9144 m). The world scale is Imperial:
distances read in **feet/yards** up close and **miles** at the region tier. Godot's
documented "1 unit = 1 meter" is a labeling convention, not a hard dependency (see the
[unit-scale research](../../.scratch/world-scale/research/02-godot-unit-scale.md)); the
yard anchor keeps every meter-tuned engine default within ~8.6 % of intent, so it is
low-risk.

**Three-tier spatial model.**

- **World unit** — 1 yard; the base unit of all positions, speeds, and sizes.
- **Tile** — the fine 1-unit (1-yard) blueprint cell; the walkable detail grid.
  Unchanged by this decision.
- **Sector** — a JIT-generated **region** with a nominal span of **¼ mile = 440 units**
  (tunable, up to 1 mile = 1760). A Sector is a **region container**: its fine Tile
  detail covers a bounded sub-area (~the current ±48 grid, town-sized), not every yard.
  Fully tiling a ¼-mile Sector at 1-yard fidelity (~194k tiles) is neither LLM-generable
  nor within the blueprint bounds, and coarsening the Tile would destroy walkable
  detail — so blueprint bounds (`MAX_COORDINATE_ABS = 48`, `MAX_TILE_COUNT = 4096`) are
  **unchanged**.

**Measurement contract seam.** A pure, versioned `shared/world_scale.gd`
(`class_name WorldScale`, `extends RefCounted`) is the single source of truth:
constants (`SCALE_VERSION`, `UNIT_LABEL = "yard"`, `FEET_PER_YARD = 3`,
`YARDS_PER_MILE = 1760`, `TILE_EDGE_UNITS = 1`, `SECTOR_EDGE_UNITS = 440`) and pure
static conversions (`units_to_feet`, `units_to_miles`, `miles_to_units`). It is inert
shared data with no authority. No `.tres` Resource loader (one scale = a hypothetical
seam) and no `format_distance()` presentation helper (no caller yet) are built now.

**Reconciliation is relabel-only.** Because the yard anchor is a near-1:1 relabel of
the meters the code assumed, existing magnitudes are **renamed, not re-tuned**: all
`*_METERS` / `reach_meters` identifiers become `*_YARDS` / `reach_yards` (same values),
and unit-labeled speeds/distances get their comments relabeled to yards. Base
magnitudes stay **literal** (routing them through `WorldScale` would be an identity
no-op). `ProjectSettings` `default_gravity` stays at the engine default `9.8` (no
vertical mechanic exists yet); the SI-accurate value (~10.72) is a **deferred** note
for a future vertical-mechanics slice. Render heights (`_WALL_HEIGHT`, etc.) are
already yard-consistent and unchanged.

## Consequences

- One canonical, versioned scale exists; distance math (HUD, telemetry, Sector spans)
  has a single seam instead of scattered magic numbers — satisfying CLAUDE.md's
  "balance is versioned data."
- Growing Sectors later (¼ mile → 1 mile) is a `WorldScale` data edit + `SCALE_VERSION`
  bump, not a code hunt.
- Given up for now: a Sector is **not** fully walkable at fine detail; what fills a
  Sector's non-detailed remainder is an open downstream geometry/world-fill question,
  not decided here.
- The meters→yards rename touches combat, monster, and network files plus their tests
  (mechanical, no behavior change).
- No schema, bounds, gravity, or geometry-height change; no world-streaming or
  persistence work is authorized by this ADR.

## Implementation handoff (downstream slices)

1. **`WorldScale` module** — add `shared/world_scale.gd` per the seam above, with a GUT
   unit test (public seam: the static API; assert `units_to_feet(1.0) == 3.0`,
   `miles_to_units(0.25) == 440.0`, `units_to_miles(1760.0) == 1.0`, and that
   `SCALE_VERSION` is present). Non-goals: no Resource, no `format_distance()`.
2. **Relabel reconciliation** — apply ticket 04's checklist (`meters`→`yards` renames
   across `shared/monster_contracts.gd`, `shared/combat_contracts.gd`,
   `server/server_monster_manager.gd`, `client/melee_strike_visual.gd`, plus
   `tests/unit/test_melee_combat_contracts.gd` and `tests/unit/test_server_monster_state.gd`;
   comment relabels in `shared/network_config.gd` and `client/player.gd`). Validation:
   the full GUT suite stays green with no magnitude change.

Non-goals (whole effort): geometry/height changes, gravity retune, HUD distance
readout, blueprint schema/bounds changes, world-streaming, persistence.
