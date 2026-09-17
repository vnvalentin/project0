# Slice 117 - Phase 14 Character alignment & disposition contract
GitHub issue: #227

Status: **delivered**

Phase: 14 (NPC generalization and shared Character)

Feature: [F-036](../FEATURE-LIST.md#f-036-phase-14-unified-character-and-npc-generalization)

Design source: [#228](https://github.com/vnvalentin/project0/issues/228)
(disposition model), [ADR 0007](../adr/0007-unified-character-and-npc-generalization.md).

## User outcome

An AI Character's stance toward the player is computed from durable alignment
(morality/chaos) plus mutable relationship history, and its narrative label can
deliberately deceive — so the world reacts believably and a "pretty knight" can
hide a cruel nature until the player learns better.

## Scope and non-goals

In scope: the deterministic `shared/character_alignment.gd` contract — two
continuous axes (morality, chaos), D&D-style label derivation with a deceptive
`declared_label`, relationship-driven `disposition_toward()`, and
lawful-under-authority restraint. Server-authoritative, fail-closed.

Out of scope: the stochastic "chaotic may attack despite an authority" chance,
time-based relationship decay, faction/community models, and any UI. These are
later slices per the Phase 14 map's non-goals.

## Public seam

`shared/character_alignment.gd` (`CharacterAlignment`): `derive_label`,
`perceived_label`, `true_label`, `respects_authority`, `disposition_toward`, and
the fail-closed `from_wire_dict`.

## Falsifiable hypothesis

If disposition derives deterministically from alignment + relationship + context
with the label decoupled from the true axes, then NPC stance is reproducible and
auditable, deception is expressible, and later combat/movement slices can consume
one disposition seam without re-deriving alignment.

## SDD

Two axes drive logic; the label is a pure derivation that a `declared_label`
may override for deception. `disposition_toward` applies, in order: strong
relationship override (trust→passive, enmity→hostile), alignment-conflict gate
(opposed values + no relationship→hostile), then a Lawful Character is
restrained from acting hostile while an authority is present. Pure and
deterministic; the server owns the axes and relationship, never the client.

## BDD

1. Given axes, when the label is derived, then it maps to the D&D grid
   deterministically, and `True Neutral` is the doubly-neutral case.
2. Given a `declared_label`, when perceived, then the observer sees the declared
   label while `true_label` still reflects the real axes.
3. Given a trusted or hostile relationship, when disposition is computed, then
   relationship overrides alignment.
4. Given opposed alignment and no relationship, when disposition is computed,
   then the Character is hostile.
5. Given a Lawful hostile Character and a present authority, when disposition is
   computed, then it is restrained to passive; a Chaotic one is not.
6. Given malformed/out-of-bounds/unknown-disposition input, when parsed, then it
   fails closed with a bounded outcome.

## TDD / validation

```bash
bash scripts/run_gut_validation.sh
bash scripts/check_record_sync.sh
```

**Delivered evidence (2026-09-17, Linux host `okami`):** full GUT suite green
with the new script — **74 scripts / 514 tests / 514 passing, exit 0**. The new
`test_character_alignment.gd` ran all **12/12** of its tests (label derivation,
deception vs true label, relationship override, alignment-conflict hostility,
compatible-alignment default, lawful-vs-chaotic authority restraint, and the
fail-closed rejection matrix), confirming the script executed (not a silent
preload skip). `check_record_sync.sh` exit 0. GUT cannot run on Windows, so
validation was performed on the Linux host per repo convention.

## Safety invariants

- The server is the sole authority for a Character's axes and relationship;
  neither is client-authored.
- The perceived label may differ from the true label by design; the true axes
  are never leaked through the perceived label.
- Parsing fails closed on version/structure/bounds/enum; invalid input yields no
  Character alignment.
- `disposition_toward` is pure and deterministic — no RNG, no clock, no I/O.

## ADR and debt

Architecture: [ADR 0007](../adr/0007-unified-character-and-npc-generalization.md).
No new technical-debt entry: the deferred stochastic-attack chance and
relationship decay are recorded as explicit non-goals here and on the Phase 14
map, not as liabilities.
