# Slice 118 - Phase 14 item & equipment effectiveness contract
GitHub issue: #227

Status: **delivered**

Phase: 14 (NPC generalization and shared Character)

Feature: [F-036](../FEATURE-LIST.md#f-036-phase-14-unified-character-and-npc-generalization)

Design source: [#233](https://github.com/vnvalentin/project0/issues/233)
(equipment model), [ADR 0007](../adr/0007-unified-character-and-npc-generalization.md).

## User outcome

An item's power depends on how well a Character knows it: an unfamiliar giant
sword hits at half strength, competence reaches full strength, and mastery
exceeds it — with class knowledge removing the unfamiliarity penalty and raising
the mastery ceiling. Items reshape capability without replacing development.

## Scope and non-goals

In scope: the deterministic `shared/item_contract.gd` contract — item metadata
(slot, category, binding, base effect), the item/item-class proficiency
effectiveness curve, the mastery proc, and tradeability. Server-authoritative,
fail-closed.

Out of scope: per-Character equip/inventory state and swap flow, technique
grants from items, magical item evolution, stat-graph reshaping wiring, and any
UI — later slices per the Phase 14 map's non-goals. Proficiency values
themselves are per-Character-per-item state owned by a later slice; this
contract only derives outcomes from them.

## Public seam

`shared/item_contract.gd` (`ItemContract`): `effectiveness_multiplier`,
`effective_value`, `has_proc`, `proc_multiplier`, `is_tradeable`, and the
fail-closed `from_wire_dict`; plus the `SLOTS`, category, and binding vocabularies.

## Falsifiable hypothesis

If item effectiveness is a pure function of two 0..1 proficiencies matching the
canonical curve, then equipment power is reproducible and tunable, and later
equip/technique slices can consume one effectiveness seam without re-deriving it.

## SDD

`effectiveness_multiplier(item, class) = 0.5 + 0.5*class + item` (inputs clamped
to 0..1). At class 0 that is the giant-sword curve (0%→0.5, 50%→1.0, 100%→1.5);
at class 1 the floor rises to 1.0 (no unfamiliarity penalty) and mastery reaches
2.0. The direct-effect proc unlocks at full item proficiency and is improved by
class mastery. Binding governs tradeability (only quest/player-locked bind).
Pure and deterministic; the server owns proficiency, never the client.

## BDD

1. Given item/class proficiencies, when the multiplier is computed, then it
   matches the giant-sword curve and the class floor/ceiling shifts.
2. Given a base effect, when effective value is computed, then it is the base
   scaled by the multiplier.
3. Given out-of-range proficiency, when computed, then inputs clamp to 0..1.
4. Given full item proficiency, when the proc is checked, then it unlocks and
   improves with class mastery.
5. Given a binding, when tradeability is checked, then only `none` is tradeable.
6. Given malformed/out-of-bounds/unknown-enum input, when parsed, then it fails
   closed with a bounded outcome.

## TDD / validation

```bash
bash scripts/run_gut_validation.sh
bash scripts/check_record_sync.sh
```

**Delivered evidence (2026-09-17, Linux host `okami`):** full GUT suite green
with the new script — **75 scripts / 526 tests / 526 passing, exit 0**. The new
`test_item_contract.gd` ran all **12/12** of its tests (the giant-sword curve,
effective value, proficiency clamping, proc unlock/improvement, binding
tradeability, mundane/magical parse, and the fail-closed rejection matrix),
confirming the script executed (not a silent preload skip). `check_record_sync.sh`
exit 0. GUT cannot run on Windows, so validation was performed on the Linux host
per repo convention.

## Safety invariants

- The server is the sole authority for proficiency; effectiveness is derived,
  never client-authored.
- Effectiveness inputs clamp to 0..1 so no state produces an absurd multiplier.
- Parsing fails closed on version/structure/enum/bounds; invalid input yields no
  item.
- All effectiveness/proc helpers are pure and deterministic — no RNG, clock, IO.

## ADR and debt

Architecture: [ADR 0007](../adr/0007-unified-character-and-npc-generalization.md).
No new technical-debt entry: deferred equip/inventory state, technique grants,
and magical item evolution are explicit non-goals here and on the Phase 14 map,
not liabilities.
