# Experiment #1444 — one-owner persistence affinity prerequisite

Governing issue: https://github.com/vnvalentin/project0/issues/1444
Parent experiment: https://github.com/vnvalentin/project0/issues/1347
Related Epic: https://github.com/vnvalentin/project0/issues/951
Related Feature: https://github.com/vnvalentin/project0/issues/950
Milestone: Milestone 3: Authoritative Content Systems.
Primary named group: M3.1: Spatial Facility Authority. M3.2 is a supporting relationship, not duplicate milestone membership.
Implementation owner: the root coordinator of the authorized M3 continuation.

## Outcome and boundaries

Determine whether an experiment-owned worker can perform its complete disposable native SQLite lifecycle while the main simulation thread exchanges bounded values through nonblocking mailbox attempts. Qualify measurement coverage and intentional controls before drawing any affinity conclusion. The unverified hypothesis is that one trusted owner can commit, roll back, reopen, close and release its native handles while candidate main code makes no supported native SQLite or blocking entry. The cheapest next discriminating check is the single fixed three-mode public case with independently derived coverage and effective controls, after source/capture review.

Scope is an additive experiment fixture and public GUT case, plus the independent pure evidence validator and its controls at `scripts/persistence_thread_affinity_evidence.py` and `scripts/test_persistence_thread_affinity_controls.py`. No application persistence executor, production routing or queue, live Canon/accounts handle, store/repository transfer, competing writer, migration, client/Windows change, dependency installation or deployment. This work does not accept the proposed architecture decision, satisfy integrated workshop timing, close its parent experiment, or complete the milestone. Existing Canon timing debt and the separate full-validation approval gate remain binding.

Related ADR context: [ADR-0017 — Evidence-led world scale with one authority per fact](../../docs/adr/0017-evidence-led-world-scale.md) remains proposed and unaccepted. This additive experiment and its initial existence-only tracer make no production architecture, ownership or persistence decision, so they need no new ADR. It does not authorize production adoption of ADR-0017.

Unacceptable outcomes are unknown coverage reported as zero; incorrect caller/owner attribution; completion before native close and release; ineffective controls treated as evidence; crash, script error or setup failure treated as assertion RED; unqualified state deletion; and fixture evidence presented as application acceptance.

## SDD

The fixture is a plain RefCounted with initialization, single-attempt submission, single-attempt polling and completed finalization. One worker owns each fixed mode's native objects and trace buffering. Only closed primitive values cross the mailbox. Candidate main code never performs a blocking acquisition, join, SQLite entry or resource load in the request window.

The fixed experiment uses candidate, main-SQLite control and main-wait control modes. Each owns fresh state. Direct commit/rollback and same-file reopen parity, successful native close and worker-local final release precede completion. Constructor entry has an explicit not-yet-observed identity; later entries must preserve the resulting native object's identity. Cleanup is an explicit owning-thread epilogue; cleanup success cannot replace a failed operation result.

The wait control declares only worker control-to-mailbox readiness nesting; main never waits while holding the mailbox. Supported call-site coverage, effective contention, raw monotonic timing and actual loaded-addon association are separately required. Hidden native/engine locks and production consumers remain outside this fixture's demonstrated coverage.

The fixed wait control may establish supported blocking-call detection, failed-try-lock contention, positive elapsed lock-call time and bounded generic main-task futex-sleep corroboration. Its target attribution is a source-based inference. Exact target-futex identity, continuous wait duration and hidden VM/engine/native locks remain NOT_OBSERVED. Elapsed lock-call time is not exact synchronization waiting time, and these limits change no integrated milestone metric or acceptance criterion.

The request window includes submission, the entire worker lifecycle, primitive completion consumption and observed worker termination. The worker returns only bounded primitive trace data after its final mailbox unlock. Main retrieves that final trace with a separately traced join after the request window ends. Native handles never enter a mailbox or Thread result; all encountered native failures retain failure status through their owner-local close/release epilogue.

Each fixed mode runs once with fresh disposable state outside the prepared source. The worker performs first and reopen cycles; the deliberate main SQLite control needs only its complete first cycle with fixed extra queries. Trace spans pair one supported entry with its exit, with explicit per-mode and aggregate ceilings; overflow fails qualification instead of silently truncating. Mailbox completion and final Thread trace return have separate bounded primitive payloads. Worker-only initialization polling uses a fixed coarse idle interval, while the short contention observer uses its separate fixed sampling interval; neither adds a main blocking entry or changes the request workload. An exhausted trace or deadline remains unqualified. The public test executes the same modes with or without optional coordinator evidence capture; it never skips for missing evidence configuration. Only a fixed, fresh transient evidence destination may receive bounded primitive JSON after all teardown. Unknown files or incomplete owners remain unqualified and retained for controller containment. The fixed mode directory is created only under the existing configured user root after a bounded ordinary, link-free, canonical ancestor-chain check. Its post-creation chain is frozen and rechecked immediately before removal, with hidden entries subject to the same fixed allowlist. Unknown or changed chains preserve state. Same-canonical ordinary replacement, inode identity and atomic filesystem race protection remain NOT_OBSERVED; the coordinator owns the isolated temporary root.

## BDD

Given fresh disposable state, a complete reviewed call inventory and qualified capture, when the owning worker completes both native lifecycles and recovery, then candidate evidence must establish supported ownership, parity and absence of forbidden main entries. Intentional controls must expose correctly attributed real main SQLite work and contended waiting. Missing, ambiguous or ineffective observations leave an explicit unqualified result rather than an invented zero.

The public seam is `tests/integration/test_persistence_thread_affinity.gd::test_direct_sqlite_worker_lifecycle_has_complete_fixture_coverage`. The initial missing-fixture guard remains at that seam; the subsequent increment supplies the fixed three-mode experiment behavior without changing production consumers.

## TDD and validation

First retain the parse-safe named missing-fixture assertion and stop for root-coordinated RED qualification. The initial named fixture-absence RED is qualified privately. The next logical edit adds the bounded fixture and complete three-mode public behavior assertions; independent evidence/capture controls and final source-bound native qualification remain required.

Exact commands, selected inputs, controller/source/provenance bindings and detailed evidence remain in private owned validation records. Static ownership and record-sync checks accompany source edits. Root exclusively coordinates native qualification. Standard full GUT and independent Standards/Spec review remain required before delivery closure; a focused result does not replace them.

## Foundation and delivery status

The foundation marker is absent. Issue, Project and milestone/parent records were verified by the coordinator before this source edit. Current status is bounded fixture implementation after initial RED. Supported lifecycle coverage, effective controls, actually loaded-addon association and full delivery remain NOT_OBSERVED. Next actor is the root coordinator freezing the complete source, independent validator, capture controls and private qualification plan before native execution.

## Root-cause learning and rollback

A pre-native source review found that the main-task state reader would consume the complete bounded stat line before selecting its state. That exceeded the approved state-prefix capture boundary. The confirmed source cause was reuse of a generic line-prefix reader with a later delimiter search; the existence-only tracer could not exercise this observer. The focused countermeasure consumes only the reviewed own-task header, one state byte and its separator, then closes immediately, rejecting unknown or ambiguous headers. Independent source-audit controls must reject whole-line or tail reads. No fixture execution or runtime exposure occurred before this correction; native behavior and the actual contention observation remain unverified.

A separate pre-native source review found that directory opens could follow ancestor links even though leaf links were rejected. The source cause was checking only the terminal entry. The focused countermeasure freezes and rechecks the bounded ordinary canonical chain around exclusive leaf creation and known-state deletion; an ancestor-link mutation control must preserve outside bytes. The existing existence-only tracer and pure lifecycle receipts did not exercise filesystem custody. Native behavior remains unobserved, and same-path replacement and atomic race protection remain explicit limits.

No runtime observation is claimed in this source-only checkpoint. Unexpected failures require private symptom/cause/countermeasure evidence and a permitted status-only governing update. The root coordinator owns remaining validation and acceptance gaps.

Rollback reverts the additive experiment files. Future cleanup removes only known-owned disposable state after process/path qualification; unknown state is retained. No production database is touched.
