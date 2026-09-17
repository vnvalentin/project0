# Slice 122 - Phase 14 status-effect (resistible / removable) contract
GitHub issue: #227

Status: **delivered**

Phase: 14 (NPC generalization and shared Character)

Feature: [F-036](../FEATURE-LIST.md#f-036-phase-14-unified-character-and-npc-generalization)

Design source: [#231](https://github.com/vnvalentin/project0/issues/231)
(combat/status), [ADR 0007](../adr/0007-unified-character-and-npc-generalization.md).

## User outcome

Deliberate magical spells and impairments (a poison-like slow, a weakening
hex) can be applied to players and NPCs alike — a well-defended target resists
them, and any of them can be cleansed or simply worn off. Ordinary damage never
produces one: a hit hurts, it does not inflict a lingering condition.

## Scope and non-goals

In scope: `shared/status_effect.gd` — the value contract for a deliberate
status effect: its category (magical vs impairment), potency (how hard to
resist), magnitude (effect strength), and duration, plus the deterministic
resistance gate (resistible) and the cleanse/expire lifecycle (removable).

Out of scope: how magnitude changes a stat/technique (the combat/stat layer
consumes it), which sources emit effects (spells, traps, items), stacking rules
for multiple simultaneous effects, RNG-based resistance, and any UI. Ordinary
damage causing an effect is explicitly excluded — no injury system (#231).

## Public seam

`shared/status_effect.gd` (`StatusEffect`): the static `is_resisted(potency,
resistance)`, the instance `lands_against(resistance)`, the lifecycle
`advance(ticks)` / `remove()` / `is_active()` / `is_expired()`, and the
fail-closed `from_wire_dict`.

## Falsifiable hypothesis

If a status effect is a pure value with a deterministic resistance gate and an
explicit cleanse/expire lifecycle, then the same effect resolves identically for
a player or an NPC, resistance always negates a weak-enough effect
reproducibly, and every applied effect is guaranteed removable — so no effect
can become permanent by construction.

## SDD

`is_resisted(potency, resistance)` clamps both to `[0,1]` and resists when
`resistance >= potency` — a deterministic gate, no RNG. `lands_against` is its
instance complement. On construction `remaining_ticks = duration_ticks`;
`advance(ticks)` floors remaining at zero and reports expiry; `remove()` sets
remaining to zero immediately (cleanse). `from_wire_dict` fails closed on
version, structure, category enum, potency/magnitude bounds, and a positive
whole-number duration.

## BDD

1. Given a resistance at or above an effect's potency, when applied, then it is
   resisted; below potency it lands.
2. Given out-of-range potency/resistance, when compared, then clamping keeps the
   gate consistent.
3. Given an active effect, when advanced past its duration, then it expires and
   remaining floors at zero; non-positive ticks are ignored.
4. Given an active effect, when removed, then it is immediately inactive
   (removable).
5. Given a valid magical or impairment effect, when parsed, then it is accepted.
6. Given a malformed/unknown-category/out-of-bounds request, when parsed, then
   it fails closed.

## TDD / validation

```bash
bash scripts/run_gut_validation.sh
bash scripts/check_record_sync.sh
```

**Delivered evidence (2026-09-17, Linux host `okami`):** full GUT suite green
with the new script — **73 scripts / 506 tests / 506 passing, exit 0**. The new
`test_status_effect.gd` ran all **13/13** of its tests (the resistance gate and
its clamping, `lands_against`, the advance/expire and cleanse lifecycle, and the
fail-closed accept/reject matrix for both categories), confirming the script
executed (not a silent preload skip). `check_record_sync.sh` exit 0. GUT cannot
run on Windows, so validation was performed on the Linux host per repo
convention. (This standalone contract has no Phase 14 dependencies, so the suite
total reflects the baseline plus this one script.)

## Safety invariants

- The server owns application and removal; resistance and lifecycle are
  server-evaluated, never client-authored.
- Resistance and potency are clamped, so out-of-range state cannot invert the
  gate.
- Every effect is removable and bounded in duration — none can become permanent.
- Parsing fails closed on version/structure/category/bounds; invalid input
  yields no effect.
- No effect is produced by ordinary damage; there is no injury system.

## ADR and debt

Architecture: [ADR 0007](../adr/0007-unified-character-and-npc-generalization.md).
No new technical-debt entry: deferred effect sources, stacking rules, and
magnitude application are explicit non-goals here and on the Phase 14 map, not
liabilities.
