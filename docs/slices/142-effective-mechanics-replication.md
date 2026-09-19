# Slice 142 - Phase 15 follow-on (P-016): live RPC replication of the EffectiveMechanicsSnapshot

GitHub issue: #219 (Goal: embodiment — P-016 biological progression and kinetic combat systems); snapshot contract issue 03 (#224)

Status: **delivered**

Phase: 15 (Biological progression and kinetic systems) — post-exit-gate follow-on wiring

Feature: [P-016](../FEATURE-LIST.md#p-016-biological-progression-and-kinetic-combat-systems)

Design source: [Slice 140](140-phase15-embodiment-progression-service.md) — its
"Out of scope" section explicitly defers "the live RPC replication of the
snapshot to the client (the same peer-scoped channel pattern proven for the
Character snapshot in Phase 14 — a follow-on wiring)". This slice delivers that
one deferred channel. See
[ADR 0006](../adr/0006-versioned-embodiment-mechanics-architecture.md).

## User outcome

When a Player enters the world, their client now receives — and shows on the HUD
— a live, presentation-safe readout of their character's effective mechanics
(the derived vessel graph and its friction profile), replicated from the
server-authoritative embodiment progression that Phase 15 built. The hidden
numbers stay on the server; only the derived, safe view crosses.

## Scope and non-goals

In scope: the server derives an `EffectiveMechanicsSnapshot` for the owning
Player at world entry and replicates its presentation-safe view to that peer over
the same peer-scoped channel proven for the Character snapshot in Phase 14; the
client validates the untrusted wire fail-closed, retains it, and a HUD label
renders it.

Out of scope: persistence of vessels to SQLite (the other Slice 140 deferral —
a separate follow-on), applying the derived mechanics to gameplay resolution
(movement/combat consuming the friction/kinetic factors), training/evidence
input over the wire, and re-replicating the snapshot on live progression changes
(this slice replicates once at world entry, matching the Character snapshot
channel it mirrors).

## Public seam

- `server/server_player_state.gd`: `effective_mechanics_ready(peer_id, snapshot)`
  signal emitted at world entry; `effective_mechanics_snapshot()` returning the
  presentation-safe Dictionary; a per-Player `EmbodimentProgressionService` +
  resolved default tuning create the durable vessel at `start_for_peer`.
- `server/server_main.gd`: `_on_player_state_effective_mechanics_ready` connects
  and `rpc_id(peer_id, "receive_effective_mechanics", snapshot)` (peer-scoped,
  mirroring the Character-snapshot handler).
- `client/network_client.gd`: `effective_mechanics_changed(snapshot)` signal,
  `latest_effective_mechanics` retained var, and the fail-closed
  `receive_effective_mechanics` RPC target (validates via
  `EffectiveMechanicsSnapshot.from_presentation_wire`).
- `client/effective_mechanics_label.gd`: pure static `summarize` / `dominant_axis`
  HUD helpers; `MechanicsLabel` node in `client/gameplay.tscn`.

## Security / boundary

The replicated payload is the presentation snapshot only — normalized graph axes
(each 0..1, summing to 1.0) plus subsystem-safe derived summaries (friction
profile, kinetic energy-cost factor, meridian unlock flags, active-burnout
pathways). Raw effective/base node magnitudes and the tuning tables never cross.
The client treats the wire as untrusted and validates it fail-closed
(`malformed` / `unsupported_version` / `out_of_bounds` payloads are dropped, never
stored or relayed), so a hostile server cannot inject out-of-range graph state
into the HUD.

## Validation

Command: `bash scripts/run_gut_validation.sh` on the Linux host (working-tree
overlay onto the deploy tree, since this touches `server_player_state.gd`,
`server_main.gd`, and `network_client.gd`, all with merged-but-undeployed deps).

Result: **723/723 tests passing across 99/99 scripts, 2304 asserts, exit 0**
(from 712/97 on main: +2 scripts, +11 tests). 4 pre-existing headless warnings
unrelated.

New tests:

- `tests/unit/test_effective_mechanics_replication.gd` (7 tests): world entry
  emits `effective_mechanics_ready` with the peer id + the presentation snapshot;
  the snapshot is empty before world entry; graph axes are normalized and
  balanced at the baseline (each 1/6); the derived map carries all five
  subsystem-safe summaries; the current tuning version is stamped; raw effective
  and base node numbers never appear.
- `tests/unit/test_effective_mechanics_label.gd` (5 tests): the pure HUD summary
  helper renders the placeholder for an empty snapshot, the friction profile +
  "balanced" for the equal baseline, the dominant axis when unbalanced, a profile
  placeholder when absent, and "—" for no axes.

Regression: the Phase 14 Character-snapshot channel
(`test_character_foundation_replication`) and the rest of the suite are unchanged.

## Root-cause learning

No unexpected runtime failure, defect, or validation surprise arose during this
slice. (One authoring self-check caught before validation: a HUD-helper test
initially used two equal graph axes, which the balanced-axis rule correctly
renders as "balanced" rather than naming a dominant axis; the test data was
corrected to unbalanced axes before running the suite.)

## Follow-on / debt

- Vessel persistence to SQLite remains the outstanding Slice 140 deferral.
- Applying the derived friction/kinetic factors to authoritative
  movement/combat resolution is future gameplay wiring, not part of this
  replication channel.
- Re-replication on live progression changes (training/burnout) would extend
  this channel beyond the once-at-world-entry pattern it currently mirrors.
