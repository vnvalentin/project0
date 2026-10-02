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

## Incremental next-test sequence (source design only)

Application edits remain gated on the first qualified native RED and dependency #1413.
Do not bulk-write all regressions before learning from the first tracer bullet.

1. Observe the committed compatibility regression RED, then implement only the public
   Canon metadata getter. Run the same selected script GREEN before moving to the next
   behavioral increment. The public accepted Canon-read/hash result is the legacy oracle;
   returned metadata must omit the blueprint rather than materialize it for the caller.
2. Warm metadata, then change only the isolated authoritative row's schema_version through
   SqliteStore's bound public query API while leaving blueprint_json unchanged. Metadata
   must report the new row revision with the unchanged compatible hash. Then separately
   change the stored blueprint JSON (including alternate formatting/key ordering) and
   compare with the existing Canon public read. These are fixture-controlled persisted
   row changes; no production API that rewrites immutable Canon is introduced.
3. Cover absence-to-success after ordinary canonicalize_blueprint, and invalid/empty
   sector ids using the existing outcome contract. Warm metadata then make the isolated
   query unavailable (drop its fixture table through SqliteStore public query). Both
   public Canon reads must return query_failed, never cached success.
4. Warm metadata, close the same store object, assert not_open, then reopen into owned
   fixture state and assert that its current row or absence wins. Every alternate DB
   path and its WAL/SHM/journal companions must be registered for finally cleanup.
   No public metadata request can skip the current store/open/query check.
5. Add a valid oversized supported blueprint using the existing schema-v3 structure
   fixture with a long nonempty structure_id (current schema does not bound that string).
   Repeated metadata still equals the accepted Canon-read result and a later row change
   remains fresh. This proves oversize correctness, not cache memory use. Bound both
   retained entry count and retained JSON characters in source; independent review
   verifies the bound and uncached fallback. Do not inspect private cache layout.
6. Extend existing Journey integration coverage with real ServerMain/Canon/Journey/Registry
   objects in isolated shared and dedicated fixture stores. The existing server-orchestration
   tests already safely instantiate ServerMainScript.new() without launching a backend.
   Bind one controlled Player character, enter through JourneyRegistry, drive the actual
   authoritative checkpoint callback and read results through JourneyRepository.load_all.
   Reopen the original journey store and verify the last successful persisted fields:
   journey_id, character_id, lifecycle_status, peer_id, x/y/z, sector_id, sector_revision,
   sector_geometry_hash, last_checkpoint_at and last_disconnected_at. Two distinct
   positions/checkpoints prove the latest save is durable; no private cache or SQL row
   query is the assertion seam. Capture before/after wall-time bounds for timestamps
   rather than predicting exact system time. Preserve normal registry reclaim behavior.

Only after the server checkpoint-caller increment is GREEN, audit its integration fakes
for the new public method. The existing fake Canon in server_main_jit_orchestration
provides only get_canonical_sector; do not hide absent fixture coverage with a production
fallback path. Expand the exact owned plan selection to Canon plus Journey scripts
before native execution and verify both selected XML script names.

Diagnostic #1405 is not edited in this worktree. After it is accepted/integrated, extend
the observer's unchanged-super Canon child path for metadata and qualify its controls;
otherwise its current get_canonical_sector-only override would omit checkpoint Canon
timing. Rebind final full/benchmark/review gates to the eventual clean production head.

Status: first test/plan committed, native RED pending accepted import-boundary fix #1413
and root's coordinated window. No countermeasure, runtime pass or capacity is claimed.
