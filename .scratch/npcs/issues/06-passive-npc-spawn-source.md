Type: grilling
Status: unclaimed
Blocked by: 01

## Question

Where do `PASSIVE` NPCs come from? Today monsters spawn 1:1 from a sector
blueprint's `spawn_point`s via `server/server_monster_manager.gd`, with placement
tuned for hostiles (kept **outside** the town exclusion zone). Passive NPCs
(villagers) most naturally live **inside** the town. Resolve with
`domain-modeling` + `grilling`:

- **Source.** (a) Reuse the same `spawn_point` list with a per-point
  disposition/kind field; (b) tie passive NPCs to `npc_house` / `village_hall`
  structures so villagers "live" in houses; or (c) a new blueprint field/marker.
- **Schema impact.** New field vs. reuse — and whether it needs a schema version
  bump (`shared/sector_blueprint_schema.gd`), keeping older versions valid.
- **Placement + counts.** Passives inside the town vs. the monster exclusion
  zone; how many; how the manager (`server_monster_manager.gd`) drives both
  dispositions (one mechanism vs. two).
- **Telemetry.** Spawn/despawn signals for passives.

Recommended default: extend the spawn marker with a `disposition` (and/or kind)
field so **one** spawn mechanism places both hostiles and passives; passives are
allowed inside the town boundary while hostiles keep their exclusion rule;
version-gate any schema change so v1/v2 blueprints stay valid.
