Type: grilling
Status: resolved
Blocked by: 01

## Question

Design the single server-owned, **versioned measurement/scale contract** the whole
codebase derives from (per [CLAUDE.md](../../../CLAUDE.md): balance is versioned data,
in a bounded, versioned, server-owned tuning seam).

Sub-questions to resolve here:

- Where does it live — a `shared/` value contract (e.g. `shared/world_scale.gd`) of
  typed constants + pure conversion helpers, a Godot `Resource` tuning file, or both?
- What does it expose: unit label (`"yard"`), yards-per-unit, feet-per-yard,
  yards-per-mile, Tile edge (units, from ticket 01), Sector edge (units, from
  ticket 01), and conversion helpers (units ↔ feet ↔ yards ↔ miles)?
- Is it a shared **pure** contract that both client and server read, with no authority
  implied, matching the `shared/` rules (no secrets, no clocks, no repositories)?
- Versioning: how does a `scale_version` travel so a future rescale is a versioned
  data change rather than scattered edits?

Consult the `codebase-design` skill for seam placement (deep-module boundary between
"raw world units" and "human-readable Imperial distances").

## Answer

Grilled 2026-09-13; all four recommendations accepted. This ticket decides the seam
**design**; the module itself is written by a downstream implementation slice
(plan-not-do).

- **Seam form: a pure `shared/world_scale.gd`** — `extends RefCounted`,
  `class_name WorldScale`, `const` tables + `static` pure helpers — matching the
  existing shared value contracts (`combat_contracts.gd`, `sector_geometry_lookup.gd`).
  No `.tres` Resource loader: only one scale exists, so the seam is *hypothetical*, not
  real ("two adapters means a real seam"); a const module already delivers versioned
  data.
- **Interface (deep = small):**
  - Constants: `SCALE_VERSION`, `UNIT_LABEL = "yard"`, `FEET_PER_YARD = 3.0`,
    `YARDS_PER_MILE = 1760`, `TILE_EDGE_UNITS = 1.0` (ticket 01),
    `SECTOR_EDGE_UNITS = 440.0` (¼ mile, tunable default).
  - Static conversions: `units_to_feet()`, `units_to_miles()`, `miles_to_units()`
    (`units_to_yards()` omitted — identity, since 1 unit = 1 yard).
  - **Deferred:** a `format_distance()` presentation helper — no caller yet; it joins
    the HUD ticket when that seam is real.
- **Versioning: a single `const SCALE_VERSION: int = 1`** (stamped into scale-derived
  telemetry/records later), like `CombatContracts.SCHEMA_VERSION`. No supported-set
  validator — nothing loads external scale data. Changing `SECTOR_EDGE_UNITS` later =
  edit the const + bump `SCALE_VERSION` = the versioned-data change CLAUDE.md wants.
- **Authority: pure shared value contract** — inert data + pure math, no mutable
  state / clocks / secrets, read identically by client and server, granting neither
  authority. Firmly on the `shared/` side of the ownership line.

Deep-module rationale (deletion test): without `WorldScale`, the 3-ft/yard,
1760-yд/mile, and ¼-mile-Sector arithmetic reappears scattered across HUD, telemetry,
and monster/movement config — so the seam earns its keep.

Feeds ticket 04: the existing constants (monster `*_METERS` → `*_YARDS`,
`AUTHORITATIVE_MOVE_SPEED`, smooth/snap distances) are reconciled against this seam.
