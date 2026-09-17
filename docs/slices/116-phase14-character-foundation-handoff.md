# Slice 116 - Phase 14 Character foundation handoff
GitHub issue: #227

Status: **delivered**

Phase: 14 (NPC generalization and shared Character)

Public seam implemented: `shared/character_foundation.gd`
(`CharacterFoundation`) with tests in
`tests/unit/test_character_foundation.gd`.

Feature: [F-036](../FEATURE-LIST.md#f-036-phase-14-unified-character-and-npc-generalization)

## User outcome

The player and every NPC are represented by one Character contract. The current
player remains humanoid, while NPCs can use the same vessel, development,
equipment, technique, movement, combat, and disposition state without a second
parallel entity model.

## Scope and non-goals

In scope: records-first implementation handoff for the shared Character
foundation, six-node baseline, organic-development layer, server authority,
and the read-model boundaries needed by later equipment, technique, movement,
combat, and spawn slices.

Out of scope: implementation code in this planning slice, non-humanoid player
characters, humanoid race selection, magical item evolution, injury, authored
technique invention, reincarnation, and the detailed Phase 15 subsystems.

## Public seam

The future server-owned Character/progression service and its replicated,
presentation-safe Character snapshot: hidden numeric state remains server-side;
the client receives derived graph/proficiency/known-capability state only.

## Falsifiable hypothesis

If Player and NPC consume one Character foundation with controller type as a
separate field, then later movement, combat, equipment, technique, and spawn
slices can reuse the same public state and authority seams without duplicating
player and NPC logic.

## SDD

Character owns identity, controller type, humanoid/NPC type context, baseline
vessel, organic development, equipment/knowledge, techniques, disposition, and
health-facing state. Server resolution is authoritative; clients consume a
bounded derived snapshot. Baseline and organic development remain separate so
the fixed-area vessel is not a lifetime cap.

## BDD

1. Given a player and NPC, when both are created, then both satisfy the same
   Character contract and differ only in controller/context state.
2. Given activity evidence, when development is resolved, then multiple nodes
   may change continuously without exposing numeric values to the client.
3. Given an equipment or technique update, when a snapshot is replicated, then
   the client receives only presentation-safe derived state.
4. Given an invalid client-authored outcome, when the server resolves it, then
   the outcome is rejected and authoritative Character state is unchanged.

## TDD / validation

Future implementation must add public-seam tests before code and run:

```bash
bash scripts/run_gut_validation.sh
bash scripts/check_record_sync.sh
```

Evidence must include focused Character-contract tests, full GUT telemetry,
record-sync output, and a review of hidden-state and authority invariants.

**Delivered evidence (2026-09-17, Linux host `okami`):** the full GUT suite ran
green with the new script included — **73 scripts / 502 tests / 502 passing /
1780 asserts, exit 0** (`build/validation/validation-summary.json`,
`build/validation/gut.xml`). The new `test_character_foundation.gd` block ran
all **9/9** of its tests (player/NPC one-contract parity, fixed balanced
budget, deterministic multi-node effective derivation, snapshot excludes raw
numeric stats, and fail-closed rejection of unsupported version, unsupported
controller, non-finite value, budget violation, and non-dictionary input),
confirming the script executed (not a silent preload skip). GUT cannot run on
Windows (missing sqlite/wgnetstack native libs), so validation was performed on
the Linux host per repo convention.

## Safety invariants

- The server is the sole authority for identity, development, proficiency,
  disposition, health, technique readiness, and outcomes.
- Client snapshots never expose hidden numeric stats, thresholds, or formulas.
- Player and NPC state cannot diverge through duplicated authority paths.
- Invalid or stale events are rejected atomically and do not mutate Character
  state.
- Existing player/account/world-entry behavior remains playable while this
  foundation is introduced.

## ADR and debt

Architecture: [ADR 0007](../adr/0007-unified-character-and-npc-generalization.md)
and [ADR 0006](../adr/0006-versioned-embodiment-mechanics-architecture.md).
No new technical-debt entry is required: this slice records a planned seam and
its explicit future validation obligations, rather than introducing a known
liability.