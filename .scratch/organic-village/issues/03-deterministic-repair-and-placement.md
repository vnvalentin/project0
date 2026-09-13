Type: grilling
Status: unclaimed
Blocked by: 02

## Question

Design the deterministic server-side pass that turns a schema-valid but
spatially-invalid candidate into a non-overlapping, on-valid-tile layout, then
hands it to the existing required-structures / fixture-fallback flow (strategy
ticket 01, decisions 1 and 3). Needs the footprint model from ticket 02.

Resolve with `grilling` + `codebase-design` (a small `prototype` is allowed to
sanity-check placement feel):

- **Algorithm.** Greedy nearest-free-cell relocation, district/slot assignment,
  or physics-style separation relaxation. MUST be deterministic (same input ->
  same output), terminate within an explicit bound, and preserve the required
  structures.
- **Guaranteed invariants.** No footprint overlap (including margin); every
  structure on an interior valid tile (not wall/water/outside); within
  coordinate bounds; required-structure set intact.
- **Failure policy.** If it cannot place everything within its bound, fall back
  to the fixture (never an unusable town — map Q2). Does repair run before or
  after the required-structure check in `town_layout_provider.resolve()`?
- **Seam placement.** A new pure server module (e.g.
  `server/town_layout_planner.gd`) consumed by `TownLayoutProvider`, or an
  extension of the provider — decide via `codebase-design`. Keep it pure and
  testable (Dictionary in -> Dictionary out, no HTTP/async).
- **Telemetry.** Per-structure relocations, repair success vs fallback, and
  iteration count, reusing CLAUDE.md's Telemetry & Andon seam.

Output: the algorithm + invariants + seam, ready to hand Claude a bounded
SDD/BDD/TDD implementation slice.
