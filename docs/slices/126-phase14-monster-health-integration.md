# Slice 126 - Phase 14 integration: Monster HP on the shared CombatHealth contract
GitHub issue: #227

Status: **delivered**

Phase: 14 (NPC generalization and shared Character)

Feature: [F-036](../FEATURE-LIST.md#f-036-phase-14-unified-character-and-npc-generalization)

Design source: [#231](https://github.com/vnvalentin/project0/issues/231)
(shared health/defeat/recovery), [ADR 0007](../adr/0007-unified-character-and-npc-generalization.md).
Retires the provisional `MonsterCombatState` from
[Slice 020](020-monster-hp-damage-death.md); consumes
[Slice 120](120-phase14-combat-health.md)'s `CombatHealth`; mirrors
[Slice 125](125-phase14-player-health-integration.md) for the monster.

## User outcome

Monsters and the player now run their health on the same shared rule. A
monster still takes exactly three hits to defeat and dies once, exactly as
before — but its HP is now the tested shared `CombatHealth` contract, so player
and NPC durability are one unified concept, not two parallel placeholders.

## Scope and non-goals

In scope: replacing the monster's server-owned `MonsterCombatState` flat pool
with the shared `CombatHealth` contract, seeded at `MonsterContracts.MAX_HP`;
retiring the `MonsterCombatState` class and its now-redundant unit tests (its
damage/defeat behaviour is owned and tested by `CombatHealth`).

Out of scope: any change to `ServerMonsterState`'s phase machine, damage
amounts, respawn, or the `DEATH` combat event; vessel-derived health (Phase 15);
and unifying the monster onto the full `CharacterFoundation` (a later slice).
This is an internal, behaviour-preserving swap.

## Public seam

`server/server_monster_state.gd`: `current_hp()`, `is_dead()`, and
`receive_damage()` — unchanged in shape and behaviour; the monster's pool is now
a `shared/combat_health.gd` (`CombatHealth`) instance from
`MonsterContracts.default_monster()`. `shared/monster_contracts.gd` keeps its
`MAX_HP` / `DAMAGE_PER_HIT` / `DAMAGE_TO_PLAYER` seeds and the reach/arc
archetype; only the `MonsterCombatState` class is retired.

## Falsifiable hypothesis

If the monster HP pool is swapped to `CombatHealth` while preserving
`ServerMonsterState`'s seam, then the monster combat, death, and respawn tests
pass unchanged — proving both combatants can share one health contract, the same
pattern used for the Player in Slice 125.

## SDD

`MonsterContracts.default_monster()` now returns `CombatHealth.new(float(MAX_HP),
float(MAX_HP))`. `ServerMonsterState.current_hp()` rounds the float pool to an
int; `receive_damage` preserves the retired `MonsterCombatState` death semantics
exactly: capture `was_alive` before `take_damage`, and enter `PHASE_DEAD` +
emit exactly one `died` only when a still-living monster is reduced to 0. The
early `PHASE_DEAD` return already prevents a second death. `MonsterCombatState`
is deleted; `MAX_HP` stays as the seed (still equal to `PLAYER_MAX_HP` so player
and monster start equally durable).

## BDD

1. Given a fresh monster, when HP is read, then it is full at `MAX_HP`.
2. Given a player's landed hit, when applied, then HP drops by `DAMAGE_PER_HIT` —
   unchanged.
3. Given three hits, when applied, then the monster dies once with one attacker
   attributed — unchanged.
4. Given an already-dead monster, when hit again, then no second death is
   emitted — unchanged.
5. Given a defeated monster, when the cooldown elapses, then it respawns outside
   town — unchanged.

## TDD / validation

```bash
bash scripts/run_gut_validation.sh
bash scripts/check_record_sync.sh
```

**Delivered evidence (2026-09-17, Linux host `okami`):** full GUT suite green
after the migration — **72 scripts / 489 tests / 489 passing, exit 0**. The
behaviour-preserving regression net passed unchanged: `test_server_monster_
state.gd` **10/10** (incl. `test_receive_damage_kills_and_emits_one_death` and
the dead-monster no-op), `test_server_monster_manager.gd` **19/19** (incl.
damage-per-hit, three-hit death, respawn, dead-target no-op), and the
integration `test_authoritative_melee_strike.gd` **9/9** (incl. three-hits →
one attributed death and no-double-damage) — the latter two exercising the real
`ServerMonsterManager`/`ServerMonsterState` node path, i.e. runtime evidence
that live monster combat is unchanged. The rewritten `test_monster_contracts.gd`
ran **2/2** (seeds a full `CombatHealth` pool + the `DEATH` event kind).
`check_record_sync.sh` exit 0. GUT cannot run on Windows, so validation was
performed on the Linux host per repo convention; `combat_health.gd` (merged to
main, absent from okami's deploy tree) was staged for the run and then removed,
and the three modified tracked files were restored from backup.

## Safety invariants

- The server remains the sole authority for monster HP; the client only displays
  replicated state.
- Damage never heals and HP stays within `[0, max]` (enforced by `CombatHealth`).
- Exactly one death is emitted per still-living→0 transition; a dead monster
  ignores further damage — unchanged.
- No wire/replication shape changed, so no client update is required.

## ADR and debt

Architecture: [ADR 0007](../adr/0007-unified-character-and-npc-generalization.md).
No new technical-debt entry: this removes a provisional placeholder in favour of
the tested shared contract. Player and monster HP now share one contract;
unifying both onto the full `CharacterFoundation` remains a follow-on integration
slice (tracked on the Phase 14 map), not a liability.
