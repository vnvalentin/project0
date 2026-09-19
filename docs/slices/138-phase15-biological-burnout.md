# Slice 138 - Phase 15 (P-016-E): Biological Burnout
GitHub issue: #219

Status: **delivered**

Phase: 15 (Biological progression and kinetic systems)

Feature: [P-016](../FEATURE-LIST.md#p-016-biological-progression-and-kinetic-combat-systems)

Design source: [docs/SYSTEMS-SPECIFICATION.md](../SYSTEMS-SPECIFICATION.md)
("Biological Burnout"), [#219](https://github.com/vnvalentin/project0/issues/219),
[ADR 0006](../adr/0006-versioned-embodiment-mechanics-architecture.md). Subsystem
slice P-016-E.

## User outcome

Venting maximum Output through a pathway (an Overload Surge) has a real cost: the
pathway burns out for a while, and its finesse (effective Control/DEX) drops to
zero until it recovers on the server clock. The burnout is temporary — it never
erases what you earned — and it survives a disconnect because the server owns it.

## Scope and non-goals

In scope: the burnout tuning namespace on `server/embodiment_tuning.gd` and
`shared/burnout_instance.gd` — the temporary Burnout value (authoritative
start/end tick, pathway, source action, tuning version), the active/expired time
checks, the pathway-scoped effective-Control flatten, and the normative lifecycle
transition validator.

Out of scope: the server Overload-Surge acceptance path and simulation-clock
expiry driver, folding Burnout into the replicated `derived` map (server
service), disconnect/reconnect recovery wiring, and the magic subsystem
(P-016-F).

## Public seam

`shared/burnout_instance.gd` (`BurnoutInstance`): `from_accepted_surge(
burnout_id, pathway, source_action_id, start_tick, tuning) -> {outcome, detail,
burnout}`, `is_active(tick)` / `is_expired(tick)`, `control_multiplier_for(
pathway, tick)`, the static `valid_transition(from, to)`, and the `STATE_*`
constants. `server/embodiment_tuning.gd` gains `burnout()` returning the cooldown
duration.

## Falsifiable hypothesis

If Burnout is a temporary modifier keyed to authoritative ticks and a pathway,
then it flattens only the affected pathway's effective Control while active,
restores automatically at its end tick, never writes base state, and its
lifecycle rejects impossible transitions — exactly the spec's contract.

## SDD

`from_accepted_surge` validates the pathway (impact/flow/spark) and non-empty
ids, then builds a Burnout with `end_tick = start_tick + duration_ticks` (180
baseline) stamped with the current tuning version. `is_active` is
`[start, end)`; `is_expired` is `tick >= end`. `control_multiplier_for` returns
0.0 only for the matching pathway while active, else 1.0 — a pure derivation
modifier that never touches base DEX/Control/training. `valid_transition` encodes
the normative `READY → SURGE_VALIDATING → ACTIVE_SURGE → BURNED_OUT → RECOVERED →
READY` graph (with the `REJECTED` branch) and refuses any other edge. Pure and
deterministic; duration is frozen tuning.

## BDD

1. Given an accepted surge, when built, then the cooldown window is
   `[start, start + duration)` stamped with the tuning.
2. Given ticks, when checked, then Burnout is active within the window and
   expired at/after the end.
3. Given the affected pathway, when active, then its effective Control is
   flattened; other pathways and post-expiry are unaffected.
4. Given an unsupported pathway or malformed ids, then it fails closed.
5. Given the lifecycle, then the normative path is allowed and impossible
   transitions are rejected.
6. Given the tuning, then it exposes the burnout namespace.

## TDD / validation

```bash
bash scripts/run_gut_validation.sh
bash scripts/check_record_sync.sh
```

**Delivered evidence (2026-09-17, Linux host `okami`):** full GUT suite green
with the new script — **73 scripts / 500 tests / 500 passing, exit 0**. The new
`test_burnout_instance.gd` ran **7/7** (cooldown window, active/expired boundaries,
pathway-scoped flatten + restore, the fail-closed matrix, the normative lifecycle
path, impossible-transition rejection, and the burnout tuning namespace).
`check_record_sync.sh` exit 0. GUT cannot run on Windows, so validation was on the
Linux host per repo convention; the new files and the Phase 15 tuning chain were
staged and removed.

## Safety invariants

- Burnout is a temporary modifier keyed to authoritative ticks; it never writes
  base DEX/Control/training or the unmodified kinetic inputs.
- It flattens only the affected pathway while active and restores automatically at
  its end tick.
- Only the normative lifecycle transitions are allowed; the server owns every
  state entry and the expiry clock. The duration is frozen tuning.

## ADR and debt

Architecture: [ADR 0006](../adr/0006-versioned-embodiment-mechanics-architecture.md).
No new technical-debt entry. The server surge-acceptance/expiry driver,
disconnect/reconnect recovery, and folding Burnout into the replicated `derived`
map are explicit later scope, not liabilities.
