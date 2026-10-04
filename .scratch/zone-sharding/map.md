# Goal H Map: Scale and Bounded Simulation Expansion

Status: research-first
Parent vision: [#495](https://github.com/vnvalentin/project0/issues/495)
Research goal: [#204](https://github.com/vnvalentin/project0/issues/204)
Seed issue: [#205](https://github.com/vnvalentin/project0/issues/205)

## Destination

M4 is an evidence-led evaluation of whether the world needs more than one
authoritative simulation runtime. Define ownership, Canon writes, generation
coordination, and Player handoff only to the extent justified by measured
capacity or isolation needs. A passing single-runtime result is valid; this map
does not presume or authorize a multi-authority deployment.

## Capability Statement

The system can safely operate the agreed dynamic spatial workload and preserve
ownership, persistence, and player-visible world state across adjacent sector
boundaries, on one runtime or a justified deployable scale path.

## Current Condition

The game server currently owns simulation, sector-boundary handling, generation
orchestration, and Canon writes in one runtime. The latest captured M4.1 baseline
at source `33a2752d65652043d0ea57ac08353d3404cd7b0b` failed the timing target: the
known maximum tick was 66.875 ms and the conservative P99 lower bound was 59.557
ms. Exact P99 remains unavailable because one observation coalesced two physics
steps. Five journey-checkpoint calls at the peak occupied 49.292 ms in total:
Canon read 7.113 ms, journey save 19.552 ms, and 22.627 ms inclusive remainder.

The authorized, bounded countermeasure in [#1411](https://github.com/vnvalentin/project0/issues/1411)
targets repeated Canon-derived checkpoint work while preserving synchronous
durability. Its causal hypothesis and the post-countermeasure full-workload result
remain unresolved; do not attribute the full overrun to the Canon read or infer
that a process split is required. Cross-process ownership and handoff remain
unproven. No complete post-countermeasure, 1,000-tick result is recorded yet.

## Measurable Outcome

- **What:** Repeatably evaluate the single-runtime workload, boundary-state
  parity, rejected writes, and capacity/isolation triggers; record a reviewed
  scale decision and deployable architecture.
- **How much:** 10 active peers; at least 4 adjacent active sectors; at least
  50 dynamic entities (10 player characters, at least 10 active NPCs, at least
  15 dynamic collision shapes, and at least 15 interaction/boundary triggers);
  at least 2 aggregate boundary crossings per second over 1,000 consecutive
  server ticks at 30 Hz. P99 tick duration <=33.3 ms and maximum <=50.0 ms.
  All agreed parity cases match exactly, and rejected/unvalidated requests cause
  zero Canon INSERT/UPDATE writes.
- **Who:** The authoritative game server, connected players and dynamic spatial
  entities, and the server-owned Canon state they affect.
- **By when:** No fixed date. Complete the evidence-led decision, reviewed
  map/ADR, and tested containerized single-runtime increment before M4
  acceptance. Do not deploy multiple authorities by default.

## Player Example

Ten players explore adjacent sectors and interact with dynamic world entities.
As they cross sector boundaries, committed changes remain present, no other
sector silently acquires authority, and unrelated sessions continue without a
freeze. After re-entry, players see the same committed world state. If one
runtime meets the measured workload, they continue on that runtime; if evidence
justifies a process boundary, the scale architecture preserves the same
experience.

## What Good Looks Like

- [ ] M4.1 records a complete, repeatable workload baseline and classifies
  capacity and isolation findings, including timing for the existing Canon-read
  path.
- [ ] M4.2 evaluates unilateral, concurrent multi-entity, and supported
  synchronous interaction boundary cases against the single-runtime reference,
  proves rejected requests are write-free, and explicitly lists unsupported
  gameplay fields without inventing values.
- [ ] M4.3 records a reviewed decision and ADR. If one runtime passes, the
  containerized single-runtime increment passes the complete baseline. If
  evidence justifies process boundaries, the deployable architecture defines
  ownership, handoff, persistence, generation coordination, tick semantics, and
  recovery; deploying multiple authorities is not implied.
- [ ] Any process split is justified by measured capacity failure or a
  reproduced isolation failure, never by analogy alone.

## Provisional TBP Feature Breakdown

These are planning candidates, not GitHub Feature issues, Ready work, or delivery
commitments. The Feature boundaries map to this Goal's own What Good Looks Like
items; M4 slice groups and their included issues remain the delivery map.

### Feature candidate: Single-runtime capacity and isolation envelope

- **Advances:** What Good Looks Like item 1; M4.1.
- **Ideal condition:** A repeatable Linux-server run records all 1,000 actual
  ticks for 10 peers, at least four adjacent sectors, at least 50 dynamic
  entities, and at least two aggregate boundary crossings per second. P99 is at
  most 33.3 ms, maximum at most 50.0 ms, and all specified isolation probes have
  attributable outcomes.
- **Current condition:** The latest qualified baseline exceeds the tick limits;
  exact P99 is unavailable. Checkpoint work is measured, but the avoidable cost
  and any isolation failure are not yet causally established. #1411 is the
  existing bounded latency investigation; do not duplicate it.
- **Measurable component:** Complete samples and isolation evidence meet the
  M4.1 criteria, or preserve a qualified failure that identifies which criterion
  failed. Missing or coalesced samples cannot pass.
- **4W partition:** Who: the authoritative Linux game server and connected
  players. When: sustained load and sector-boundary checkpoints. Where: the
  server physics loop, checkpoint/Canon path, and adjacent-sector isolation
  boundaries. What: tick-budget performance, sample integrity, and containment
  behavior.
- **Root-cause ordering:** First establish complete per-tick observations and
  exact source identity; then finish the existing #1411 public-seam hypothesis
  check without weakening durability; finally rerun the unchanged M4.1 workload
  and classify isolation probes. Create further Epic seams only where a probe or
  measurement demonstrates a distinct problem.

### Feature candidate: Evidence-based scale decision and ready-to-scale architecture

- **Advances:** What Good Looks Like item 3; M4.3.
- **Ideal condition:** M4.1 and M4.2 evidence support a reviewed decision to
  retain one runtime or, only when a measured capacity/isolation trigger requires
  it, a deployable architecture with explicit ownership, Canon authority,
  generation coordination, handoff, tick, recovery, and rollback contracts.
- **Current condition:** M4.2 parity is accepted in #1377. M4.1 has a qualified
  failed timing result and an authorized countermeasure, but no complete
  post-countermeasure baseline. Cross-process handoff is unproven; #205's
  architecture decision therefore remains evidence-dependent.
- **Measurable component:** The reviewed map/ADR cites the final M4.1/M4.2
  evidence and selects a justified path. A single-runtime decision includes a
  containerized package passing the full agreed workload; a split decision
  defines the required ownership and recovery architecture. This does not
  authorize deploying multiple authorities.
- **4W partition:** Who: the project owner/operator and authoritative runtime
  owners. When: after the M4.1 baseline and M4.2 parity evidence. Where: across
  simulation, Canon, JIT generation, and any proposed runtime boundary. What:
  choose and substantiate the smallest safe operating topology.
- **Root-cause ordering:** M4.1's complete result and M4.2's accepted supported
  parity precede the #205 decision. Single-runtime packaging or cross-process
  ownership/handoff Epics are conditional branches; do not create both as
  committed work before the evidence selects a path.

## M4 Evaluation Contract

### Baseline Workload

- 10 active player connections.
- At least four adjacent active sectors.
- At least 50 dynamic entities total: 10 player characters, at least 10 active
  NPCs, at least 15 active dynamic collision shapes, and at least 15 active
  interaction/boundary triggers.
- At least two adjacent-sector boundary crossings per second in aggregate across
  the server.
- 1,000 consecutive server ticks at the configured 30 Hz rate. Record the
  actual rate and elapsed wall time.
- P99 tick duration <=33.3 ms and absolute maximum <=50.0 ms across all 1,000
  samples. Missing samples do not pass.

### Isolation Criteria

A measured occurrence requires M4.3 to define the needed process boundary and
containment strategy; it does not itself authorize implementation or
deployment:

1. State or mutation leakage across sector boundaries outside the authoritative
   Canon transaction/handoff protocol.
2. A sector-local processing failure corrupts or stops unrelated sectors or
   non-dependent player sessions.
3. Background work or handoff coordination causes a blocking main-thread lock,
   simulation-thread disk/network I/O, or worker starvation affecting the server
   loop.

The zero-blocking structural assertion applies to new background-worker,
handoff, and cross-runtime paths. Instrument the existing synchronous
physics-driven Canon read path during baseline profiling; refactor it only if
measured latency or lock evidence violates acceptance. A sub-millisecond WAL
read assumption is not evidence.

### Boundary and Canon Evidence

Evaluate unilateral character crossing with active spatial references,
concurrent multi-entity crossings, and supported synchronous spatial interaction
at an adjacent-sector boundary against the single-runtime reference. Match the
exact raw canonical JSON blueprint and ordered committed mutation records plus
supported reconstructed authoritative entity state: coordinates/transforms,
entity GUIDs and structure anchor IDs, unlocked state, destroyed-structure
removal, static collision footprints/bounds, and deterministic occupancy encoding
from the authoritative blocked-cell query.

The user clarified on 2026-10-02 that this is an evaluation of supported runtime
state. Repair/claim flags, retained in-flight tether or line-of-sight-lock transfer,
and absent native persisted occupancy bitmasks must be explicitly reported as
unsupported in the results and ADR. Do not infer false values or build fixture-only
gameplay to satisfy them. These missing gameplay capabilities do not block M4
closure; missing evidence for supported behavior still fails closed. The workload,
timing, isolation, zero-write, cleanup, and container-package gates are unchanged.

The current physical Canon tables are `canon_sectors` and `canon_mutations`.
Compare actual schema fields and ordered revision data; do not use the former
`sector_mutations` name or assume absent column names. Mutation parity includes
`event_id`, `sector_id`, `target_guid`, `mutation_kind`, `payload_json`,
`actor_player_id`, `server_tick`, `expected_revision`, `applied_revision`, and
`schema_version` in applied-revision order. Exclude only run-specific wall-clock
creation timestamps from cross-run parity; preserve authoritative tick and
revision semantics.

Parity excludes physical SQLite file layout, process/thread IDs, pointers,
run-specific wall-clock timestamps, and transient client presentation state.
The active database is selected by `PROJECT0_CANON_DB_PATH`; when unset, Canon
shares the accounts-store handle. Rejected/unvalidated requests must issue zero
INSERT/UPDATE statements, confirmed with attempted-write counters and an
isolated, quiescent pre/post database SHA-256 check. Record WAL/journal mode and
sidecars; the digest supplements SQL counters, not replaces them.

### Evidence and Decision

M4.1 owns the repeatable load/isolation baseline; M4.2 owns boundary-state and
rejected-write parity; M4.3 owns the final decision, map/ADR, deployment
procedure, and rollback. Retain actual host/revision/engine/commands, complete
telemetry, and cleanup results. Missing observations, crashes, incomplete
samples, or cleanup failures are not passes.

If the single runtime passes, retain one authority and prove the containerized
package against this baseline. If capacity or isolation evidence fails, the ADR
must define topology, per-fact ownership, Canon write authority, generation
coordination, handoff fields/idempotency/failure recovery, cross-process tick
semantics, deployment, and rollback. Multi-authority deployment remains outside
the automatic acceptance path.

## M4 Slice Groups

- **M4.1 Single-Runtime Load and Isolation Baseline:** [#1376](https://github.com/vnvalentin/project0/issues/1376)
- **M4.2 Boundary State and Persistence Parity:** [#1377](https://github.com/vnvalentin/project0/issues/1377)
- **M4.3 Scale Decision and Ready-to-Scale Architecture:** parent Goal [#204](https://github.com/vnvalentin/project0/issues/204) and existing research issue [#205](https://github.com/vnvalentin/project0/issues/205)

## Existing questions

The seed research issue identifies generation ownership, the single scarce
inference resource, single-writer Canon constraints, atomic Player handoff, and
cross-process tick translation as unresolved.

## Non-goals

- No sharding implementation yet.
- No multi-authority deployment by default or process split based on analogy
  alone.
- No storage migration or multi-writer Canon decision without evidence and a
  separate ADR.
- No refactor of the existing synchronous Canon read path unless baseline
  evidence shows tick overruns or main-thread blocking.
