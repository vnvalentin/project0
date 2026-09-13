# Domain Context

## Product

`Project0` helps `a single developer and their playtesters` accomplish `entering
a shared 3D isometric world under one player identity and moving a character
through it, as the foundation for a server-authoritative multiplayer
action-adventure with JIT-generated, canon-persisted world content`.

## Domain terms

- **Identity gate**: The local, pre-gameplay step where a player supplies a
  display name (or other minimal credential) before a Player is created.
  Authoritative for the current slice; provisional — it is a stand-in for a
  real authentication/session design, not a security boundary.
  _Avoid_: login (implies networked auth that does not exist yet), account.
- **Player**: The in-scene actor a person controls after passing the identity
  gate. Authoritative in the current slice as a client-visible node; once
  networking exists, position/state authority moves to the server.
  _Avoid_: character, avatar, user (User is a person; Player is their in-world
  actor).
- **Flat plane**: The minimal placeholder ground scene used to prove movement
  without committing to any generated or hand-built map. Authoritative as the
  current slice's only world geometry.
  _Avoid_: level, map, world (those terms are reserved for the future
  generated/canon world).
- **Sector**: A unit of JIT-generated world content produced by the local LLM
  and, once validated, written to the SQLite canon store. Provisional — no
  generation or persistence exists yet; defined here only so the term is
  reserved and not reused for the flat plane.
  _Avoid_: chunk, tile map, level.
- **Canon**: World state that has been validated and persisted to SQLite,
  making it authoritative and durable across sessions. Provisional — canon
  persistence is not implemented in this slice; nothing produced today is
  canon.
  _Avoid_: save data, world save.
- **Structure**: A building placement within a sector blueprint (e.g. house,
  smithy, armor shop, inn, and the schema-v3 flavor kinds church, item shop,
  tavern, well), identified by a unique `structure_id` and an anchor
  point/facing rather than a footprint. Implemented: schema v2 (Slice 014)
  added the `structures` array, schema v3 (Slice 025) added the organic flavor
  kinds, and geometry translation (Slices 015/024) instantiates one placeholder
  prefab per structure.
  _Avoid_: building (a Structure covers non-house placeables like a well; keep
  the neutral term canonical). A gate is a Tile kind, not a Structure.
- **Tile kind**: The terrain class of a blueprint tile. Base kinds
  (schema v1+): `floor`, `wall`, `corridor`. Organic vocabulary (schema v3,
  Slice 025): `path`, `plaza`, `gate`, `water`, `grass`. Only `wall` is solid
  (gets collision); the rest are visual ground merged into one mesh per kind by
  the geometry pass.
  _Avoid_: terrain type, biome (kind is the blueprint/validator term).
- **Spawn point**: A monster-instantiation marker within a sector blueprint,
  distinct from a Structure (not rendered or enterable). Provisional —
  reserved by [Starting Town map](.scratch/starting-town/map.md) ticket 01;
  the monster archetype placed at a spawn point is decided by the
  [Basic Monsters map](.scratch/basic-monsters/map.md).
  _Avoid_: spawner, spawn tile.
- **Hub sector**: The one reserved, hard-coded fixture sector
  (`sector_id = "starting_town_hub"`) every server instance starts with,
  containing the starting town's Structures. Distinct from Canon — it is
  static shipped data, not a persisted, validated-then-frozen LLM output.
  Implemented: materialized fail-closed at boot (Slice 016) and enriched to the
  schema-v3 organic vocabulary (Slice 025).
  _Avoid_: starting sector (ambiguous with a future player-specific spawn
  concept), canon town (it is not Canon in the persisted-and-frozen sense
  until Phase 9 exists).
- **Monster**: A server-authoritative, non-player combat target with a flat,
  explicitly provisional HP pool (`MonsterCombatState` in
  `shared/monster_contracts.gd`), distinct from `TargetDummy` (which has no
  HP/death at all). Provisional — decided by
  [Basic Monsters map](.scratch/basic-monsters/map.md) ticket 01; the HP
  model here is a placeholder for the future six-node vessel-derived health
  formula (Phase 12, 0% built).
  _Avoid_: enemy, mob (keep the term consistent with this repo's existing
  "Player"/"TargetDummy" naming register).

## External contexts

- **Ollama API** (`http://127.0.0.1:11434`, local Llama-3-8B on a Tesla P100):
  Supplemental, server-side-only inference source for future sector
  generation. Not authoritative for any game state by itself — the server
  must validate its output before anything becomes canon. Not exercised by
  the current identity-gate/movement slice.
- **SQLite canon database** (future, server-owned): Will be authoritative for
  persisted world state (canon) once introduced. Does not exist yet.

## Invariants

- The identity gate never blocks on, and has no dependency on, Ollama or
  SQLite.
- Nothing in the current slice is persisted to disk; closing the client
  discards all state.
- A Sector is never treated as Canon until the server has validated and
  written it to the SQLite store (future work; stated here so the boundary is
  not blurred when that system is built).

## Ambiguity policy

When evidence conflicts or is incomplete, preserve the source evidence, surface
the ambiguity, and define whether the affected action is blocked, retried, or
sent for review. Never silently guess.

## Ambiguity policy

When evidence conflicts or is incomplete, preserve the source evidence, surface
the ambiguity, and define whether the affected action is blocked, retried, or
sent for review. Never silently guess.