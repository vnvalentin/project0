# Domain Context

## Product

`Project0` helps `a single developer and their playtesters` accomplish `securely
entering a shared 3D isometric world as a selected Character and moving through
server-authoritative, generated, canon-persisted content`.

## Domain terms

- **Identity gate**: The original local, pre-gameplay step where a player
  supplied a display name before a Player was created. **Superseded** by the
  Account login and Character select flow (Phase 14, player-accounts); retained
  here only as the historical provisional stand-in it always was, never a
  security boundary.
- **Account**: The persistent, server-owned authenticated credential a person
  logs in with — an opaque `account_id`, a unique username, and a salted PBKDF2
  derived secret (never plaintext). One Account owns up to five Characters and
  is the modelled root of identity.
  _Avoid_: user (the human person, not a stored entity), profile.
- **Character**: A persistent, selectable persona owned by exactly one Account —
  an opaque `character_id`, a globally-unique display name, cosmetic data,
  timestamps, and a forward-compatible slot for future vessel state. A selected
  Character is instantiated as the in-world Player. Soft-deleted (retained and
  reversible; its name stays reserved to its Account).
  _Avoid_: avatar, hero, class.
- **Player**: The in-scene actor a person controls in the world — the runtime
  instantiation of a selected Character, its position and state
  server-authoritative once networking exists.
  _Avoid_: character (the persistent persona is the Character; the Player is its
  in-world instantiation), user.
- **Traversal action**: A player-directed movement activity used to explore,
  evade, reach, manipulate, or solve a problem in the world, such as jumping,
  swimming, dodging, sliding, crawling, climbing, wall-running, or falling.
  Character state changes its physical execution profile, not the player's
  ability to reason about or attempt the action.
- **Party**: A persistent, server-owned cooperative association of one to five
  unique Characters, with its own identity, leader, mutable roster, and shared
  coordination history. A Party survives roster and presence changes until it
  is authoritatively retired; one Character belongs to at most one active Party.
  _Avoid_: group (overloaded by engineering and external-game terminology),
  squad, raid, team.
- **Party membership**: The authoritative relationship between a Character and
  an active Party. Membership begins through accepted consent and ends through
  leave, removal, timeout, or Party retirement; it is not inferred from a live
  network connection, scene proximity, or current Sector.
  _Avoid_: Player membership, peer membership, Account membership.
- **Party presence**: A Party member's current in-world availability as a
  Player, distinct from Party membership. Connection loss or movement between
  Sectors changes presence without itself expressing consent to leave.
  _Avoid_: membership status, online membership.
- **World DM**: The campaign-level narrative authority that interprets global
  timeline, faction, regional, and cross-Character consequences and publishes
  bounded world context. A World DM proposes semantic changes; it does not own
  authoritative gameplay state.
- **Party DM**: The group-campaign narrative role that coordinates a Party's
  shared objectives, history, relationships, and encounters while preserving
  each Character's personal authority and progression.
- **Personal DM**: The Character-level narrative role that uses personal
  memory, Party context, and relevant World DM bulletins to propose immediate
  stories, encounters, and locations for one Player.
- **DM Guild**: The coordinated hierarchy of World DM, Party DM, and Personal
  DM roles. It is a semantic proposal system, not a replacement for the
  server-authoritative simulation or persistence boundary.
- **Encounter**: A bounded, server-owned attempt to resolve a hostile or world
  objective. It begins and ends with authoritative objective state, may involve
  Party and non-Party Characters, and retains its own participation history
  independently of later roster changes.
  _Avoid_: fight (not every Encounter is combat), Party event, client session.
- **Participation evidence**: Authoritative facts that a Character performed
  meaningful, relevant actions during an Encounter. Party membership,
  proximity, presence, or another Character's actions are context, never
  participation evidence by themselves.
  _Avoid_: contribution score (evidence is not one universal public number),
  shared experience, attendance.
- **Encounter credit**: The terminal, personal fact that a Character qualified
  for successful Encounter completion. Matching quest objectives or loot
  allocation may consume this fact, but it is not conventional experience,
  an item, or another Character's embodied training evidence.
  _Avoid_: shared XP, Party reward, duplicated loot.
- **Flat plane**: The minimal placeholder ground scene used to prove movement
  without committing to any generated or hand-built map. Authoritative as the
  current slice's only world geometry.
  _Avoid_: level, map, world (those terms are reserved for the future
  generated/canon world).
- **World unit**: The base spatial unit of the game world. One world unit =
  **1 yard** (Imperial); the world scale reads in feet/yards up close and miles
  at the region level. All in-engine positions, speeds, and sizes are expressed
  in world units, anchored and converted through `WorldScale`
  (`shared/world_scale.gd`); see [ADR 0003](docs/adr/0003-imperial-world-scale.md).
  _Avoid_: meter (Godot's default convention, which this project overrides),
  pixel.
- **Sector**: A unit of JIT-generated world content produced by the local LLM,
  validated, then committed through the server-owned Canon persistence service. Its nominal span is
  **≈ ¼ mile = 440 world units** (tunable via `WorldScale`, growing toward
  1 mile = 1760); a Sector is a **region container** whose fine Tile detail
  covers only a bounded sub-area, not every yard (see
  [ADR 0003](docs/adr/0003-imperial-world-scale.md)). Generation is asynchronous;
  an unseen coordinate is requested from an authoritative boundary transition,
  and only the stored Canon result is replicated.
  _Avoid_: chunk, tile map, level.
- **Canon**: World state that has been validated and persisted to the
  server-owned persistence service, making it authoritative and durable across
  sessions. Canon sectors are immutable at their base revision; an append-only,
  idempotent mutation history yields an effective blueprint for replication.
  _Avoid_: save data, world save.
- **World blueprint**: A portable, structured description of semantic world
  intent, including regions, relationships, landmarks, themes, puzzle intent,
  entity roles, and bounded generation constraints. It is an intermediate
  representation interpreted by replaceable deterministic builders, not a
  renderer-specific scene or gameplay result.
- **World builder**: A deterministic interpreter that turns an accepted World
  blueprint into geometry, collision, navigation, entities, presentation, and
  runtime state. A builder validates physical feasibility and never grants
  authority to an LLM proposal.
- **Player-built place**: A persistent player- or Party-owned modification to
  the world, such as a home, workshop, shared base, settlement, or town. It is
  Canon state with explicit ownership, permissions, spatial validation, and
  history; it is not disposable client decoration.
- **Structure**: A building placement within a sector blueprint (e.g. player
  `house`, villager `npc_house`, the `village_hall` leader's house, smithy,
  armor shop, inn, and the schema-v3 flavor kinds church, item shop, tavern,
  well), identified by a unique `structure_id` and an anchor point/facing rather
  than a footprint. Implemented: schema v2 (Slice 014) added the `structures`
  array, schema v3 (Slices 025/031) added the organic settlement kinds, and
  geometry translation (Slices 015/024) instantiates one placeholder prefab per
  structure. Only `house` structures form the player pool (HouseAllocator);
  `npc_house` and `village_hall` are non-player buildings.
  _Avoid_: building (a Structure covers non-house placeables like a well; keep
  the neutral term canonical). A gate is a Tile kind, not a Structure.
- **Tile**: The fine grid cell of a sector blueprint — one world unit (1 yard)
  square — placed by the blueprint `tiles` array as walkable detail (floors,
  walls, paths). The detail grid: a Sector's fine content is a bounded field of
  Tiles, not the whole region (see
  [ADR 0003](docs/adr/0003-imperial-world-scale.md)). Distinct from **Tile kind**
  (the Tile's terrain class).
  _Avoid_: cell, square; do not conflate with the coarser Sector.
- **Tile kind**: The terrain class of a blueprint tile. Base kinds
  (schema v1+): `floor`, `wall`, `corridor`. Organic vocabulary (schema v3,
  Slice 025): `path`, `plaza`, `gate`, `water`, `grass`. Only `wall` is solid
  (gets collision); the rest are visual ground merged into one mesh per kind by
  the geometry pass.
  _Avoid_: terrain type, biome (kind is the blueprint/validator term).
- **Spawn point**: A monster-instantiation marker within a sector blueprint,
  distinct from a Structure (not rendered or enterable). Spawn points are
  implemented in the blueprint schema and used by the current basic Monster
  manager; future archetype breadth remains a gameplay decision.
  _Avoid_: spawner, spawn tile.
- **Hub sector**: The reserved `starting_town_hub` starting-town blueprint.
  It is materialized fail-closed at boot, validated, and canonicalized by the
  server; its shipped fixture and optional LLM proposal are inputs, while its
  accepted stored record is Canon.
  _Avoid_: starting sector (ambiguous with a future player-specific spawn
  concept), canon town (it is not Canon in the persisted-and-frozen sense
  until Phase 9 exists).
- **Monster**: A server-authoritative, non-player combat target with a flat,
  explicitly provisional HP pool (the shared `CombatHealth` contract in
  `shared/combat_health.gd`, seeded at `MonsterContracts.MAX_HP`; Slice 126
  retired the provisional `MonsterCombatState`), distinct from `TargetDummy`
  (which has no HP/death at all). Provisional — decided by
  [Basic Monsters map](.scratch/basic-monsters/map.md) ticket 01; the HP
  model here is a placeholder for the future six-node vessel-derived health
  formula (Phase 12, 0% built).
  _Avoid_: enemy, mob (keep the term consistent with this repo's existing
  "Player"/"TargetDummy" naming register).
- **Client build version**: The semver identity of a packaged Windows client
  build, used by the server-owned pre-auth version gate. Distinct from a data
  contract's `schema_version` or `tuning_version`.
- **Update manifest**: The offline-signed release record that binds one client
  build version to one full `Project0.pck` URL, byte size, and SHA-256.
- **Patch**: A full replacement `Project0.pck` for one client build version;
  v1 does not use delta patches.
- **Version handshake**: The first client/server message after connection and
  before authentication, where the client presents its build version and the
  server accepts or rejects it.
- **Ops snapshot**: A versioned, server-owned, bounded current-state read model
  for operator telemetry. It is not gameplay authority or historical metrics.
- **Operator console**: The standalone LAN service that reads Ops snapshots and
  submits bounded authenticated control actions.
- **Control action**: A versioned request for one bounded operator operation;
  gameplay and Canon/progression mutation are excluded.
- **Operator token**: A signed credential carrying operator identity and scopes,
  independently verified by each control executor.
- **Server registry**: The manifest-backed mapping from server id/type to its
  snapshot location and control metadata.
- **Drain**: A server-authoritative mode that refuses new connections while
  allowing existing sessions to finish or disconnect normally.
- **Degraded**: An explicit server health state with a bounded reason, visible
  to operators and never inferred from arbitrary player-facing text.

## External contexts

- **Ollama API** (`http://127.0.0.1:11434`, local Llama-3-8B on a Tesla P100):
  Supplemental, server-side-only inference source for sector generation. It is
  never authoritative by itself: the server validates output before it can be
  stored as Canon.
- **SQLite Canon database**: The server-owned durable store for validated,
  immutable sector records and their append-only mutation logs. It is separate
  from the accounts store when the split runtime is configured.

## Invariants

- The client never directly contacts Ollama or the Canon SQLite store.
- Account, Character, Canon, and mutation state are server-owned; assertions
  and client presentation state are not durable client authority.
- A Sector is never treated as Canon until the server has validated and written
  it to the SQLite Canon store.

## Ambiguity policy

When evidence conflicts or is incomplete, preserve the source evidence, surface
the ambiguity, and define whether the affected action is blocked, retried, or
sent for review. Never silently guess.
