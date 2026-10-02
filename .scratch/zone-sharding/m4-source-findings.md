# M4.3 source findings and scale decision draft

Status: proposed; source investigation complete, workload/parity evidence pending.
Governing issue: [#205](https://github.com/vnvalentin/project0/issues/205).
Parent: [#204](https://github.com/vnvalentin/project0/issues/204).
Milestone/group: Milestone 4 / M4.3.
Source baseline: `75655f6b62f61fc4f6e69e6aa9e317d9c0e498ae`.
Research date: 2026-10-02.

This note maps the current implementation and the decisions needed after
[M4.1](https://github.com/vnvalentin/project0/issues/1376) and
[M4.2](https://github.com/vnvalentin/project0/issues/1377). It does not select a
final architecture or claim runtime acceptance. The planning map in
[PR #1378](https://github.com/vnvalentin/project0/pull/1378) defines the workload;
its review/merge status remains separate from implementation acceptance.

## Evidence and decision gate

The issue contract requires 10 active player connections, four adjacent active
sectors, and at least 50 dynamic entities: 10 player characters, 10 NPCs,
15 dynamic collision shapes and 15 interaction/boundary triggers. At least two
aggregate adjacent-sector crossings per second must occur over 1,000 consecutive
30 Hz server ticks. Tick P99 must be at most 33.3 ms and maximum at most 50.0 ms.
Exact boundary/persistence parity and the isolation probes are additional gates;
a fast average or a source audit cannot replace them. A no-sharding outcome also
requires a tested containerized single-runtime increment.
([#1376](https://github.com/vnvalentin/project0/issues/1376),
[#1377](https://github.com/vnvalentin/project0/issues/1377),
[#205](https://github.com/vnvalentin/project0/issues/205))

| Required evidence | Current finding | Decision consequence |
| --- | --- | --- |
| Complete M4.1 workload, native host/engine, source identity, all 1,000 samples, crossings, isolation controls, cleanup | Measurements not supplied to this draft | Capacity and isolation outcome remain unknown. |
| Complete M4.2 unilateral, concurrent and in-flight interaction parity, attempted Canon writes, database/sidecar hashes, cleanup | Measurements not supplied to this draft; current source lacks some requested state representations | Missing observations must fail closed; do not manufacture parity fields. |
| Same containerized artifact passes the complete profile | No artifact-bound result supplied | Source-checkout success would be supporting evidence only. |
| Independent review and integrated validation | Not yet run for this draft | Neither #205 nor M4 is complete. |

## Current authority per mutable fact

The design contract assigns gameplay and persistence to the Linux game server,
client presentation/input to the client, and pure schema/identity conversion to
shared code. Process boundaries do not follow file location: a shared helper
cannot become a mutable authority merely because multiple processes import it.
([runtime contract][runtime])

| Fact | Current owner and write path | What a future split must preserve |
| --- | --- | --- |
| Player position, action sequence, combat phase and temporary locomotion | One `ServerPlayerState` under the admitted server peer; movement/collision and fixed-tick action progression remain server-owned. [player source][player] | One owner at a time; transfer the accepted sequence watermark and remaining action/effect state, not client-reported outcomes. |
| NPC/monster simulation | The game server owns managers and advances them from its physics-frame callback. [tick source][tick] | No independent duplicate simulation of the same entity. |
| Sector generation acceptance and result | `ProvisionalSectorGenerator` retains one in-memory entry per sector and emits a provisional result; it does not write Canon. [generator][generator] | Deduplication and result identity must cross any new process boundary. |
| Canonical blueprint | `CanonGenerationCoordinator` validates provenance/profile then invokes the server repository; it exposes the returned Canon blueprint, not the raw model response. [coordinator][coordinator] | Only the Canon authority commits; generation workers remain untrusted proposers. |
| Immutable Canon and mutation history | `CanonRepository` stores one immutable blueprint per sector; `CanonMutationRepository` appends event-ID-keyed mutations with expected/applied revision semantics. [Canon][canon], [mutations][mutations] | One writer per fact; no competing SQLite handles promoted to independent authorities. |
| Canon lookup and frontier admission | Boundary lookup is synchronous. The server binds readiness to connection, Character, journey and presentation; an ACK is presentation evidence, not write or movement authority. [boundary][boundary], [frontier binding][frontier] | A routing/ownership change cannot silently reuse an old owner or presentation binding. |
| Account/Character records and game journey state | The documented login authority is separate. The game still opens its own accounts-schema store, uses it for Journey state, and optionally opens a separate Canon store. [store wiring][stores], [Compose][compose] | Preserve service-scoped data ownership; actual store identity must be recorded, never guessed from historical filenames. |

The configured replicated-player cap is 10. That admission policy is not a
measured throughput ceiling. Physics rate is explicitly clamped to 20–30 Hz,
with 30 Hz the default. Source comments referring to a generic 60 Hz Godot tick
must not override the actual configured server cadence.
([admission][admission], [health configuration][health])

## Generation, queueing and failure

The current generator deduplicates a repeated sector while it is pending or
ready, returning its existing correlation ID. Every distinct sector starts a
deferred coroutine with its own short-lived `SectorBlueprintService` and HTTP
request. `_sector_state` retains the result for the process lifetime. This code
has no global in-flight cap, bounded waiting queue, per-player fairness policy,
or result-retention eviction. A bound on one request's time therefore does not
bound aggregate queued work or memory. This is a source finding, not a measured
starvation or capacity failure. [Generator source][generator]

The generation service uses an absolute monotonic deadline capped at three
seconds and zero LLM retries. Deadline/transport/schema failure selects a
validated fallback or repair path; the coordinator still checks the selected
profile and provenance before Canon commit. Placement and ingress validation
occur before finalization. Presentation/preparation retries are separately
bounded in time and do not restart the accepted LLM request.
([service][service], [coordinator][coordinator], [placement][placement],
[preparation retry][retry])

Awaiting HTTP suspends the coroutine. It does not prove that synchronous schema
validation, placement work, Canon reads/writes or result dispatch take zero time,
nor does it prove lock contention or worker starvation cannot occur. M4.1 must
measure the existing path. There is no generation-worker pool in this source
that could support a claim about pool fairness or parallel GPU scheduling.
([generator][generator], [completion path][completion])

Reuse the existing [worker-extension contract][workers]; do not design a second
job framework. It already specifies a bounded request with schema version,
job ID/kind, bounded parameters, issued-at and deadline; a bounded result;
idempotency; isolated resources; observable bounded retries/timeouts; and
provisional output with no worker Canon handle or gameplay authority. These are
requirements for a future worker, not evidence that the present generator is a
distributed job service.

A future worker slice must resolve numeric concurrency, queued-job and retention
limits from measurements; choose admission/backpressure and per-requester
fairness; coalesce identical sector requests; reject expired/stale results; and
reconcile an ambiguous completion by job identity before retrying. Do not assign
new limits here without evidence. The game/Canon owner must validate schema,
sector/profile identity and applicable revision before committing. A worker
failure must not transfer authority or authorize a second writer. These are
proposed completion conditions derived from the existing worker contract.

## Persistence and parity limits

At boot, `PROJECT0_CANON_DB_PATH` selects a separate Canon store when nonempty;
otherwise Canon shares the game accounts-store handle. The tracked Compose file
sets `PROJECT0_ACCOUNTS_DB_PATH=accounts.db` and mounts distinct game/login data
roots; it does not set `PROJECT0_CANON_DB_PATH`. The resolved live host path and
runtime configuration were not inspected in this research. An isolated fixture
must state its actual path/handle and WAL sidecars.
([store wiring][stores], [Compose][compose])

`SqliteStore` enables WAL and wraps writes in transactions with rollback on
failure. Canon identity is protected by the sector primary key and immutable
replay rules. Mutation event identity is a primary key, but per-sector revision
is read before the insertion transaction and the `(sector_id, applied_revision)`
index is not unique. The current synchronous single-owner path must not be
reinterpreted as a distributed multi-writer compare-and-swap protocol.
([SQLite wrapper][sqlite], [Canon][canon], [mutation schema and apply][mutations])

M4.2 must compare raw canonical JSON and actual ordered mutation schema fields,
including authoritative tick and expected/applied revision. Physical SQLite
layout and creation timestamps are excluded only where the governing issue
allows it. Rejected-request SQL attempt counters and quiescent database/sidecar
digests answer different questions; neither substitutes for the other.
([#1377](https://github.com/vnvalentin/project0/issues/1377))

The current environmental-interaction service resolves reach, line of sight,
execution profile and the unlock mutation synchronously. It persists an
`unlocked` boolean in the mutation payload, and keeps open-gate posture in an
in-memory dictionary. It does not represent a retained uncommitted tether or
line-of-sight lock that can be transferred between runtimes. The requested
`REPAIRED`/`CLAIMED` bitfields and occupancy-bitmask parity are not established by
this implementation. Absent state is a coverage gap, not an empty value that
passes comparison. [Interaction source][interaction]

The residency reconciler computes nine desired sector coordinates and proposed
evictions without a database handle, async execution, or Canon mutation. At the
baseline, its consumers are tests, not game/client runtime wiring. Its pure
result cannot prove actual reclamation, ownership handoff, or retained entity
state across an authoritative runtime transfer.
([reconciler][residency], [integration test][residency-test])

## Handoff and tick contract draft

A same-runtime sector crossing does not transfer simulation authority. Keep the
current owner and apply Canon admission/readiness rules. No cross-process
handoff is implemented by the boundary detector or residency reconciler.
([boundary][boundary], [residency][residency], [runtime contract][runtime])

If measured capacity or isolation evidence requires a simulation split, the ADR
must define the following before implementation:

- A unique transfer identity and ownership epoch; source/destination sector and
  owner; a fence that prevents both sides accepting authoritative commands.
- A complete state inventory: Character/Vessel identity and durable revision,
  accepted input/action sequence, position/velocity, combat/action phase,
  remaining cooldown/effect durations, spatial references and committed mutation
  watermark. Currently unsupported interaction state needs its own approved
  semantics before it can be included in a handoff.
- Prepare, durable ownership commit, acknowledge and reconcile outcomes. An
  ambiguous acknowledgement cannot create a second owner. A failed transfer
  before commit remains with the source; after commit, recovery follows the
  recorded owner rather than blindly reversing effects.
- Tick translation: transfer remaining durations in an agreed simulation-time
  unit and retain the source tick/epoch for evidence. Do not copy an absolute
  process-local physics-frame count into another clock. Specify rounding,
  ordering and expired-effect behavior and test it against the reference run.
- Reconnect/replay/duplicate handling and rollback without replaying committed
  mutations or losing uncommitted actions.

These are unresolved design obligations, not an implemented protocol. The
single-writer worker seam above is the first alternative to consider when only
generation contention needs isolation; it does not require splitting player
simulation or Canon ownership.

## Deployment and rollback route

The current durable deployment authority is `/apps/project0/deploy/compose.yml`
under Compose project `project0`, not a transient CI checkout. The deployment
script validates and publishes a candidate, requires explicit mutable services,
checks health, and on failure restores the previous Compose artifact and recorded
Project0/Nakama image tags before checking rollback health. It records new tags
only after successful health checks. [ADR 0011][deploy-adr], [deploy script][deploy]

This source uses image tags, including a default mutable `main` tag. It does not
establish universal digest-pinned images or automatic rollback to a native
service. The older [platform migration decision][migration] is retained planning
context; use the later deployment ADR and actual artifact evidence for current
claims. No production Compose output, environment file, database or container
metadata was captured for this research.

For an eventual single-runtime decision: build an identifiable candidate with
its source and image digest recorded; run the complete M4 fixture in an isolated
container with owned storage/ports and retained reports; pass delivery gates;
then use the existing explicit-service deployment procedure only under its
separate runtime authority. Verify intended-runtime health and relevant player
journeys before claiming delivery. Preserve both previous Compose and image
identity and prove the scoped rollback, including storage compatibility.

For a split decision: retain the current single runtime as the recovery boundary,
prove the new worker/owner contract in isolation, and define candidate routing,
data ownership, promotion/fencing and rollback in a separately authorized slice.
Do not add a second simulation writer or a second Canon writer through a replica
count change.

## Proposed ADR disposition

No final choice yet. The evidence distinguishes these outcomes:

1. Complete load, isolation, parity and container-artifact checks pass: retain
   one simulation/Canon authority and document the measured envelope and future
   worker seam.
2. A reproduced generation/worker isolation problem exists: decide the smallest
   worker boundary that contains it while retaining single simulation and Canon
   authority; document queue and recovery contracts from the measured cause.
3. Measured simulation capacity or sector-local cascading failure requires
   separation: define ownership and handoff topology, Canon write authority,
   tick translation and rollback before separately authorized implementation.
4. Samples, required state, parity controls or container evidence are missing:
   retain the current runtime, mark the decision blocked/awaiting evidence, and
   name the missing acceptance work. Missing evidence alone does not justify a
   process split or prove the single-runtime baseline adequate.

No ADR number is allocated while this choice remains unresolved. The final
accepted decision should use the repository's `docs/adr/` convention and link
this source analysis plus the actual M4 reports at their exact revisions.

## Validation and remaining work

This is a source-bound research artifact. Document/link review and whitespace
validation apply locally; Linux ownership preflight, full GUT, record sync,
independent Standards/Spec review and final-revision evidence remain root-owned
delivery gates. No product/runtime test was run as part of this source research.
The next actor is the M4.1/M4.2 evidence owner, followed by the M4.3 reviewer.
Rollback for this artifact is reverting its documentation commit.

[runtime]: https://github.com/vnvalentin/project0/blob/75655f6b62f61fc4f6e69e6aa9e317d9c0e498ae/docs/SYSTEMS-SPECIFICATION.md#deployment-and-interaction-boundary
[player]: https://github.com/vnvalentin/project0/blob/75655f6b62f61fc4f6e69e6aa9e317d9c0e498ae/server/server_player_state.gd
[tick]: https://github.com/vnvalentin/project0/blob/75655f6b62f61fc4f6e69e6aa9e317d9c0e498ae/server/server_main.gd#L1604-L1636
[generator]: https://github.com/vnvalentin/project0/blob/75655f6b62f61fc4f6e69e6aa9e317d9c0e498ae/server/provisional_sector_generator.gd
[coordinator]: https://github.com/vnvalentin/project0/blob/75655f6b62f61fc4f6e69e6aa9e317d9c0e498ae/server/canon_generation_coordinator.gd
[canon]: https://github.com/vnvalentin/project0/blob/75655f6b62f61fc4f6e69e6aa9e317d9c0e498ae/server/canon_repository.gd#L21-L113
[mutations]: https://github.com/vnvalentin/project0/blob/75655f6b62f61fc4f6e69e6aa9e317d9c0e498ae/server/canon_mutation_repository.gd#L58-L163
[boundary]: https://github.com/vnvalentin/project0/blob/75655f6b62f61fc4f6e69e6aa9e317d9c0e498ae/server/sector_boundary_detector.gd
[frontier]: https://github.com/vnvalentin/project0/blob/75655f6b62f61fc4f6e69e6aa9e317d9c0e498ae/server/server_main.gd#L1292-L1335
[stores]: https://github.com/vnvalentin/project0/blob/75655f6b62f61fc4f6e69e6aa9e317d9c0e498ae/server/server_main.gd#L369-L489
[compose]: https://github.com/vnvalentin/project0/blob/75655f6b62f61fc4f6e69e6aa9e317d9c0e498ae/deploy/compose.yml#L16-L144
[admission]: https://github.com/vnvalentin/project0/blob/75655f6b62f61fc4f6e69e6aa9e317d9c0e498ae/server/server_main.gd#L647-L650
[health]: https://github.com/vnvalentin/project0/blob/75655f6b62f61fc4f6e69e6aa9e317d9c0e498ae/server/server_health.gd#L24-L46
[service]: https://github.com/vnvalentin/project0/blob/75655f6b62f61fc4f6e69e6aa9e317d9c0e498ae/server/sector_blueprint_service.gd#L93-L144
[placement]: https://github.com/vnvalentin/project0/blob/75655f6b62f61fc4f6e69e6aa9e317d9c0e498ae/server/sector_detail_generation.gd
[retry]: https://github.com/vnvalentin/project0/blob/75655f6b62f61fc4f6e69e6aa9e317d9c0e498ae/server/server_main.gd#L1268-L1289
[completion]: https://github.com/vnvalentin/project0/blob/75655f6b62f61fc4f6e69e6aa9e317d9c0e498ae/server/server_main.gd#L1110-L1158
[workers]: https://github.com/vnvalentin/project0/blob/75655f6b62f61fc4f6e69e6aa9e317d9c0e498ae/.scratch/container-platform/issues/06-worker-extension-contract.md
[sqlite]: https://github.com/vnvalentin/project0/blob/75655f6b62f61fc4f6e69e6aa9e317d9c0e498ae/server/sqlite_store.gd#L116-L241
[interaction]: https://github.com/vnvalentin/project0/blob/75655f6b62f61fc4f6e69e6aa9e317d9c0e498ae/server/environmental_interaction_service.gd#L31-L118
[residency]: https://github.com/vnvalentin/project0/blob/75655f6b62f61fc4f6e69e6aa9e317d9c0e498ae/shared/sector_residency_reconciler.gd
[residency-test]: https://github.com/vnvalentin/project0/blob/75655f6b62f61fc4f6e69e6aa9e317d9c0e498ae/tests/integration/test_sector_residency_canon_preservation.gd
[deploy-adr]: https://github.com/vnvalentin/project0/blob/75655f6b62f61fc4f6e69e6aa9e317d9c0e498ae/docs/adr/0011-stable-compose-deployment-authority.md
[deploy]: https://github.com/vnvalentin/project0/blob/75655f6b62f61fc4f6e69e6aa9e317d9c0e498ae/scripts/deploy_containers.sh
[migration]: https://github.com/vnvalentin/project0/blob/75655f6b62f61fc4f6e69e6aa9e317d9c0e498ae/.scratch/container-platform/issues/05-migration-update-and-rollback.md
