# Slice 130 - Phase 14 integration: live town-NPC population manager (SpawnAnchor)
GitHub issue: #227

Status: **delivered**

Phase: 14 (NPC generalization and shared Character)

Feature: [F-036](../FEATURE-LIST.md#f-036-phase-14-unified-character-and-npc-generalization)

Design source: [#232](https://github.com/vnvalentin/project0/issues/232)
(anchors, population, replacement, significance), [ADR 0007](../adr/0007-unified-character-and-npc-generalization.md).
Second of three slices closing the exit gate's "What Good Looks Like" item 6.
Consumes [Slice 124](124-phase14-spawn-anchor.md)'s `SpawnAnchor` and
[Slice 129](129-phase14-town-npc-state.md)'s `ServerTownNpcState`.

## User outcome

The town stays believably populated on its own: each fixed anchor (the forge, the
market) keeps its role staffed with a live town NPC. When one is lost, the anchor
does not instantly pop a clone back — after a delay, shorter when players are
around, the role is refilled either by silently promoting a nearby ambient NPC or
by a freshly generated, contextually-named newcomer. The same person never comes
back from the dead.

## Scope and non-goals

In scope: `server/server_town_npc_manager.gd` — instantiates town NPCs at fixed
anchors, drives population via `SpawnAnchor` (deficit, pressure-scaled delayed
replacement, promote-ambient-or-generate-identity), and emits spawn/removal
telemetry.

Out of scope: wiring the manager into `server_main` and replicating town NPCs to
clients (Slice 131), deriving anchors from a real town blueprint (Slice 131
supplies them; here they are constructor input), rich contextual generation
(a role-flavoured name only), and driving the NPCs' per-tick movement (that is
`ServerTownNpcState`'s pure `position_at`, called by the runtime in 131).

## Public seam

`server/server_town_npc_manager.gd` (`ServerTownNpcManager`): `anchor_count()`,
`npc_count()`, `npcs_at(index)`, `anchor_deficit(index)`,
`add_ambient_candidate(name)`, `remove_npc(anchor_index, npc_id, tick)`,
`advance(observer_positions, ticks, tick)`, and the `npc_spawned` / `npc_removed`
signals.

## Falsifiable hypothesis

If town population runs on `SpawnAnchor`, then anchors stay staffed, a lost
occupant is refilled only after a pressure-scaled delay (never an instant clone),
and the refill is a promotion or a new identity — never a resurrection — all
provable deterministically, reusing the shared spawning contract.

## SDD

Each anchor is a `SpawnAnchor` (desired capacity, replacement delay); the manager
holds the live `ServerTownNpcState` objects. Anchors start staffed to capacity.
`remove_npc` vacates an anchor; `advance` accumulates each understaffed anchor's
vacancy clock and, when `plan_replacement(pressure, has_ambient)` is due, staffs
it. Pressure is 1.0 when a player is within `PRESSURE_RADIUS_YARDS` of the anchor
(shortening the delay). Sourcing promotes an ambient candidate (reusing its name,
no pop-in) when available, else generates a fresh role-flavoured identity with a
unique id. RefCounted + deterministic, unit-testable like `ServerMonsterManager`.

## BDD

1. Given anchors, when created, then each starts staffed to capacity.
2. Given a lost occupant, when removed, then its anchor is understaffed.
3. Given no pressure, when time passes below the delay, then no replacement
   occurs.
4. Given the delay elapses, when advanced, then a NEW identity is generated (not
   the same individual).
5. Given an ambient candidate, when a replacement is due, then it is silently
   promoted into the role.
6. Given a nearby player, when advanced, then pressure shortens the delay to an
   immediate refill.
7. Given repeated replacements, then each generated identity is unique.

## TDD / validation

```bash
bash scripts/run_gut_validation.sh
bash scripts/check_record_sync.sh
```

**Delivered evidence (2026-09-17, Linux host `okami`):** full GUT suite green —
**73 scripts / 500 tests / 500 passing, exit 0**. The new
`test_server_town_npc_manager.gd` ran **7/7** (staffed-to-capacity, understaffing
on removal, no-instant-respawn-before-delay, generate-new-identity-after-delay,
silent promotion of an ambient candidate, pressure-shortens-the-delay, and unique
generated identities). `check_record_sync.sh` exit 0. GUT cannot run on Windows,
so validation was on the Linux host per repo convention; the new files and their
merged-but-undeployed dependencies (`character_foundation`, `activity_routine`,
`spawn_anchor`, `server_town_npc_state`) were staged and then removed.

## Safety invariants

- The server owns town population; nothing is client-authored.
- Replacement is always delayed and pressure-clamped; occupancy is bounded to the
  anchor capacity; a lost occupant is replaced by promotion or a new identity —
  never resurrected.
- Generated identities are unique.

## ADR and debt

Architecture: [ADR 0007](../adr/0007-unified-character-and-npc-generalization.md).
No new technical-debt entry. Simple role-flavoured name generation and
constructor-supplied anchors are deliberate first-cut scope, not liabilities;
`server_main` wiring + client replication follow in Slice 131.
