# Slice 125 - Phase 14 integration: Player HP on the shared CombatHealth contract
GitHub issue: #227

Status: **delivered**

Phase: 14 (NPC generalization and shared Character)

Feature: [F-036](../FEATURE-LIST.md#f-036-phase-14-unified-character-and-npc-generalization)

Design source: [#231](https://github.com/vnvalentin/project0/issues/231)
(shared health/defeat/recovery), [ADR 0007](../adr/0007-unified-character-and-npc-generalization.md).
Retires the provisional `PlayerVitals` from
[Slice 094](094-player-hp-monster-damage.md); consumes
[Slice 120](120-phase14-combat-health.md)'s `CombatHealth`.

## User outcome

The player's health now runs on the same shared rule as every NPC will: the
first wiring of a Phase 14 contract into the live server. Behaviour is
unchanged for the player — the HUD, monster damage, defeat, and respawn all work
exactly as before — but the placeholder pool is gone, replaced by the tested
shared contract.

## Scope and non-goals

In scope: replacing the server-owned `PlayerVitals` flat pool in
`server/server_player_state.gd` with the shared `CombatHealth` contract, seeded
at the shared `PLAYER_MAX_HP` default; retiring the `PlayerVitals` class and its
now-redundant unit tests (its damage/reset behaviour is owned and tested by
`CombatHealth`).

Out of scope: migrating the monster's HP onto `CombatHealth` (a follow-on
slice), any change to replicated HUD values (still int HP), a health fraction
in the wire snapshot, wiring `CharacterFoundation`/other Phase 14 contracts, and
vessel-derived health (Phase 15). This is an internal, behaviour-preserving
swap, not a gameplay change.

## Public seam

`server/server_player_state.gd`: `current_hp()`, `max_hp()`,
`receive_monster_damage()`, and the `health_changed` / `player_defeated`
signals — all unchanged in shape and behaviour. The Player's pool is now a
`shared/combat_health.gd` (`CombatHealth`) instance instead of `PlayerVitals`.
`shared/player_combat_contracts.gd` now only owns the shared `PLAYER_MAX_HP`
seed constant.

## Falsifiable hypothesis

If the live Player HP pool is swapped to `CombatHealth` while preserving the
public seam, then the existing damage/defeat/respawn tests pass unchanged (no
regression), proving a Phase 14 contract can back real server state without
altering behaviour — the pattern the remaining integration slices follow.

## SDD

`server_player_state` holds `var _health: CombatHealth` seeded at
`float(PLAYER_MAX_HP)` for both max and current. `current_hp()`/`max_hp()` round
the float pool to ints for the unchanged HUD replication. `start_for_peer` and
the defeat respawn refill via `current_health = max_health`.
`receive_monster_damage` preserves the retired `PlayerVitals` defeat semantics
exactly: capture `was_alive` before `take_damage`, and report defeat only when a
still-living Player is reduced to 0 (`was_alive and is_now_defeated()`), so
exactly one `player_defeated` fires and never a second for an already-defeated
Player. `CombatHealth` floors damage at 0, so a non-positive amount is a no-op,
matching the old pool. `PlayerVitals` is deleted; `PLAYER_MAX_HP` stays as the
shared seed (still used by the client HUD default and monster-parity).

## BDD

1. Given a Player enters the world, when HP is read, then it is full at the
   shared seed.
2. Given a landed monster hit, when applied, then HP drops by the exact amount
   and `health_changed` fires with ints — unchanged.
3. Given a lethal hit, when applied, then `player_defeated` fires once and the
   Player respawns at full HP and the spawn anchor — unchanged.
4. Given an overkill hit, when applied, then defeat is reported exactly once.
5. Given the telegraph dodge, when the swing whiffs, then the Player takes no
   damage — unchanged end-to-end.

## TDD / validation

```bash
bash scripts/run_gut_validation.sh
bash scripts/check_record_sync.sh
```

**Delivered evidence (2026-09-17, Linux host `okami`):** full GUT suite green
after the migration — **72 scripts / 488 tests / 488 passing, exit 0**. The
behaviour-preserving regression net passed unchanged:
`test_server_player_state_damage.gd` **5/5** (full-HP entry, one-hit damage +
`health_changed`, pre-world-entry ignore, lethal defeat→respawn, overkill
defeat-once) and the integration `test_monster_damages_player.gd` **2/2**
(landed-attack damage and telegraph-dodge no-damage) — the latter exercising the
real `ServerMonsterManager` → `ServerPlayerState` node/signal path, i.e. runtime
evidence that live combat is unchanged. The rewritten `test_player_combat_
contracts.gd` ran **2/2** (shared seed parity + seeds-a-full-CombatHealth-pool).
`check_record_sync.sh` exit 0. GUT cannot run on Windows, so validation was
performed on the Linux host per repo convention; `combat_health.gd` (merged to
main, absent from okami's deploy tree) was staged alongside for the run and then
removed, and the three modified tracked files were restored from backup.

## Root-cause learning

- **Symptom:** the first okami run failed (`Scripts 71`, 2 failing, exit 1) with
  `Preload file "res://shared/combat_health.gd" does not exist` cascading through
  every script that preloads `server_player_state`, plus a parse error in the
  test.
- **Public seam:** the GUT validation gate on okami's deploy tree.
- **Hypothesis / discriminating check:** okami is a deployment tree, not a git
  checkout, so merged-but-undeployed shared contracts (`combat_health.gd`) are
  absent. `ls shared/combat_health.gd` confirmed it was missing.
- **Confirmed root cause (two faults):** (1) the new server preload depended on a
  contract not present on okami; (2) my `replace_string_in_file` oldString did
  not cover a trailing `test_reset_refills_to_full` (beyond my initial read
  range) that still referenced the deleted `_vitals()`, so it survived as an
  orphaned parse error.
- **Countermeasure:** stage merged dependencies alongside modified files when
  validating on the deploy tree, and read the whole target file before rewriting
  it. Both fixed; the re-run was 72/72 scripts, 488/488, exit 0.
- **Regression evidence:** the passing `test_server_player_state_damage.gd` and
  `test_monster_damages_player.gd` on the clean re-run.

## Safety invariants

- The server remains the sole authority for the Player's HP; the client only
  displays the replicated int values, never sets them.
- Damage never heals and HP stays within `[0, max]` (enforced by `CombatHealth`).
- Defeat is reported exactly once per still-living→0 transition, unchanged.
- No wire/replication shape changed, so no client update is required.

## ADR and debt

Architecture: [ADR 0007](../adr/0007-unified-character-and-npc-generalization.md).
No new technical-debt entry: this removes a provisional placeholder in favour of
the tested shared contract. The monster HP migration onto `CombatHealth` remains
a follow-on integration slice (tracked on the Phase 14 map), not a liability.
