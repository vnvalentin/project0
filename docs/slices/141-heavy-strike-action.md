# Slice 141 - Phase 12 (IP-015): second authoritative action kind — Heavy Strike
GitHub issue: (none — IP-015 melee-combat continuation; create if formalized)

Status: **delivered**

Phase: 12 (Authoritative runtime and action input)

Feature: [IP-015](../FEATURE-LIST.md#ip-015-authoritative-action-input)

Design source: [melee-combat map](../../.scratch/melee-combat/map.md),
[issue 03 — model melee weapon archetypes](../../.scratch/melee-combat/issues/03-model-melee-weapon-archetypes.md)
(archetypes are data-driven; "future archetypes extend by adding another
instance"). Advances the Phase 12 exit gate's "server resolves a bounded action
set authoritatively beyond the first melee seam".

## User outcome

The server now resolves more than one attack: alongside the quick sword strike,
a Player can throw a **Heavy Strike** — a slower, more telegraphed swing that
reaches further, sweeps a wider arc, and can catch several foes. It is fully
server-authoritative: the client requests it, the server decides windup, reach,
arc, and hits.

## Scope and non-goals

In scope: a second authoritative action kind (`HEAVY_STRIKE`) with its own
data-driven archetype, routed through the existing action state machine and
reach/arc hit test, and the server accepting/resolving both kinds.

Out of scope: client input binding for the heavy strike (a second key + its
prediction — a follow-up; the wire already carries `action_kind`), damage tuning
differences between the kinds, stamina/combos/blocking (melee-map non-goals), and
coupling the archetype to the Phase 15 embodiment layer (separate wiring).

## Public seam

`shared/combat_contracts.gd`: `ACTION_KIND_HEAVY_STRIKE`,
`SUPPORTED_ACTION_KINDS`, `heavy_strike_archetype()`,
`is_supported_action_kind(action_kind)`, `archetype_for_action(action_kind)`.
`server/server_player_state.gd`: `apply_action_intent` accepts any supported
action kind and selects the accepted kind's archetype for the swing.

## Falsifiable hypothesis

If a second action kind reuses the whole action machine and only supplies a
different archetype, then the server resolves both kinds authoritatively (the
heavy strike uses its own timing/reach/arc), the melee behaviour is unchanged,
and an unsupported kind is still rejected — proving the action-resolution seam
generalizes beyond one kind.

## SDD

`combat_contracts` adds the `HEAVY_STRIKE` kind and a `HEAVY_GREATSWORD`
archetype (windup 12 ≥ the sword's 6 for a readable telegraph, active 4, recovery
16, reach 3.0 yd, arc 120°, heavier locomotion factors 0.3/0.6, max 3 targets),
plus `is_supported_action_kind` and `archetype_for_action`. In
`apply_action_intent`, the previous `!= ACTION_KIND_MELEE_STRIKE` rejection
becomes `not is_supported_action_kind(...)`, and on acceptance the state sets
`_archetype = archetype_for_action(intent.action_kind)` so the WINDUP ticks,
locomotion throttle, and reach/arc test all read the accepted kind's archetype.
Melee routes to the unchanged Generic Sword. Provisional archetype constants,
shaped like the sword's.

## BDD

1. Given both kinds, when checked, then both are supported and a bogus kind is
   not.
2. Given an action kind, when routed, then it maps to the correct archetype
   (unsupported → null).
3. Given the heavy archetype, then it is slower, wider, longer-reaching, and
   multi-target versus the sword.
4. Given a target just past sword reach, then a heavy swing reaches it and the
   sword does not.
5. Given a flanking target inside the heavy arc, then the heavy sweep catches it
   and the narrow sword arc does not.
6. Given a heavy intent from IDLE, then it is accepted and enters WINDUP with the
   heavy timing (and the telegraph broadcasts heavy timing).
7. Given an unsupported action kind, then it is still rejected `REJECTED_INVALID_STATE`.

## TDD / validation

```bash
bash scripts/run_gut_validation.sh
bash scripts/check_record_sync.sh
```

**Delivered evidence (2026-09-18, Linux host `okami`, consistent temp tree):**
the full cumulative tree (main through Slice 140 + this slice) ran green —
**97 scripts / 712 tests / 712 passing, exit 0**, no failing blocks. New
`test_heavy_strike_action.gd` ran **7/7** (both kinds supported, archetype
routing, heavy-is-slower/wider/longer, heavy-reaches-where-sword-misses,
wide-arc-flank, server accepts heavy into WINDUP with heavy timing + telegraph,
and unsupported-kind still rejected). The melee regression net was unchanged:
`test_melee_combat_contracts.gd` **21/21** and the integration
`test_authoritative_melee_strike.gd` **9/9** (incl. monster damage). GUT cannot
run on Windows; validation used the temp-tree overlay (deploy tree copied +
main+slice source overlaid) per the recorded okami-validation practice.
`check_record_sync.sh` exit 0.

## Safety invariants

- The server remains the sole authority for action resolution; the client only
  requests a kind and the server decides windup/reach/arc/hits.
- An unsupported action kind is still rejected fail-closed.
- The melee strike's behaviour, timing, and reach/arc truth are unchanged.

## ADR and debt

No ADR: this implements the accepted data-driven-archetype extension (melee issue
03) — a second archetype instance + kind routing, no new architecture. No new
technical-debt entry. Client input binding for the heavy strike and any damage
differentiation are explicit follow-on scope, not liabilities.
