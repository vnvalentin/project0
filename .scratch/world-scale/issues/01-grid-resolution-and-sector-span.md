Type: grilling
Status: resolved

## Question

Given **1 world unit = 1 yard** and a **Sector target of ≈ ¼ mile (440 yards =
440 units)**, decide the grid resolution and how a Sector's physical span reconciles
with the blueprint's bounded tile budget.

Sub-questions to resolve here:

- How many yards does one blueprint **Tile** represent? Stay at the current
  1 unit = 1 yard (a 3 ft × 3 ft cell), or coarsen (e.g. 1 Tile = 10 yards) so a
  ¼-mile Sector fits a small, LLM-generable grid?
- With a 1-yard Tile, a 440-yard Sector edge = 440 × 440 = 193,600 tiles — far over
  `MAX_TILE_COUNT = 4096` and `MAX_COORDINATE_ABS = 48`
  (`shared/sector_blueprint_schema.gd`). Resolve by: (a) coarsening the Tile so
  tiles-per-Sector fits the existing bounds, (b) raising the bounds, or (c) treating
  a Sector as a container of many smaller blueprint chunks.
- Do `MAX_COORDINATE_ABS` and `MAX_TILE_COUNT` change — and if so, to what — while
  staying fail-closed and LLM-generation-feasible?
- Does the walkable-Tile render footprint (`_TILE_FOOTPRINT = 1.0` in
  `shared/sector_geometry_lookup.gd`) stay 1 unit, decoupling the *blueprint* grid
  cell (which may represent many yards) from the *render* footprint?

Recommended direction: coarsen the blueprint Tile to ~10 yards so 440 yд ≈ 44 tiles
fits within ±48, decouple "blueprint grid cell" from "world unit," and keep the fine
walkable/render footprint separate. Confirm (or reject) at resolution.

## Answer

Grilled 2026-09-13; all recommendations accepted. (The ticket-body "coarsen the Tile"
direction was **superseded** during grilling once the domain-modeling clash surfaced:
coarsening would erase the town's 1-yard detail, so the massive scale moves to the
Sector level instead.)

- **Strategy: region container (option A).** A **Sector** is a 440-unit (¼-mile)
  *region*. The fine 1-yard tile grid describes only a **bounded detailed sub-area**
  within it (~the current ±48 footprint, town-sized). "Massive scale" is a
  measurement/spacing fact, not a mandate to tile every yard. Rejected: **(B)** a
  ~10-yd coarse cell (destroys 1-yard detail — walls/doorways/town); **(C)** fine
  chunking (a streaming/LOD architecture, out of scope for this map).
- **Fine `Tile` preserved.** `Tile` stays **1 unit = 1 yard**, the detail grid the
  starting town's 289 tiles are built from — never redefined to "1 mile." Three-tier
  model locked: **world unit (1 yд) → Tile (1 unit) → Sector (440 units)**.
- **Sector span = versioned tuning data, default 440 units (¼ mile).** Freely
  changeable later toward 1 mile (1760 units); honors "start with ¼," per CLAUDE.md
  "balance is versioned data."
- **Bounds unchanged.** `MAX_COORDINATE_ABS = 48` and `MAX_TILE_COUNT = 4096` stay
  as-is — they bound the *detailed sub-area* per blueprint (~96 yд ≈ 288 ft across, a
  town-sized fraction of a 440-yд Sector), well within LLM-generation feasibility.
  `_TILE_FOOTPRINT = 1.0` (render) stays 1 unit.

Feeds ticket 03 (contract seam): **Tile edge = 1 unit, Sector edge = 440 units
(tunable)**. `CONTEXT.md` term-writing (World unit / Tile / Sector) is staged for the
capstone ticket 05, not written here (planning map; terms finalize after 03/04).
