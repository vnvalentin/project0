# Slice 036: Imperial world-scale measurement contract (WorldScale)

Tracker context: Phase 8 — JIT world generation and local inference (cross-cutting
scale foundation; the Sector/Tile span it fixes also underpins Phase 10 runtime
distances). Advances
[F-028](../FEATURE-LIST.md#f-028-imperial-world-scale-measurement-contract).
Planning ticket: [World Scale map](../../.scratch/world-scale/map.md) (tickets 01–05);
decision [ADR 0003](../adr/0003-imperial-world-scale.md).

## SDD

Goal (user request): implement a measurement system that defines world scale, in
Imperial units. Decision (ADR 0003, grilled via the World Scale map): the world is
Imperial, **1 world unit = 1 yard**, in a three-tier **world unit → Tile → Sector**
model where a Sector is a **¼-mile (440-unit) region container**. This slice delivers
the single versioned contract module that is the source of truth for that scale; the
meters→yards relabel of existing constants is a separate follow-up slice.

Public seam:

- `shared/world_scale.gd` (`class_name WorldScale`, `extends RefCounted`) — a pure,
  stateless value contract (no scene tree, no network I/O, no authority; both client
  and server read it identically, matching the `shared/` rules). Exposes:
  - constants: `SCALE_VERSION`, `UNIT_LABEL = "yard"`, `FEET_PER_YARD = 3.0`,
    `YARDS_PER_MILE = 1760.0`, `TILE_EDGE_UNITS = 1.0`, `SECTOR_EDGE_UNITS = 440.0`;
  - static conversions: `units_to_feet`, `units_to_miles`, `miles_to_units`.

Behavior:

- One world unit is one yard; `units_to_feet(1.0) == 3.0`.
- A 440-unit Sector edge is a quarter mile; `units_to_miles(440.0) == 0.25` and
  `miles_to_units(0.25) == 440.0`.
- `SECTOR_EDGE_UNITS` is tunable data (grows toward 1 mile = 1760); changing any scale
  constant bumps `SCALE_VERSION` so scale-derived data can be stamped.

Implementation decisions:

- **Const module, not a `.tres` Resource.** Only one scale exists, so a runtime-
  swappable Resource is a hypothetical seam (codebase-design: "two adapters means a
  real seam"); a versioned const module already delivers "balance is versioned data"
  (CLAUDE.md).
- **No `format_distance()` presentation helper yet.** No caller renders distances (HUD
  is downstream), so building it now would over-build for a nonexistent caller.
- **Base magnitudes stay literal, not contract-derived.** Because 1 unit = 1 yard,
  routing a `5.0`-unit speed through `WorldScale` is an identity no-op; the contract is
  for callers that genuinely cross units (HUD, Sector-span math).

## BDD

### One world unit is one yard

Given the `WorldScale` contract
When a distance of one world unit is converted to feet
Then it is 3.0 feet (one yard).

### A quarter-mile Sector

Given the default Sector edge (440 units)
When it is converted to miles
Then it is 0.25 miles, and `miles_to_units(0.25)` round-trips to 440 units.

### Versioned, stampable scale

Given `SCALE_VERSION`
Then it is a positive integer, so scale-derived telemetry/records can be stamped with
the scale they were produced under.

## TDD

- `tests/unit/test_world_scale.gd` — public-seam unit tests, written first and failing
  (the `preload` of `res://shared/world_scale.gd` errored before the module existed):
  scale version present/positive, unit label is `"yard"`, 1 unit = 3 feet, units↔miles
  both directions, a 440-unit edge = ¼ mile, the miles→units→miles round-trip, the
  Tile/Sector edge constants, and the zero-distance edge.

## Validation

- Focused (RED→GREEN): `godot --headless -s addons/gut/gut_cmdln.gd
  -gdir=res://tests/unit -gselect=test_world_scale -gexit` — RED before the module
  (`Parse Error: Preload file "res://shared/world_scale.gd" does not exist`), then
  **8/8 tests, 15 asserts, exit 0** after.
- Full gate: `scripts/run_gut_validation.sh` — **27 scripts, 207/207 tests, 808
  asserts, exit 0**; `build/validation/validation-summary.json` shows
  `scripts_expected == scripts_ran == 27` (the hardened gate confirms no script was
  silently skipped), and `test_world_scale` is present in `build/validation/gut.xml`.
  Only the known-expected fail-closed rejection diagnostics remain.

## Non-goals (this slice)

- The meters→yards relabel of existing constants (`shared/monster_contracts.gd`,
  `shared/combat_contracts.gd` `reach_meters`, `server/server_monster_manager.gd`,
  `shared/network_config.gd` comments) — the separate follow-up slice enumerated in
  ADR 0003 / world-scale ticket 04.
- No `format_distance()` HUD helper and no `.tres` tuning Resource.
- No schema/bounds change (`MAX_COORDINATE_ABS`/`MAX_TILE_COUNT` unchanged), no
  `default_gravity` change, no geometry-height change.
- No world-streaming and no persistence.
