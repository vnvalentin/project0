Type: grilling
Status: resolved (assigned: Copilot)
Blocked by: None

## Question

The local LLM (Ollama) frequently proposes town layouts with buildings stacked
on or overlapping each other, and the current pipeline accepts them. How should
the server guarantee spatially valid, logically placed settlements — without
re-opening the delivered organic-village slices (023-027) or the decided
client-side geometry-translation model?

Root cause (go-and-see, 2026-09-13):

- `shared/sector_blueprint_schema.gd` validates a structure only for
  `structure_id` (unique), `kind` (enum), bounded `x`/`y`, and `facing_degrees`.
  It explicitly carries **no footprint/size**, so overlap is not even
  expressible, and there is no cross-structure spatial check nor an
  on-valid-tile check.
- `server/town_layout_provider.gd` `resolve()` accepts a candidate on schema
  validity plus required-structure *counts* only (`meets_required_structures`);
  nothing spatial. The prompt asks the model not to overlap, but nothing
  enforces it — so stacked buildings pass and render as fixed-size prefabs on
  top of each other.

## Resolution

Accepted strategy (user, 2026-09-13):

1. **Enforcement = validate + deterministic server-side repair**, layered on the
   existing validate -> required-structures -> fixture-fallback flow. Pure reject
   would collapse a sloppy model to the fixture every time (the LLM effectively
   unused, which is the actual complaint); repair keeps server authority
   (CLAUDE.md law 3) while still using the model's proposal. Generator-side
   constraints are an upstream aid, never a replacement for server validation
   (law 5).
2. **Per-kind footprints live in server-owned versioned tuning** (not LLM- or
   client-supplied sizes — "balance is versioned data"). Overlap is undefinable
   without extent; this is the keystone the rest depends on. -> ticket 02.
3. **Lock non-overlap + on-valid-tile placement first** (the real bug).
   Aesthetically "logical" placement (spacing, facing a road, district
   clustering) graduates later as fog, not now. Repair/validation -> ticket 03.
4. The **MCP / OSM / GIS external-planner** idea is **deferred to a research
   ticket** (additive at best, with real architecture/security cost); prove the
   deterministic in-engine path first. -> ticket 04.

Scope guard: no SQLite/Canon, no client-side rendering changes, no re-opening
the delivered slices. This cluster only makes an LLM-proposed layout spatially
valid **before** it reaches the existing replication/translation seam.
