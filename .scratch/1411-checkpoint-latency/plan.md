# #1411 checkpoint latency

Governing issue: https://github.com/vnvalentin/project0/issues/1411
Parent goal: #204; blocks #1376; architecture consumer: #205.
Milestone 4 / Slice M4.1: Single-Runtime Load and Isolation Baseline.
Accepted main at orientation: `3b6c21812cdd48df90842fe5689df0358259bd03`.
Harness guidance consumed: `77de008a0f28eb91726527d543adb435735a2157`.

## Outcome / SDD
Reduce repeated Canon-derived checkpoint work while preserving current journey durability.
Canon owns a derived checkpoint-metadata result; each request still checks the existing
store and SELECTs the authoritative row. Reuse the existing parsed-blueprint serialization
hash only for exact unchanged stored JSON, with bounded memory. Return current schema
version/hash. The server retains each synchronous journey UPSERT, current handles,
10-second/one-unit checkpoint triggers, schemas, write ordering and failure behavior.
No ADR is required for repository-local derived-result reuse with unchanged authority,
persistence and recovery contracts. ADR #205 still needs final scale evidence.

Scope: Canon repository derived result, authoritative checkpoint caller and Linux
regressions at existing public Canon/Journey persistence seams. No gameplay, deployment,
new handle/thread/writer, storage migration, skipped/deferred save, timing-limit change,
or unrelated checkpoint failure/recovery/backoff behavior (#1142/#1146).

## Hypothesis / cheapest check
Repeated parse/serialize/hash of unchanged immutable Canon contributes avoidable work.
First compare candidate metadata with the accepted public Canon-read/hash behavior.
Native RED must be observed before application changes. Cache layout is not a test seam.
Then test freshness/lifecycle errors and actual checkpoint-to-reopened Journey records,
and compare the original representative M4 workload without changing its thresholds.
Journey UPSERT/commit and scheduling may remain dominant; a component pass is not capacity.

## BDD / agreed public seams
Given committed Canon, repeated metadata reads return the same revision/hash as the
existing public read. Given changed JSON/schema, missing-to-insert, or close/reopen, stale
metadata cannot succeed. Given shared/dedicated stores, authoritative checkpoints retain
the exact persisted/reopened journey fields and every save. No negative result is cached
as trusted Canon. Tests cover public repository outcomes and persisted recovery; no
private cache assertions. The user authorized this bounded remediation and the root
confirmed these existing Canon/Journey/authoritative-checkpoint seams before tests.

## TDD / validation frontier
First regression: `test_checkpoint_metadata_matches_existing_canon_read` in
`tests/integration/test_canon_repository.gd`. A guarded missing-method assertion makes
the accepted baseline fail through GUT, without a missing-method engine error.
Native RED is pending the coordinated window; application countermeasure is absent.
Focused recipe and owning-runtime preflight are in `validation-plan.json`. Root execution
monitor supplies fresh XDG state, coordinated lock, engine ancestry/start identity,
exact-source binding, complete logs/XML, all four engine-error checks and finally cleanup.
The embedded command selects exactly the Canon repository script; XML must prove that
selection, not merely successful process exit.
Full GUT, record sync, independent Standards+Spec, required CI and original qualified
1000-actual-tick workload remain required at final source. No repeated-to-green benchmark.

## Root-cause learning / rollback
Checkpoint timing attribution proves high inclusive work, not isolated hash or fsync
causality. Original failures remain linked on #1411/#1376. Source-only preparation and
static checks do not establish runtime behavior. Revert the bounded source commit via
normal PR to restore behavior; no data rollback. Never mutate live stores or foreign jobs.
