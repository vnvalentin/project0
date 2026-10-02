---
status: proposed
---

# Evidence-led world scale with one authority per fact

Milestone 4 evaluates whether the current single authoritative game runtime
meets the agreed workload and isolation envelope. The proposed decision is to
retain one simulation and Canon-writing authority when the complete measured
baseline passes, and introduce a process boundary only for a reproduced capacity
or isolation problem. The tested single runtime failed M4.1 capacity at the
target crossing rate.
This ADR remains **proposed**: the candidate off-tick checkpoint boundary needs
feasibility, independent review and project architecture acceptance. Supported
M4.2 component parity is accepted separately; it does not establish capacity.

Governing issue: [#205](https://github.com/vnvalentin/project0/issues/205).
Parent: [#204](https://github.com/vnvalentin/project0/issues/204).
Source analysis: [M4.3 findings](../../.scratch/zone-sharding/m4-source-findings.md),
reconciled at accepted main `424a71092d8f4b91fecdcf962aa19faa5a4c9510`.
The [initial checkpoint](https://github.com/vnvalentin/project0/issues/205#issuecomment-5957545685),
[evidence amendment](https://github.com/vnvalentin/project0/issues/205#issuecomment-5958590827)
[target proposal](https://github.com/vnvalentin/project0/issues/205#issuecomment-5958697673),
[accepted-map diagnostic frontier](https://github.com/vnvalentin/project0/issues/205#issuecomment-5958888901),
and [accepted baseline integration](https://github.com/vnvalentin/project0/issues/205#issuecomment-5959023851)
own this documentation work. The planning map is accepted in PR #1378; its
merge does not qualify capacity or this proposed architecture.

## Evidence required to accept

[M4.1](https://github.com/vnvalentin/project0/issues/1376) must record the actual
10 connected players, four adjacent active sectors, and 50 dynamic entities:
10 player characters, at least 10 active NPCs, 15 dynamic collision shapes and
15 interaction/boundary triggers. At least two aggregate adjacent-sector
crossings per second occur over 1,000 consecutive 30 Hz ticks. P99 tick duration
is at most 33.3 ms and maximum at most 50.0 ms. Existing synchronous Canon reads
are measured; state leakage, sector-local fault containment and background-work
contention are evaluated. Timing alone cannot prove a zero-blocking assertion.

[M4.2](https://github.com/vnvalentin/project0/issues/1377) must prove exact raw
Canon blueprint and ordered mutation parity for supported boundary and
interaction state. Its rejected-request controls must observe zero attempted
Canon INSERT/UPDATE writes, the configured active store and journal mode,
quiescent database/sidecar digests, and successful owned cleanup. Missing
supported observations and failed cleanup are failures.

The [user-approved scope clarification](https://github.com/vnvalentin/project0/issues/205#issuecomment-5954712157)
requires evaluation of currently supported state and explicit unsupported fields.
`REPAIRED`/`CLAIMED` permanent flags, persistent in-flight tether/line-of-sight
interaction state and occupancy bitmasks are not implemented acceptance fixtures.
The current supported unlock payload and synchronous interaction outcome must
retain their real representation. Do not add gameplay merely to fill a report,
and do not represent unsupported fields as passing empty comparisons. This
clarification does not waive workload, timing, isolation, persistence or
container gates.

Acceptance also requires the complete workload on an identifiable containerized
single-runtime artifact, exact source/engine/host/container identities, retained
reports, independent review and final-revision repository validation. Source
inspection, component tests or a source-checkout load run alone cannot establish
this result. The public diagnostic checkpoints below supply supporting evidence,
not completed capacity acceptance. Integrated component parity is qualified
by the separate final evidence below.

## Supporting evidence and unresolved coverage

[The retained frontier diagnostic](https://github.com/vnvalentin/project0/issues/1376#issuecomment-5957463251)
at `ce26012f3cbd0eb1875d1dfa8f4764d19bff3d5d` reports 60 zero-worker
observations, ten above 33.3 ms, none above 50 ms, no coalescing and a 44.115 ms
maximum. At that peak, 28.232 ms of journey checkpoints was nested inside
31.611 ms of position callbacks; frontier-stay took 0.123 ms and did not dominate
that peak. Reconstruction, hashing, persistence and scheduling remain unseparated
inside the checkpoint span. These are issue-recorded observations, not a new raw
report inspection. They justify continued attribution/evaluation without a
production refactor or process split. Sixty observations and zero workers do not
satisfy the 1,000-tick capacity and worker-isolation contract.

Retain physics and process coverage separately. Deadline polling resumes on
`process_frame`; asynchronous generation completion/evaluation can execute outside
the physics span. Nested timings must not be added, and coalesced iteration
maxima cannot establish exact per-tick P99. The tested request path is bounded
timeout fallback, not arbitrary successful generated candidates. No zero
native-engine blocking claim follows from these timings or an `await` statement.

[M4.2 final acceptance](https://github.com/vnvalentin/project0/issues/1377#issuecomment-5958365467)
and [qualified native evidence](https://github.com/vnvalentin/project0/issues/1377#issuecomment-5958474826)
bind accepted component parity to `6bda74b00aea805e6c1dce2bb72ac5431930c075`:
ten focused tests/case reports and 157/157 full scripts / 1,175 tests passed,
with source/helper/test qualification, rejected-write/observation controls,
zero error markers and verified owned cleanup. PR #1387 merged as
`521601a72e792e7a54c6b12c618f10eff48cadb0`; #1377 is closed. This is supported
same-runtime component evidence, not deployed cross-process handoff or capacity.
The source findings retain prior diagnostics with their historical identities.
Research source, benchmark/package source, engine/artifact identity and final
integration source remain distinct. Accepted main's interior-anchor persistence
([ADR 0016](0016-interior-anchor-and-cell-persistence.md)) has unresolved runtime
integration and does not establish new supported repair/claim gameplay.

[The retained full high-crossing profiles](https://github.com/vnvalentin/project0/issues/1376#issuecomment-5958477060)
at `51d39e2b308b0089ac2a6e08134fd9f3ad4699ac` both failed: 1,000 observations
with five coalesced supported iterations and 17 coalesced worker-stress iterations;
maxima 207.810 ms and 87.600 ms at about 19 crossings/sec. All required stage
observations and cleanup were qualified, but exact consecutive-tick P99 was
unavailable. At the single-step supported peak, frontier-stay took 188.753 ms
inside 198.682 ms of position callbacks; journey checkpoints took 7.488 ms.
A checkpoint-only explanation is contradicted. Relative synchronous telemetry,
stdout, trace preparation and scheduling contributions remain **unknown**.
Neither the failed stress nor this source analysis selects a process boundary.

[The final span10 checkpoint](https://github.com/vnvalentin/project0/issues/1376#issuecomment-5958678365)
at `746e8a2e8c42d8e3db26351c8adea50c9c646401` reports supported 82 crossings
in 34.372720 s (2.385613/sec), stress 80 in 33.581454 s (2.382267/sec).
Known single-step maxima are 548.826 ms / 83.827 ms. Coalescing leaves exact P99
unavailable; conservative first-1,000-tick nearest-rank P99 lower bounds
48.679 ms / 55.558 ms nevertheless establish failure. Source/package custody,
required callback stages, bounded fault/worker controls and cleanup are qualified.
[Final baseline delivery](https://github.com/vnvalentin/project0/issues/1376#issuecomment-5958967441)
is qualified at `4d355401f61e3e6da79341b7aa7779649cd8bff2`: native full
157-script/1,175-test GUT, all ten parity cases, source/cleanup, controls, record
sync, both final independent reviews and hosted CI passed. PR #1386 merged at
`424a71092d8f4b91fecdcf962aa19faa5a4c9510`; application/harness blobs are
unchanged from benchmark source `746e8a2e8c42d8e3db26351c8adea50c9c646401`.
The benchmark keeps its original identity and failed verdict. Research final-head
native validation/reviews remain separate; #1376 timing is blocked and M4 is not complete.

At the supported peak, three journey checkpoints took 534.269 ms inside
537.523 ms position callbacks, with zero telemetry calls and zero observed
throttling. This associates the peak with journey work, but does not isolate
Canon SELECT/decode, JSON serialization/hash, journey UPSERT or scheduling.
The earlier frontier-associated tail remains a separate measured limit.

## Proposed bounded checkpoint boundary

Retain one simulation and Canon authority; do not select zone sharding from
these observations. The next candidate is a bounded off-tick checkpoint lane
inside the existing game persistence authority. First measure unchanged public
child seams for canonical read/decode versus journey save; residual blueprint
serialization/hash work remains unassigned. The current
checkpoint reads immutable Canon, hashes its blueprint and copies schema_version
into sector_revision, then updates JourneyRegistry and synchronously UPSERTs
journeys. It does not replay mutations or rebuild runtime collision state.
Preserve these identities and reclaim/lifecycle behavior explicitly.

The next diagnostic uses harness-only Canon/Journey repository subclasses with
unchanged public `CanonRepository.get_canonical_sector` and
`JourneyRepository.save` `super()` calls under a proposed checkpoint-depth counter.
Reuse the same qualified store handles, explicitly preserve server/coordinator/
registry bindings and reject stale or missing observers. Observe Canon read/decode
and journey save without copying the production pipeline. The findings specify
positive delegated-path and negative binding/observation controls. Residual
checkpoint time remains unassigned; this source plan is not runtime evidence.
#205 stays awaiting the linked diagnostic and accepted architecture decision.

Simulation captures immutable, epoch/sequence-bound checkpoint requests.
A trusted game-owned executor may serialize persistence away from the physics
callback only after native affinity and exclusive handle ownership are proven.
The game accounts handle also holds Canon by default: it must not be shared
concurrently with tick callbacks or transferred between threads. Qualify all
consumers before routing repository work through one owner. A pure computation
worker receives no Canon handle; a dedicated persistence process is a separate
new authority design requiring acceptance, not the provisional-worker contract.
No implementation mechanism is claimed safe or necessary from the current span.

Before implementation, bound queue items/bytes, age, deadline and retries from
measurements; define saturation/backpressure outside the tick and durable
acknowledgement/reconciliation by request identity. Preserve ordered lifecycle
barriers, single active peer, reconnect/expiry and the crash-loss/freshness budget;
never report queued state as durable or allow stale epochs/sequences to overwrite
newer state. Test duplicates, ambiguous commits, crashes, saturation and storage
failure along with exact parity and complete workload timing. The findings give
this candidate's detailed owner, promotion and rollback contract. Its feasibility
and measured remedy remain open; it is not capacity acceptance.

## Authority and scale contract

- The game server owns player/NPC simulation, admission and authoritative tick
  state. A same-runtime sector crossing does not transfer that ownership.
- The game-owned Canon repository remains the only blueprint/mutation writer.
  Clients acknowledge presentation; generation workers propose untrusted data.
  Neither receives a Canon database handle or gameplay authority.
- Account/login authority, game journey state and Canon retain their current
  service-owned boundaries. Observe the actual configured Canon store; do not
  assume a historical database filename or add a second SQLite writer.
- Reuse the [worker-extension contract](../../.scratch/container-platform/issues/06-worker-extension-contract.md):
  bounded envelopes, job identity, idempotency, deadlines, provisional results,
  isolated resources and server-side validation. This provisional-worker seam
  does not authorize a Canon worker writer; changing the sole writer requires
  a separate authority design, compatibility and recovery evidence. The present per-sector
  generator has no global fair queue or retention limit. Their design and
  numeric budgets require measured need and a bounded implementation issue.
- If a simulation split becomes necessary, first specify a unique transfer ID
  and ownership fence; the complete supported Character/Vessel/action/spatial
  state and mutation watermark; prepare/commit/reconcile behavior; duplicate,
  timeout and reconnect recovery; and rollback without double effects. Transfer
  remaining simulation durations with explicit rounding/expiry rules, not
  another process's absolute physics-frame counter. These are future obligations,
  not an implemented handoff protocol.

## Alternatives and decision rule

Accepting the existing baseline is currently ruled out by the measured maximum
and conservative P99 failure. Retaining one runtime after a qualified remedy
preserves the existing authority and avoids introducing
cross-process handoff failure modes when the agreed workload already fits. It
is acceptable only after the complete measured profile passes.

Separating generation workers may contain a measured generation-contention or
failure problem without splitting player simulation or Canon ownership. The
worker contract and observable queue limits must address the reproduced cause.

Splitting authoritative simulation requires a measured simulation-capacity
failure or reproduced sector-local cascading failure plus a deployable ownership,
Canon, handoff, tick and recovery design. Containerization or the configured
10-peer policy cap alone is not evidence for that choice. Missing measurements
leave the decision awaiting evidence; they do not justify either acceptance or
an architecture split.

## Deployment, rollback and non-goals

Follow [ADR 0011](0011-stable-compose-deployment-authority.md): the durable
Compose authority is `/apps/project0/deploy/compose.yml`; a deployment names its
mutable services and retains the prior Compose artifact and recorded component
image identities. Prove the candidate and scoped rollback in isolation before
any separately authorized runtime promotion. The current script restores the
previous Compose artifact and image tags; a claim of digest custody requires
actual recorded artifact evidence. Storage compatibility must remain explicit.

For the proposed lane, qualify candidate and recovery game images on isolated
compatible storage; stop admission, drain a durable checkpoint barrier, stop and
fence the old store owner before activating one candidate. Rollback stops candidate
admission, reconciles durable/ambiguous requests, fences that owner, then restores
the previous compatible image/Compose artifact and checks journey/reclaim health
before reopening admission. No simultaneous old/new writers or replay of committed
mutations is permitted. Failed native-affinity/storage compatibility leaves the
proposal inactive; no migration is implicit. Prove this route before separately
authorized promotion.

This proposal introduces no worker, shard, database migration, client authority,
new gameplay state or production deployment. Multi-authority deployment is not
an automatic consequence of M4 acceptance. Revert this documentation change to
withdraw the proposal; any future runtime change requires its own rollback
boundary and accepted implementation evidence.
