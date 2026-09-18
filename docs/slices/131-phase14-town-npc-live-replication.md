# Slice 131 - Phase 14 integration: town NPCs live in server_main + client replication (closes the exit gate)
GitHub issue: #227

Status: **delivered**

Phase: 14 (NPC generalization and shared Character)

Feature: [F-036](../FEATURE-LIST.md#f-036-phase-14-unified-character-and-npc-generalization)

Design source: [#229](https://github.com/vnvalentin/project0/issues/229),
[#232](https://github.com/vnvalentin/project0/issues/232),
[ADR 0007](../adr/0007-unified-character-and-npc-generalization.md). Third of three
slices closing the exit gate's "What Good Looks Like" items 4 and 6; makes the
`ServerTownNpcState`/`ServerTownNpcManager` subsystem live and visible.

## User outcome

Living townsfolk now actually appear in the running game. The server staffs the
town's fixed anchors with town NPCs that walk their daily routes between the
forge, market, and tavern; a connecting player sees them arrive where their
schedule says, and sees replacements fade in after a delay (promoted or newly
generated) when one is lost — never a resurrected clone.

## Scope and non-goals

In scope: instantiating and driving `ServerTownNpcManager` in the live
`server_main` (a first-cut fixed set of in-town anchors), replicating town-NPC
spawn/position/despawn to clients on peer-scoped/broadcast RPCs mirroring the
monster channel, and a self-contained cosmetic client representation
(`client/town_npc.gd`, teal, position-smoothed).

Out of scope: deriving anchors from the town blueprint's structures (a fixed set
for now), pathfinding, town-NPC combat, and a per-NPC vessel HUD. These are
future polish, not gate requirements.

## Public seam

- Server: `server/server_main.gd` drives `_town_npc_manager.advance` each physics
  frame, broadcasts positions, and replicates spawns/despawns;
  `server/server_town_npc_manager.gd` gains `all_npcs()` / `find_npc()`.
- Client: `client/network_client.gd` — `receive_town_npc_spawn` /
  `receive_town_npc_position` / `receive_town_npc_despawn` + the static
  `spawn_town_npc_representation` / `apply_town_npc_position` /
  `despawn_town_npc_representation` / `town_npc_node_name` seams;
  `client/town_npc.gd` renders one NPC; `connection_status.gd` flushes pending
  town NPCs on scene entry.

## Falsifiable hypothesis

If the town-NPC subsystem is driven by the live server and replicated on the same
channel shape as monsters, then town NPCs appear and move route-consistently for
connected players with no change to existing player/monster replication — closing
items 4 and 6 end-to-end.

## SDD

`server_main` instantiates `ServerTownNpcManager` with `_default_town_anchor_defs()`
(fixed in-town anchors + short routes), connects `npc_spawned`/`npc_removed`, and
each physics frame calls `advance` (with player positions for pressure), then
broadcasts `receive_town_npc_position` for every live NPC's `position_at(tick)`.
Peer connect replays existing NPC spawns; `npc_spawned`/`npc_removed` broadcast
spawn/despawn. The client render seam mirrors the monster helpers exactly (static,
parent-injected, idempotent). The town-NPC channel is additive; the monster and
player channels are untouched.

## BDD

1. Given the server boots, then it staffs the town anchors and drives them each
   tick.
2. Given a peer connects, then it receives a spawn for every live town NPC.
3. Given each tick, then every town NPC's authoritative route position is
   broadcast; the client node smooths toward it.
4. Given a delayed replacement/promotion, then a spawn is broadcast; given a
   removal, a despawn is broadcast.
5. Given the static render seam, then spawns are idempotent per npc_id, positions
   update the right node, and despawns remove it — no-ops on unknown ids.

## TDD / validation

```bash
bash scripts/run_gut_validation.sh
bash scripts/check_record_sync.sh
```

**Delivered evidence (2026-09-17, Linux host `okami`, consistent temp tree):**
the full cumulative Phase 14 tree (main through Slice 130 + this slice) ran green
— **87 scripts / 632 tests / 632 passing, exit 0, "All tests passed!"**, no
failing blocks. This includes the socket **E2E harnesses** (authoritative melee
strike, multi-peer replication) that boot the real `server_main` + `gameplay.tscn`
— they pass with the live town-NPC manager running and broadcasting. New
`test_town_npc_replication.gd` ran **7/7** (namespaced node names, idempotent
spawn, distinct nodes, position apply, unknown-id no-op, despawn), alongside the
prior town-NPC tests (`test_server_town_npc_state` 9/9,
`test_server_town_npc_manager` 7/7) and the parity test (4/4).
`check_record_sync.sh` exit 0. The "Parameter m is null"
(`mesh_get_surface_count`) lines are pre-existing headless dummy-renderer noise,
not failures.

## Root-cause learning

- **Symptom:** validating on okami's deploy tree by staging only this slice's
  changed files, the two socket E2E harnesses failed with
  `Invalid access to property or key 'character_snapshot_ready' on
  server_player_state.gd`, and piecemeal-staging `server_player_state` then
  dropped ~32 more tests.
- **Public seam:** the GUT validation gate on okami.
- **Hypothesis / discriminating check:** okami's `/data/code/project0` is a DEPLOY
  TREE frozen far behind `main` (no `.git`), so `server_main` (with the Slice 127
  signal connection) was validated against a pre-127 `server_player_state`. `ls`
  confirmed the drift; a full consistent tree would resolve it.
- **Confirmed root cause:** cumulative deploy-tree drift — Slice 131 depends on the
  merged-but-undeployed state of Slices 116–130, which piecemeal staging cannot
  reconstruct. Not a code defect (the code is correct against `main`).
- **Countermeasure:** validate cumulative slices on a throwaway temp tree — copy
  the deploy tree (keeping its built Linux addon binaries) to `/tmp/p0v`, overlay
  the full local `shared/server/client/tests` (main + slice), run the suite there,
  and delete it. Recorded in repo memory.
- **Regression evidence:** the 632/632 green run on the consistent temp tree,
  including the E2E harnesses.

## Safety invariants

- The server owns all town-NPC state and replication; clients only render.
- The town-NPC channel is additive; existing player/monster/identity replication
  is untouched (proved by the unchanged E2E harnesses).
- Client render seams are idempotent and no-op on unknown ids.

## ADR and debt

Architecture: [ADR 0007](../adr/0007-unified-character-and-npc-generalization.md).
No new technical-debt entry. Fixed (not blueprint-derived) anchors and no
pathfinding are deliberate first-cut scope. **This slice closes the Phase 14
F-036 exit gate**: the shared Character seam is implemented and validated for
Player/NPC state, baseline, development, techniques, equipment, movement,
combat/status, disposition, relevance, and role-based spawning — live and without
duplicating Monster logic.
