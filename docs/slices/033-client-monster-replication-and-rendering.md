# Slice 033: Client monster replication and rendering

Tracker context: Phase 10 — Authoritative runtime and action input; completes
[IP-023](../FEATURE-LIST.md#ip-023-basic-monster-combat)'s "visible to and
fightable by players" boundary. Fifth Basic Monsters slice; the client-side
half of the two-slice boundary recorded in
[Slice 022's "next boundary"](022-monster-spawning-and-respawn.md#explicit-non-goals-and-next-boundary)
and [Slice 029's "next boundary"](029-authoritative-monster-melee-damage.md#explicit-non-goals-and-next-boundary),
where it was called "Slice 030." It is delivered here as **Slice 033**: by the
time this slice started, `docs/slices/030-server-side-collision.md` and
`docs/slices/032-wgnetstack-netstack-bridge-linux-prototype.md` had already
been allocated by concurrent uncommitted work (see
[SLICE-REGISTRY.md](SLICE-REGISTRY.md)), so this slice reserved the next free
number, 033, there before writing this file.

## SDD

Goal: replicate every currently living server-authoritative monster
(`server/server_monster_manager.gd`) to connected clients and render a visible,
purely cosmetic representation that moves with the server's authoritative
position, reacts to an existing `COMBAT_EVENT_HIT` for its own `target_id`,
and disappears on `COMBAT_EVENT_DEATH` / reappears on respawn — mirroring the
existing remote-player replication pattern
(`spawn_remote_player_representation` / `receive_remote_player_position` /
`despawn_remote_player_representation`) and the existing target-dummy hit
reaction (`client/target_dummy.gd`) rather than inventing a new pattern.

Public seams:

- `client/network_client.gd` — three additions, one-for-one with the
  remote-player seam:
  - `receive_monster_spawn(target_id, start_position)` (RPC, reliable,
    authority → client): thin wrapper that resolves/creates the `Monsters`
    container under the current scene's Gameplay root and delegates to the
    static seam below.
  - `receive_monster_position(target_id, position)` (RPC, unreliable,
    authority → client): thin wrapper delegating to the static
    `apply_monster_position` seam; a no-op if the `Monsters` container does
    not exist yet (e.g. before the first spawn).
  - Static, parent-injected seam (mirrors `render_sector_blueprint`'s
    testability style, so none of this needs a live ENet peer or
    `current_scene`):
    - `spawn_monster_representation(target_id, start_position, parent)`:
      idempotent — a duplicate spawn for an already-represented `target_id` is
      a no-op, matching `spawn_remote_player_representation`.
    - `apply_monster_position(target_id, position, parent)`: forwards the
      position to the existing node for `target_id`; a no-op if none exists.
    - `despawn_monster_representation(target_id, parent)`: removes the node
      for `target_id`; a no-op if already gone, matching
      `despawn_remote_player_representation`.
    - `monster_node_name(target_id) -> String`: `"Monster_<target_id>"`, the
      single naming authority both the spawn and lookup paths use.
  - `MONSTERS_CONTAINER_NAME = "Monsters"`, a dedicated child of the Gameplay
    root created on first use via `_get_or_create_monsters_container`, exactly
    like the existing `RemotePlayers`/`SectorGeometry` containers — never a
    static node in `client/gameplay.tscn`.
- `client/monster.gd` + `client/monster.tscn`: a new cosmetic node, one
  instance per `target_id`, structurally mirroring `client/remote_player.gd`
  (bounded smoothing toward the latest authoritative position using the same
  `NETWORKED_PLAYER_SNAP_DISTANCE`/`NETWORKED_PLAYER_SMOOTH_SPEED` constants)
  and `client/target_dummy.gd` (listens to `NetworkClient.combat_event_received`
  directly, reacts only to events naming its own `target_id`). A dark-red
  `BoxMesh` distinguishes it at a glance from the player capsules (red/blue/
  yellow) and the gray target dummy. On `COMBAT_EVENT_HIT` it plays the same
  brief flash/wobble as `target_dummy.gd`; on `COMBAT_EVENT_DEATH` it plays a
  brief shrink reaction, then frees itself — so despawn-on-death is owned by
  the node itself, not a second listener in `network_client.gd`.
- `server/server_main.gd` — three additions, mirroring the existing
  remote-player broadcast wiring:
  - `_on_peer_connected`: after the existing remote-player replication loop,
    if a monster manager exists, RPCs `receive_monster_spawn` to the *new*
    peer only, once per `_monster_manager.living_targets()` entry (existing
    peers already have every current monster's representation from their own
    connect or the server's initial monster spawn, so they are not re-sent).
  - `_on_physics_frame`: after `_monster_manager.advance_all(...)`, calls a
    new `_broadcast_monster_positions()` helper that RPCs
    `receive_monster_position` for every `living_targets()` entry to every
    connected peer — the per-entity relay shape of the existing
    `_on_player_state_position_updated`, just driven once per physics frame
    from the manager's snapshot instead of from a per-entity signal.
  - `_on_monster_respawned`: in addition to its existing telemetry `print`,
    now also RPCs `receive_monster_spawn` for the respawned `spawn_id`/
    `position` to every connected peer, so a respawned monster reappears on
    every client without a separate "monster removed" cycle first.

Implementation decisions:

- **Reuse `COMBAT_EVENT_DEATH` for despawn, add no parallel channel.** The
  brief explicitly asked to justify not adding a redundant "monster removed"
  RPC. Slice 029 already broadcasts an attacker-attributed
  `COMBAT_EVENT_DEATH` over `receive_combat_event` the instant
  `ServerMonsterManager.receive_player_hit` reports a kill. `client/monster.gd`
  already needs to listen to `combat_event_received` for the `HIT` reaction, so
  adding a `DEATH` branch to the same listener is strictly less code and one
  fewer authoritative channel than a second "despawn" RPC would be, and it
  keeps despawn causally tied to the same event that killed the monster
  server-side rather than a second, potentially-reorderable message.
- **Respawn reuses the spawn RPC, not a new "monster reappeared" message.**
  `receive_monster_spawn` is already idempotent
  (`spawn_monster_representation` no-ops if a node for that `target_id`
  already exists). Since the client already freed the previous node on
  `COMBAT_EVENT_DEATH` by the time a respawn can occur (respawn has a
  multi-second server-side cooldown — `RESPAWN_COOLDOWN_TICKS` — that always
  outlasts the client's own short death-reaction animation), calling
  `receive_monster_spawn` again on respawn always creates a fresh
  representation rather than silently no-op'ing against a stale one.
- **Per-frame broadcast driven by the manager's snapshot, not a per-monster
  position-changed signal.** `ServerMonsterManager` has no per-tick
  "position changed" signal (monsters move continuously every frame, unlike a
  player's discrete `position_updated`), so mirroring
  `_on_player_state_position_updated` exactly was not possible. Instead
  `_broadcast_monster_positions()` is called once, after `advance_all`, and
  iterates the same `living_targets()` seam Slice 029 already uses for hit
  testing — one additional read-only pass over already-computed state, no new
  manager API.
- **Static, parent-injected client seam, matching `render_sector_blueprint`.**
  All three spawn/position/despawn operations are implemented as static
  functions taking an explicit `parent: Node3D`, exactly like
  `NetworkClient.render_sector_blueprint`. This is what makes
  `tests/integration/test_monster_replication.gd` possible without a live
  ENet peer, a `current_scene`, or a `NetworkClient` autoload instance — the
  RPC targets (`receive_monster_spawn`/`receive_monster_position`) are thin,
  untested-in-isolation wrappers over these tested seams, the same relationship
  `receive_sector_blueprint` has to `render_sector_blueprint`.
- **Visually distinct mesh/color.** Players render as capsules (red local,
  blue own-networked, yellow remote); the target dummy is a gray capsule.
  Monsters render as a dark-red `BoxMesh` so a human can distinguish "a
  fightable monster" from "a person" or "the stationary practice dummy" at a
  glance, per the slice's "visually distinct" requirement.

## BDD

### A newly connecting peer sees every currently living monster

Given one or more monsters are alive when a new peer connects
When `_on_peer_connected` runs
Then the server RPCs `receive_monster_spawn` to that peer once per living
monster, each at that monster's current authoritative position.

### Every peer sees a living monster move each physics frame

Given at least one connected peer and at least one living monster
When a physics frame advances the monster's AI
Then the server RPCs `receive_monster_position` for that monster's
`target_id` and current position to every connected peer.

### A spawned representation is idempotent per target_id

Given a monster representation already exists under the Monsters container
When `spawn_monster_representation` is called again for the same `target_id`
Then no second node is created and the existing node's position is
unaffected.

### A position update moves the existing node, and is a no-op for an unknown one

Given a monster representation exists for `target_id`
When `apply_monster_position` is called for that `target_id`
Then the existing node's target position updates;
And when called for a `target_id` with no representation, nothing is created
and nothing errors.

### A monster reacts to its own HIT and ignores others'

Given a client/monster.gd node bound to `target_id = "m0"`
When `NetworkClient.combat_event_received` fires `COMBAT_EVENT_HIT` for
`"m0"`
Then the node starts its cosmetic flash/wobble reaction;
And when the same signal fires for a different `target_id`, the node does
not react.

### A monster frees itself on its own DEATH and ignores others'

Given a client/monster.gd node bound to `target_id = "m0"`
When `NetworkClient.combat_event_received` fires `COMBAT_EVENT_DEATH` for
`"m0"`
Then the node plays a brief death reaction and then frees itself;
And when the same signal fires for a different `target_id`, the node is
neither queued for deletion nor otherwise affected.

### Despawn is idempotent

Given a monster representation exists, or does not exist, for `target_id`
When `despawn_monster_representation` is called for that `target_id`
Then an existing node is removed, and calling it again (or calling it when no
node ever existed) is a safe no-op.

## TDD evidence

- `tests/integration/test_monster_replication.gd` (7 new tests): spawn creates
  exactly one node per `target_id`; a duplicate spawn is a no-op and does not
  move the existing node; two distinct `target_id`s produce two distinct
  nodes; a position update moves the existing node; a position update for an
  unknown `target_id` creates nothing; despawn removes the node; despawn of an
  already-gone monster is a safe no-op.
- `tests/unit/test_monster_node.gd` (4 new tests): a `HIT` for the node's own
  `target_id` starts the reaction (asserted via the node's own
  `_hit_reaction_time_remaining` state); a `HIT` for a different `target_id`
  is ignored; a `DEATH` for the node's own `target_id` frees it (waited out
  across enough physics frames for the death-reaction timer to elapse); a
  `DEATH` for a different `target_id` leaves the node alone.
- Both files were run against the pre-implementation tree first and failed
  closed as expected: `Invalid call. Nonexistent function
  'spawn_monster_representation'/'receive_monster_position'/
  'despawn_monster_representation'` (integration test) and a parse failure on
  the not-yet-existing `res://client/monster.tscn` (unit test) — see
  Validation below for the post-implementation green run.

## ADR decision

No new ADR. This slice adds no new authority boundary — it is a purely
cosmetic client-rendering layer over state Slices 020–022/029 already made
authoritative, following the exact remote-player replication pattern
[ADR 0001](../adr/0001-client-side-authority-for-first-slice.md) and
[ADR 0002](../adr/0002-authoritative-mechanics-and-progression.md) already
established. `client/monster.gd` never applies damage, decides a hit, or
decides death/respawn; it only renders positions and reacts to combat events
the server has already broadcast.

## Validation

- `godot --headless --path . --check-only -s res://client/network_client.gd`: exit 0.
- `godot --headless --path . --check-only -s res://server/server_main.gd`: exit 0.
- `godot --headless --path . --check-only -s res://tests/integration/test_monster_replication.gd`: exit 0.
- `godot --headless --path . --check-only -s res://client/monster.gd` and
  `res://tests/unit/test_monster_node.gd`: each reports `Identifier not found:
  NetworkClient` when checked in isolation. This is a pre-existing property of
  every script that references the `NetworkClient` autoload outside a running
  project/test harness — `client/target_dummy.gd` and
  `client/remote_player.gd` fail the identical `--check-only` invocation the
  same way today on `main`. It is not a regression; both files parse and run
  correctly inside the real GUT harness below, which does register autoloads.
- `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gselect=test_monster_node -gexit`:
  PASS, 4/4 tests, 4 asserts, exit 0.
- `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/integration -gselect=test_monster_replication -gexit`:
  PASS, 7/7 tests, 12 asserts, exit 0.
- `scripts/run_gut_validation.sh`: PASS, 199/199 tests, 26/26 scripts
  (`scripts_expected == scripts_ran`, no silently skipped script), 793
  asserts, exit 0 (includes substantial unrelated concurrent work already in
  the tree — organic-village, wireguard, server-side collision, bigger
  village, ci/ — plus this slice's additions).

**Interactive GUI confirmation obtained (2026-09-13, human-confirmed).** Per
this repository's rule against claiming runtime behavior from headless tests
alone, a human ran the client against the restarted `project0-server` and
visually confirmed: a monster renders as a distinct dark-red box; it visibly
moves/chases; it flashes on a landed hit; it disappears on death; and it
reappears after the respawn cooldown at its new position. With this evidence
captured, IP-023 moved from `In Progress` to `Implemented`.

## Explicit non-goals and next boundary

This slice adds no monster-to-player damage, no player HP, no loot, no
pathfinding, no destructible spawner, and no HUD health bar — the client
renders position and reacts to the two existing combat events only, deciding
nothing itself. With this slice, the server-authoritative monster lifecycle
(Slices 020–022, 029) has a complete, purely cosmetic client presentation; the
interactive GUI confirmation recorded above was obtained, so IP-023 is
`Implemented` with no further monster-combat implementation work outstanding.
