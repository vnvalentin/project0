---
status: proposed
---

# Evidence-led world scale with one authority per fact

Milestone 4 evaluates whether the current single authoritative game runtime
meets the agreed workload and isolation envelope. The proposed decision is to
retain one simulation and Canon-writing authority when the complete measured
baseline passes, and introduce a process boundary only for a reproduced capacity
or isolation problem. This ADR is **proposed** while the M4.1/M4.2 measurements
and container evidence are pending; it does not claim the baseline passes.

Governing issue: [#205](https://github.com/vnvalentin/project0/issues/205).
Parent: [#204](https://github.com/vnvalentin/project0/issues/204).
Source analysis: [M4.3 findings](../../.scratch/zone-sharding/m4-source-findings.md),
reconciled at accepted main `9702827c918cbf34719e11123e349c20af76fc1f`.
The [records-first checkpoint](https://github.com/vnvalentin/project0/issues/205#issuecomment-5957545685)
owns this documentation amendment.

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
not completed capacity or integrated parity acceptance.

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

[M4.2's final-source integration checkpoint](https://github.com/vnvalentin/project0/issues/1377#issuecomment-5957487132)
retains historical ten-case focused evidence at
`5e7d56dafbe29b3e8f66d396cb5202894f5fabf7`; final integrated native parity,
full validation and review remain pending. The source findings retain the matched
worker and earlier inclusive callback diagnostics with their exact identities.
Research source, benchmark/package source, engine/artifact identity and final
integration source remain distinct. Accepted main's interior-anchor persistence
([ADR 0016](0016-interior-anchor-and-cell-persistence.md)) has unresolved runtime
integration and does not establish new supported repair/claim gameplay.

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
  isolated resources and server-side validation. The present per-sector
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
