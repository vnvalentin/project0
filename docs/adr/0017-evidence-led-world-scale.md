---
status: proposed
---

# Evidence-led world scale with one authority per fact

Milestone 4 evaluates whether the current single authoritative game runtime
meets the agreed workload and isolation envelope. The proposed decision is to
retain one simulation and Canon-writing authority when the complete measured
baseline passes, and introduce a process boundary only for a reproduced capacity
or isolation problem. This ADR is **proposed** while final M4.1 capacity/isolation and container
evidence are pending. Supported M4.2 component parity is accepted separately;
it does not establish baseline capacity.

Governing issue: [#205](https://github.com/vnvalentin/project0/issues/205).
Parent: [#204](https://github.com/vnvalentin/project0/issues/204).
Source analysis: [M4.3 findings](../../.scratch/zone-sharding/m4-source-findings.md),
reconciled at accepted main `521601a72e792e7a54c6b12c618f10eff48cadb0`.
The [initial checkpoint](https://github.com/vnvalentin/project0/issues/205#issuecomment-5957545685)
and [evidence amendment](https://github.com/vnvalentin/project0/issues/205#issuecomment-5958590827)
own this documentation work.

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
zero error markers and verified owned cleanup. PR #1387 merged as accepted main
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

Await the explicit span10 result at
`746e8a2e8c42d8e3db26351c8adea50c9c646401`: unchanged production behavior,
actual crossings at least two/sec and inclusive unchanged-super telemetry spans.
Accept only actual qualified P99/maximum and all capacity/isolation/container
gates; preserve span1 failures as the higher-crossing limit. Missing/coalesced
measurements leave acceptance blocked. A target maximum failure requires the
smallest causal check or a fully specified evidence-backed boundary, rather than
an assumed worker or Canon writer. The findings contain the final decision outline.

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

Retaining one runtime preserves the existing authority and avoids introducing
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

This decision introduces no worker, shard, database migration, client authority,
new gameplay state or production deployment. Multi-authority deployment is not
an automatic consequence of M4 acceptance. Revert this documentation change to
withdraw the proposal; any future runtime change requires its own rollback
boundary and accepted implementation evidence.
