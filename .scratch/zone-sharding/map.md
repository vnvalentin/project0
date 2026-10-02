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
orchestration, and Canon writes in one runtime. Its configured 10-peer limit is
a policy cap, not measured proof of a capacity ceiling. Cross-boundary ownership
and handoff contracts are unproven, and there is no measured result establishing
that one runtime is insufficient. A synchronous Canon read is reachable from
physics-driven frontier handling, but no tick overrun or lock has been measured
for it; profile it before proposing a refactor.

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
- [ ] M4.2 evaluates unilateral, concurrent multi-entity, and in-flight
  interaction crossings against the single-runtime reference and proves
  rejected requests are write-free.
- [ ] M4.3 records a reviewed decision and ADR. If one runtime passes, the
  containerized single-runtime increment passes the complete baseline. If
  evidence justifies process boundaries, the deployable architecture defines
  ownership, handoff, persistence, generation coordination, tick semantics, and
  recovery; deploying multiple authorities is not implied.
- [ ] Any process split is justified by measured capacity failure or a
  reproduced isolation failure, never by analogy alone.

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
concurrent multi-entity crossings, and in-flight uncommitted interaction
transfer against the single-runtime reference. Match the exact raw canonical
JSON blueprint and ordered committed mutation records plus reconstructed
authoritative entity state: coordinates/transforms, entity GUIDs and structure
anchor IDs, permanent state bitfields (`UNLOCKED`, `REPAIRED`, `CLAIMED`), static
collider bounds, and occupancy bitmasks.

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
