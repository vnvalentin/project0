# Slice 107 - Drive the engine at the contracted authoritative tick rate

Status: **delivered**

Phase: 10 (Authoritative runtime and action input), advancing P-014 and
resolving [DT-013](../TECHNICAL-DEBT-TRACKER.md#dt-013-advertised-tick_rate-does-not-match-the-actual-authoritative-tick-rate).

## User outcome

The authoritative simulation runs at the tick rate the server advertises. Every
tick-denominated contract — Canon mutation ordering today, and Burnout,
invulnerability windows, and cooldowns when they land — now has a rate that
matches the published `tick_rate`.

## Scope and non-goals

In scope: applying `ServerHealth.resolve_tick_rate` to
`Engine.physics_ticks_per_second` in both server processes, and deriving the
monster simulation delta from that same value.

Out of scope: the client's render/physics rate (deliberately left at Godot's
default; see Design notes), changing `MIN_TICK_RATE`/`MAX_TICK_RATE`, and any
retune of movement, combat, or monster behaviour.

## Public seam

`PROJECT0_TICK_RATE` (bounded to `[20, 30]` by `ServerHealth`) now governs the
actual engine cadence in `server/server_main.gd` and
`server/login_server_main.gd`, not just the advertised value in the health
snapshot.

## Design notes

- The rate is applied at the single point where it is resolved, and the monster
  delta is derived from the same variable, so the advertised and actual rates
  cannot diverge again.
- `project.godot` is intentionally **not** changed. It is shared by the client,
  and the client should keep rendering and predicting at its own cadence.
  Verified safe: the client uses `Engine.get_physics_frames()` only as its own
  `client_tick`, and ignores the replicated `server_tick` at every call site
  (each is bound as `_server_tick`).
- `MONSTER_TICK_DELTA` was a `const` of `1.0 / 60.0`. Applying the rate without
  changing it would have halved monster speed, so the two had to move together;
  it is now `_monster_tick_delta`, set from the resolved rate at boot.

## Safety invariants

- The rate stays bounded by `ServerHealth`'s existing `[20, 30]` clamp; an
  out-of-contract value cannot be configured.
- The health snapshot reports the value that drives the engine, from one source.
- No gameplay constant other than the monster delta depends on the tick rate
  (verified by search), so nothing else silently rescales.

## Acceptance scenarios

1. Given the default configuration, when the server runs, then observed ticks
   per second equal the advertised `tick_rate`.
2. Given `PROJECT0_TICK_RATE` outside `[20, 30]`, then it is clamped and the
   engine runs at the clamped value.
3. Given the rate changes, then monster movement speed per second is unchanged
   because the delta derives from the rate.

## Validation

Focused validation: runtime measurement of tick advance against advertised
rate on okami, plus the full GUT suite.

## Validation evidence

- Runtime measurement on okami after the change: `server_tick = 1170`,
  `uptime_seconds = 38.733` → **30.21 ticks/s** against an advertised
  `tick_rate: 30` (**match**).
- Before the change, the same measurement on the deployed container gave
  **60.0 ticks/s** against an advertised `30`, twice (`11100 / 184.9s` and
  `320040 / 5333.9s`).
- `scripts/run_gut_validation.sh` on okami: **72 scripts, 493 tests, 493
  passing, 1750 asserts**, identical script/test counts to the pre-change
  baseline, so no test silently stopped running.

## Root-cause learning

- Symptom: the health contract advertised `tick_rate: 30` while `server_tick`
  advanced at exactly 60/s.
- Public seam: `ServerHealth.resolve_tick_rate` and the health snapshot.
- Hypothesis: the reported value was wrong.
- Discriminating check: `grep` for `physics_ticks_per_second` (never set
  anywhere) and for a `[physics]` section in `project.godot` (absent).
- Confirmed root cause: the reported value was *correct*; the engine was not
  driven by it. `server/server_health.gd` states outright that it "does NOT set
  the engine tick — those are later container/operator slices." Slice 055
  delivered the contract and deferred its application, and that follow-up was
  never done, so the server ran at Godot's 60 Hz default for its entire life.
  `MONSTER_TICK_DELTA = 1.0 / 60.0` had been written to match the accident,
  which made the simulation internally consistent and hid the divergence.
- Why existing tests missed it: `ServerHealth` is a pure contract seam whose
  tests assert resolution and snapshot validity. Nothing asserted that observed
  tick advance equals the advertised rate, because that requires runtime
  measurement rather than a unit test.
- Countermeasure: apply the resolved rate to the engine at the point of
  resolution and derive the monster delta from the same value.
- Regression evidence: measured 30.21 ticks/s against advertised 30 (above).
- Remaining limitation: the guard is a one-off runtime measurement, not an
  automated assertion. A test that samples tick advance over a bounded window
  and compares it to the advertised rate would close this permanently; it needs
  a running server, so it belongs in `tests/integration/`.

## Record links

- Feature: [P-014](../FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)
- Resolves: [DT-013](../TECHNICAL-DEBT-TRACKER.md#dt-013-advertised-tick_rate-does-not-match-the-actual-authoritative-tick-rate)
- Prior slice: [055 — server fixed tick and health contract](055-server-fixed-tick-and-health-contract.md)
- Phase tracker: [PROJECT-TRACKER.md](../PROJECT-TRACKER.md#phase-10--authoritative-runtime-and-action-input)
- Registry: [SLICE-REGISTRY.md](SLICE-REGISTRY.md), reservation 107
