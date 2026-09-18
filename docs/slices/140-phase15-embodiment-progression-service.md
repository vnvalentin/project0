# Slice 140 - Phase 15 (P-016-A/G): server progression service composing vessel + subsystems (closes exit gate)
GitHub issue: #219

Status: **delivered**

Phase: 15 (Biological progression and kinetic systems)

Feature: [P-016](../FEATURE-LIST.md#p-016-biological-progression-and-kinetic-combat-systems)

Design source: [#219](https://github.com/vnvalentin/project0/issues/219),
[#224](https://github.com/vnvalentin/project0/issues/224) (delivery sequence),
[ADR 0006](../adr/0006-versioned-embodiment-mechanics-architecture.md),
[docs/SYSTEMS-SPECIFICATION.md](../SYSTEMS-SPECIFICATION.md). Completes P-016-A's
server-authoritative acceptance + derivation and **closes the Phase 15 exit
gate**.

## User outcome

The whole biological progression system now works as one: the server accepts a
Character's training, grows the vessel, and derives a single live picture that
folds in friction, kinetic flow, Meridian unlocks, active Burnout, and magic
eligibility — all server-owned, deduplicated, and reproducible — while the client
only ever sees the presentation-safe result.

## Scope and non-goals

In scope: `server/embodiment_progression_service.gd` — the server-authoritative
service that owns the vessels/Meridians/Burnouts, accepts deduplicated
training/cross-training evidence, resolves magic, and composes the vessel + all
five subsystems into one presentation-safe `EffectiveMechanicsSnapshot`, with an
end-to-end deterministic assertion.

Out of scope: the live RPC replication of the snapshot to the client (the same
peer-scoped channel pattern proven for the Character snapshot in Phase 14 —
a follow-on wiring), persistence of vessels to SQLite, and applying the derived
factors to live movement/combat/casting.

## Public seam

`server/embodiment_progression_service.gd` (`EmbodimentProgressionService`):
`create_character` / `has_character`, `accept_training(character_id, node,
evidence_id, amount, tuning)`, `record_meridian_evidence(...)`,
`begin_burnout(...)`, `resolve_magic(character_id, spell_tier, tuning)`, and
`effective_snapshot(character_id, tuning, current_tick)` returning an
`EffectiveMechanicsSnapshot` whose `derived` map carries presentation-safe
subsystem results.

## Falsifiable hypothesis

If one server service composes the vessel and all five subsystems into a single
presentation-safe snapshot, then training/cross-training evidence is deduplicated,
the snapshot deterministically reflects friction/kinetic/meridian/burnout state,
magic resolves against the live vessel, hidden numbers never cross to the client,
and unknown characters fail closed — proving the Phase 15 layer works end-to-end
under server authority.

## SDD

The service holds `_vessels`, `_meridians`, `_burnouts`, and a per-character
consumed-training-evidence set. `accept_training` deduplicates the evidence id
then applies `VesselProgressionState.train`. `record_meridian_evidence` lazily
creates and drives the pathway's `MeridianState`. `begin_burnout` tracks a
`BurnoutInstance` from an accepted surge. `resolve_magic` runs `MagicEquilibrium`
against the current vessel. `effective_snapshot` derives the base effective nodes,
folds `FrictionModifier` and `KineticFlow`, the Meridian unlock flags, and the
active-at-`current_tick` Burnout pathways into the snapshot's `derived` map —
carrying presentation-safe RESULTS (profile, factors, flags), never raw stat
magnitudes. Pure/deterministic given the same state, tuning, and tick; unknown
characters fail closed.

## BDD

1. Given a baseline Character, then the snapshot composes all subsystems
   neutrally.
2. Given accepted training, then the vessel and replicated graph shift.
3. Given a replayed training id, then it does not double-apply (dedup).
4. Given a Fragile-Agility build, then the snapshot's friction profile reflects
   it.
5. Given Meridian cross-training to threshold, then the unlock shows in the
   snapshot.
6. Given a Burnout, then its pathway is active mid-window and cleared after.
7. Given a magic attempt, then it resolves against the current vessel.
8. Given the same state/tuning/tick, then derivation is deterministic.
9. Given the snapshot, then it is presentation-safe (no raw numbers).
10. Given an unknown character, then it fails closed.

## TDD / validation

```bash
bash scripts/run_gut_validation.sh
bash scripts/check_record_sync.sh
```

**Delivered evidence (2026-09-17, Linux host `okami`):** full GUT suite green
with the new script — **73 scripts / 503 tests / 503 passing, exit 0**. The new
`test_embodiment_progression_service.gd` ran **10/10** — the end-to-end exit-gate
assertion: neutral baseline composition, training shifting the vessel/graph,
training-evidence deduplication, the Fragile-Agility friction profile surfacing,
Meridian unlock in the snapshot, Burnout active-then-cleared across its window,
magic resolving against the live vessel, derivation determinism, the
presentation-safe (no-raw-numbers) invariant, and unknown-character fail-closed.
`check_record_sync.sh` exit 0. GUT cannot run on Windows, so validation was on the
Linux host per repo convention; the new files and the full Phase 15 chain were
staged and removed.

## Safety invariants

- The server owns all embodiment state; only presentation-safe derived results
  cross to the client (hidden numeric state preserved).
- Training and cross-training evidence are deduplicated; a replay never
  double-applies.
- Derivation is deterministic given the same state, tuning, and tick.
- Unknown characters fail closed.

## ADR and debt

Architecture: [ADR 0006](../adr/0006-versioned-embodiment-mechanics-architecture.md).
No new technical-debt entry. **This slice closes the Phase 15 F/P-016 exit gate**:
the shared Character/progression seam now layers friction, kinetic, Meridian,
Burnout, and magic-equilibrium effects, composed by a server-authoritative service
into a deterministic, presentation-safe snapshot with hidden state preserved. The
live RPC replication of the snapshot (the proven Phase 14 channel pattern) and
vessel persistence are explicit follow-on wiring, not gate blockers.
