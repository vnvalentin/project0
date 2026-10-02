# M4.3 source findings and scale decision draft

Status: proposed; source findings reconciled with recorded diagnostics, full acceptance pending.
Governing issue: [#205](https://github.com/vnvalentin/project0/issues/205).
Parent: [#204](https://github.com/vnvalentin/project0/issues/204).
Milestone/group: Milestone 4 / M4.3.
Source baseline: `521601a72e792e7a54c6b12c618f10eff48cadb0` (accepted main).
Prior investigation baseline: `75655f6b62f61fc4f6e69e6aa9e317d9c0e498ae`; all cited source files
were compared as committed objects and are byte-identical at accepted main.
Records-first amendments: [initial reconciliation](https://github.com/vnvalentin/project0/issues/205#issuecomment-5957545685),
[accepted-parity/full-failure reconciliation](https://github.com/vnvalentin/project0/issues/205#issuecomment-5958590827).
Research date: 2026-10-02.

This note maps the current implementation and the decisions needed after
[M4.1](https://github.com/vnvalentin/project0/issues/1376) and
[M4.2](https://github.com/vnvalentin/project0/issues/1377). It does not select a
final architecture or claim runtime acceptance. The planning map in
[PR #1378](https://github.com/vnvalentin/project0/pull/1378) defines the workload;
its review/merge status remains separate from implementation acceptance.

## Approved supported-state scope

On 2026-10-02 the user chose to evaluate currently supported state and document
unsupported fields, without implementing new gameplay before M4 closure.
[The issue checkpoint records this correction](https://github.com/vnvalentin/project0/issues/205#issuecomment-5954712157).
Exact supported Canon blueprint/mutation and reconstructed-state parity remains
required. Persistent in-flight interactions, repair/claim flags and an occupancy
bitmask representation are explicitly unsupported unless actual source and
observations establish them. Unsupported state is a reported limitation, not a
fabricated passing observation or a new gameplay prerequisite. This correction
does not change workload, tick thresholds, boundary-crossing rate, isolation,
cleanup or the container-artifact requirement.

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
| Complete M4.1 workload, qualified source/artifact identity, all 1,000 samples, crossings, isolation controls, cleanup | Retained full high-crossing profiles at `51d39e2b308b0089ac2a6e08134fd9f3ad4699ac` failed; coalescing prevents exact per-tick P99. Explicit span10 evidence at `746e8a2e8c42d8e3db26351c8adea50c9c646401` remains pending | Preserve the maximum violations and unavailable P99; do not accept capacity or infer a sole cause/process split. |
| Complete M4.2 supported unilateral/concurrent boundary and current interaction parity, attempted Canon writes, database/sidecar hashes, cleanup; explicit unsupported-state list | Accepted at `6bda74b00aea805e6c1dce2bb72ac5431930c075`; PR #1387 merged as accepted main above and #1377 closed | Supported component parity is qualified; this is not a deployed handoff or M4.1 capacity result. Unsupported representations remain explicit limitations. |
| Same containerized artifact passes the complete profile | No artifact-bound result supplied | Source-checkout success would be supporting evidence only. |
| Independent review and integrated validation | Research amendment review and final M4.1 qualification remain pending | Neither #205 nor M4 is complete. |

## Recorded diagnostics and measurement limits

These summaries come from public issue checkpoints, not a fresh read of their
raw reports. They retain the reported source identities and do not relabel old
results as executions of this research revision or accepted main.

- [The matched worker diagnostic](https://github.com/vnvalentin/project0/issues/1376#issuecomment-5956830845)
  at `6d8adcf0e2c1843f3711ebad997bc66d8e214554` reports 60 observations
  with 32 synthetic worker tasks versus zero: maximum iteration physics times
  88.479 ms and 44.450 ms, respectively. The first had four coalesced physics
  observations. Synthetic CPU stress is not existing application demand; residual
  tails without it do not support a sole-worker cause or an architecture split.
- [The inclusive callback diagnostic](https://github.com/vnvalentin/project0/issues/1376#issuecomment-5957014254)
  at `6754b7fe339d119a2b414291c98f893e9eacd1a4` reports 60 single-tick
  observations, seven above 33.3 ms and none above 50 ms. At the 48.761 ms peak,
  inclusive position callbacks took 36.411 ms, including 18.621 ms of journey
  checkpoints. This is association and callback contribution, not sole-cause proof.
- [The frontier diagnostic](https://github.com/vnvalentin/project0/issues/1376#issuecomment-5957463251)
  at `ce26012f3cbd0eb1875d1dfa8f4764d19bff3d5d` reports 60 zero-worker
  observations, no coalescing, ten above 33.3 ms, none above 50 ms, and a
  44.115 ms maximum. At that peak, journey checkpoints took 28.232 ms nested
  inside 31.611 ms of position callbacks; frontier-stay took 0.123 ms and the
  separate server physics callback took 7.885 ms. Frontier-stay reached 9.029 ms
  on another observation but did not dominate this peak. The checkpoint span
  still combines reconstruction, hashing, persistence and scheduling. Its cost
  is not a separately established SQL query duration. Cleanup was reported
  verified; the result remains diagnostic, not the 1,000-tick or contention pass.

Do not add nested/inclusive spans into an invented total. Coalesced iteration
maxima cannot establish exact per-tick P99; the final report must qualify all
1,000 tick observations and its calculation. Zero synthetic workers cannot
qualify the worker-contention probe. Earlier failed teardown evidence remains
historical failure evidence, not a pass because a later cleanup succeeded.

Physics timing does not cover every asynchronous completion/evaluation budget.
`LocalLLMClient` awaits `process_frame` during deadline polling; generation
continuations, validation and result dispatch can therefore execute outside the
physics span. Retain process measurements and their coverage limit. The tested
request path is bounded timeout fallback, not arbitrary successful generated
candidates. Neither fast ticks nor suspension by `await` proves zero native-engine
blocking or scheduling starvation. The structural assertion for new paths and
any measured lock/wait result must name their actual observation boundary.
[Deadline continuation source](https://github.com/vnvalentin/project0/blob/521601a72e792e7a54c6b12c618f10eff48cadb0/shared/local_llm_client.gd#L151-L164)

[M4.2 final acceptance](https://github.com/vnvalentin/project0/issues/1377#issuecomment-5958365467)
and [qualified native evidence](https://github.com/vnvalentin/project0/issues/1377#issuecomment-5958474826)
bind `6bda74b00aea805e6c1dce2bb72ac5431930c075`: ten focused tests/case reports,
157/157 full-suite scripts and 1,175 tests passed with zero error markers,
qualified source/helper/test identities and independently verified owned cleanup.
Both shared-account and dedicated Canon store rejection cases observed zero
attempted Canon INSERT/UPDATE statements and equal quiescent digests; deliberate
write and missing-observation controls refused qualification as intended.
Supported unilateral, concurrent same-tick and synchronous interaction parity is
accepted. PR #1387 merged as `521601a72e792e7a54c6b12c618f10eff48cadb0` and #1377
is closed. Historical `5e7d56dafbe29b3e8f66d396cb5202894f5fabf7` remains historical.
This qualifies component parity, not deployed ownership transfer or M4.1 capacity.

## Retained full failure and next decision check

[The full high-crossing checkpoint](https://github.com/vnvalentin/project0/issues/1376#issuecomment-5958477060)
binds both failed profiles to `51d39e2b308b0089ac2a6e08134fd9f3ad4699ac`.
Its source custody, callback-stage evidence and owned cleanup were qualified;
those qualifications do not change the failed verdicts.

| Profile | Actual observations and crossing rate | Timing result |
| --- | --- | --- |
| Supported load, zero synthetic workers | 1,000 observations across ticks 260–1270; five coalesced iterations; 644 crossings / 33.731608 s = 19.091886/sec | Maximum 207.810 ms; 169 observations above 33.3 ms, 24 above 50 ms |
| Unchanged 32-worker stress | 1,000 observations across ticks 248–1266; 17 coalesced iterations; 648 crossings / 33.979531 s = 19.070304/sec | Maximum 87.600 ms; 188 observations above 33.3 ms, 44 above 50 ms |

The supported peak at tick 815 had one physics step: frontier-stay 188.753 ms
nested inside position callbacks 198.682 ms, alongside journey checkpoints
7.488 ms, superclass physics 5.826 ms and observer 1.173 ms. This refutes a
checkpoint-only explanation of the worst full-run tail. The stress completed
all 32 tasks, recorded zero explicit application waits and contained the fault
without changing healthy Canon. It still failed timing. Neither coalesced run
supplies exact 1,000-consecutive-tick P99, and neither demonstrates failure at
exactly the required minimum crossing rate. The single-step supported peak does
establish a maximum violation in this higher-crossing profile.

Confirmed root cause is **unknown**. Source shows synchronous telemetry INSERT
and retention DELETE/COUNT inside frontier reentry, a Canon-reload stdout write,
retained-trace copying and UUID preparation. Telemetry persistence, stdout
backpressure, trace work and native scheduling are falsifiable alternatives;
source inspection alone assigns none a sole causal contribution.
([frontier callback][frontier-callback], [telemetry][telemetry], [trace][trace])

The next source-bound profile is `746e8a2e8c42d8e3db26351c8adea50c9c646401`:
explicit span10 movement with unchanged ten peers/four sectors/50 entities and
production behavior, measured crossings still at least two/sec, and nested
unchanged-super telemetry timing. Default span1 stress remains available. The
new observer span is inclusive of event building, validation, SQL and scheduling;
it does not isolate SQL latency. All required spans must be present for overall
acceptance. The missing-stage acceptance defect was separately corrected at
`a9b12d2fe0a6ad022b7f73812ae99943433f4df6`; it does not retroactively turn the
fully observed older timing failures into passes. No target result is presumed.

### Final decision outline once target evidence is qualified

1. Record the actual target source/artifact identity, measured rate, 1,000
   consecutive single-step ticks, exact P99 and maximum, isolation controls,
   process/async coverage limits and owned cleanup. Coalescing, missing evidence
   or a threshold failure must remain explicit; do not infer an unavailable P99.
2. If all required target capacity, worker-isolation, parity and container gates
   pass, retain one simulation/Canon authority within that exact measured envelope.
   Preserve the higher-crossing failures as its known limit.
3. If the target maximum or other gate fails, do not accept baseline capacity.
   Use the measured nested span to choose the cheapest causal check. A telemetry
   contribution is not a Canon-write measurement, and synthetic worker stress
   alone does not require splitting player simulation. If attribution remains
   unresolved, record blocked decision evidence and the next bounded check.
4. Only a reproduced causal bottleneck or isolation failure can justify a new
   boundary. Specify its mutable-fact owner, bounded queue/deadline, failure
   recovery, candidate routing, storage compatibility and rollback before choosing
   it. The provisional-worker extension contract cannot authorize a Canon worker
   writer; that would require a separate single-writer authority design and
   acceptance. Retain the deployment/rollback route below for any proposed split.

## Source qualification after integration

The cited authority, generation, interaction, Canon, deployment and residency
source files are unchanged between the prior baseline and accepted main above.
The accepted main also adds [ADR 0016](../../docs/adr/0016-interior-anchor-and-cell-persistence.md)
and interior-anchor persistence. That increment retains unresolved runtime and
permission integration; it does not supply new M4 gameplay observations or
establish repair/claim state. Preserve those integration gates without expanding
this scale evaluation into new gameplay implementation.

Keep the research revision, inspected source baseline, diagnostic source,
benchmark/package source and engine/artifact qualification distinct. Acceptance
requires the actual final integrated benchmark and parity evidence; a historical
source equality check does not qualify an unexecuted run.

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
this implementation. Under the approved scope these are explicit unsupported
representations, not mandatory new gameplay. A supported-state report must not
replace them with empty fields and count them as passing comparisons. Current
synchronous interaction behavior can be evaluated at its public seam, without
claiming persistent in-flight interaction transfer. [Interaction source][interaction]

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
4. Samples, required supported-state observations, parity controls or container
   evidence are missing: retain the current runtime, mark the decision
   blocked/awaiting evidence, and name the missing acceptance work. Missing
   evidence alone does not justify a process split or prove the single-runtime
   baseline adequate. Explicitly unsupported gameplay state is a limitation under
   the approved scope, rather than a demand to implement it for M4.

[ADR 0017](../../docs/adr/0017-evidence-led-world-scale.md) stages this conditional
disposition with `status: proposed`. Accept it only after linking the actual M4
reports and their exact source/container identities; proposed is not accepted.

## Validation and remaining work

This is a source-bound research artifact. Document/link review and whitespace
validation apply locally; Linux ownership preflight, full GUT, record sync,
independent Standards/Spec review and final-revision evidence remain root-owned
delivery gates. No product/runtime test was run as part of this source research.
The documentation behavior check is: given a diagnostic or historical parity
checkpoint, when this decision is read, then its exact source, observation limit
and outstanding acceptance remain explicit. A missing full profile keeps the
ADR proposed; a source/command check cannot promote it to accepted.
The next actor is the M4.1 evidence owner, followed by the M4.3 reviewer.
Rollback for this artifact is reverting its documentation commit.

[runtime]: https://github.com/vnvalentin/project0/blob/521601a72e792e7a54c6b12c618f10eff48cadb0/docs/SYSTEMS-SPECIFICATION.md#deployment-and-interaction-boundary
[player]: https://github.com/vnvalentin/project0/blob/521601a72e792e7a54c6b12c618f10eff48cadb0/server/server_player_state.gd
[tick]: https://github.com/vnvalentin/project0/blob/521601a72e792e7a54c6b12c618f10eff48cadb0/server/server_main.gd#L1604-L1636
[generator]: https://github.com/vnvalentin/project0/blob/521601a72e792e7a54c6b12c618f10eff48cadb0/server/provisional_sector_generator.gd
[coordinator]: https://github.com/vnvalentin/project0/blob/521601a72e792e7a54c6b12c618f10eff48cadb0/server/canon_generation_coordinator.gd
[canon]: https://github.com/vnvalentin/project0/blob/521601a72e792e7a54c6b12c618f10eff48cadb0/server/canon_repository.gd#L21-L113
[mutations]: https://github.com/vnvalentin/project0/blob/521601a72e792e7a54c6b12c618f10eff48cadb0/server/canon_mutation_repository.gd#L58-L163
[boundary]: https://github.com/vnvalentin/project0/blob/521601a72e792e7a54c6b12c618f10eff48cadb0/server/sector_boundary_detector.gd
[frontier]: https://github.com/vnvalentin/project0/blob/521601a72e792e7a54c6b12c618f10eff48cadb0/server/server_main.gd#L1292-L1335
[stores]: https://github.com/vnvalentin/project0/blob/521601a72e792e7a54c6b12c618f10eff48cadb0/server/server_main.gd#L369-L489
[compose]: https://github.com/vnvalentin/project0/blob/521601a72e792e7a54c6b12c618f10eff48cadb0/deploy/compose.yml#L16-L144
[admission]: https://github.com/vnvalentin/project0/blob/521601a72e792e7a54c6b12c618f10eff48cadb0/server/server_main.gd#L647-L650
[health]: https://github.com/vnvalentin/project0/blob/521601a72e792e7a54c6b12c618f10eff48cadb0/server/server_health.gd#L24-L46
[service]: https://github.com/vnvalentin/project0/blob/521601a72e792e7a54c6b12c618f10eff48cadb0/server/sector_blueprint_service.gd#L93-L144
[placement]: https://github.com/vnvalentin/project0/blob/521601a72e792e7a54c6b12c618f10eff48cadb0/server/sector_detail_generation.gd
[retry]: https://github.com/vnvalentin/project0/blob/521601a72e792e7a54c6b12c618f10eff48cadb0/server/server_main.gd#L1268-L1289
[completion]: https://github.com/vnvalentin/project0/blob/521601a72e792e7a54c6b12c618f10eff48cadb0/server/server_main.gd#L1110-L1158
[workers]: https://github.com/vnvalentin/project0/blob/521601a72e792e7a54c6b12c618f10eff48cadb0/.scratch/container-platform/issues/06-worker-extension-contract.md
[sqlite]: https://github.com/vnvalentin/project0/blob/521601a72e792e7a54c6b12c618f10eff48cadb0/server/sqlite_store.gd#L116-L241
[interaction]: https://github.com/vnvalentin/project0/blob/521601a72e792e7a54c6b12c618f10eff48cadb0/server/environmental_interaction_service.gd#L31-L118
[residency]: https://github.com/vnvalentin/project0/blob/521601a72e792e7a54c6b12c618f10eff48cadb0/shared/sector_residency_reconciler.gd
[residency-test]: https://github.com/vnvalentin/project0/blob/521601a72e792e7a54c6b12c618f10eff48cadb0/tests/integration/test_sector_residency_canon_preservation.gd
[deploy-adr]: https://github.com/vnvalentin/project0/blob/521601a72e792e7a54c6b12c618f10eff48cadb0/docs/adr/0011-stable-compose-deployment-authority.md
[deploy]: https://github.com/vnvalentin/project0/blob/521601a72e792e7a54c6b12c618f10eff48cadb0/scripts/deploy_containers.sh
[migration]: https://github.com/vnvalentin/project0/blob/521601a72e792e7a54c6b12c618f10eff48cadb0/.scratch/container-platform/issues/05-migration-update-and-rollback.md

[frontier-callback]: https://github.com/vnvalentin/project0/blob/521601a72e792e7a54c6b12c618f10eff48cadb0/server/server_main.gd#L1030-L1078
[telemetry]: https://github.com/vnvalentin/project0/blob/521601a72e792e7a54c6b12c618f10eff48cadb0/server/telemetry_sink.gd#L104-L157
[trace]: https://github.com/vnvalentin/project0/blob/521601a72e792e7a54c6b12c618f10eff48cadb0/shared/jit_trace_context.gd#L28-L57
