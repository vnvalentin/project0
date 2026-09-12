Type: grilling
Status: resolved

## Question

How does the server guarantee the same starting hub sector/content on every
run before Phase 9's SQLite Canon persistence exists — e.g. a fixed
`sector_id` and fixed prompt/seed requested once at server boot via the
existing `server/provisional_sector_generator.gd` and cached in memory for
the life of the process, regenerated only on a fresh process start? Confirm
this lightweight workaround is acceptable as a stated limitation in the spec
(town content can change across server restarts until Phase 9 ships) rather
than something this map needs to solve permanently.

## Answer

- **Not live-generated at all**: the hub bypasses Ollama/`provisional_sector_generator.gd`
  entirely. It is a hard-coded fixture Dictionary (schema-v2-shaped) checked
  into the server, still validated by the real
  `SectorBlueprintSchema.validate()` and rendered by the real client-side
  translator from tickets 01/02 — proving the pipeline seam works — but
  without depending on live LLM output quality for a player's house/Smithy/
  Armor Shop/Inn to reliably exist. Live Ollama generation is reserved for
  non-hub sectors.
- **Identity**: a literal reserved constant `sector_id` (e.g.
  `"starting_town_hub"`) at origin coordinate `{x:0, y:0}`, matching the
  existing reserved-literal-id pattern used by `TargetDummy`
  (`"target_dummy_0"`).
- **Materialization timing**: eagerly at server boot — validate and hold the
  fixture in memory before accepting connections, since it's now static/
  synchronous, not an async LLM call.
- **Fixture validation failure**: fail closed. If the checked-in fixture ever
  fails `SectorBlueprintSchema.validate()` (e.g. after a future schema
  change), the server refuses to start and logs the rejection reason, rather
  than silently degrading to the flat-plane-only scene.
- **Stated limitation carried into the spec**: until Phase 9's Canon
  persistence exists, this hub fixture is simply static data shipped with the
  server; it isn't "canon" in the CLAUDE.md sense and there is nothing to
  persist yet — restarting the server always yields the identical hub
  because it's the same fixture, not because anything was saved.
