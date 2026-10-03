# Experiment #1444 — one-owner persistence affinity prerequisite

Governing issue: https://github.com/vnvalentin/project0/issues/1444
Parent experiment: https://github.com/vnvalentin/project0/issues/1347
Related Epic: https://github.com/vnvalentin/project0/issues/951
Related Feature: https://github.com/vnvalentin/project0/issues/950
Milestone: Milestone 3: Authoritative Content Systems.
Primary named group: M3.1: Spatial Facility Authority. M3.2 is a supporting relationship, not duplicate milestone membership.
Implementation owner: the root coordinator of the authorized M3 continuation.

## Outcome and boundaries

Determine whether an experiment-owned worker can perform its complete disposable native SQLite lifecycle while the main simulation thread exchanges bounded values through nonblocking mailbox attempts. Qualify measurement coverage and intentional controls before drawing any affinity conclusion.

Scope is an additive experiment fixture and public GUT case. No application persistence executor, production routing or queue, live Canon/accounts handle, store/repository transfer, competing writer, migration, client/Windows change, dependency installation or deployment. This work does not accept the proposed architecture decision, satisfy integrated workshop timing, close its parent experiment, or complete the milestone. Existing Canon timing debt and the separate full-validation approval gate remain binding.

Unacceptable outcomes are unknown coverage reported as zero; incorrect caller/owner attribution; completion before native close and release; ineffective controls treated as evidence; crash, script error or setup failure treated as assertion RED; unqualified state deletion; and fixture evidence presented as application acceptance.

## SDD

The future fixture is a plain RefCounted with initialization, single-attempt submission, single-attempt polling and completed finalization. One worker owns each fixed mode's native objects and trace buffering. Only closed primitive values cross the mailbox. Candidate main code never performs a blocking acquisition, join, SQLite entry or resource load in the request window.

The fixed experiment uses candidate, main-SQLite control and main-wait control modes. Each owns fresh state. Direct commit/rollback and same-file reopen parity, successful native close and worker-local final release precede completion. Constructor entry has an explicit not-yet-observed identity; later entries must preserve the resulting native object's identity. Cleanup is an explicit owning-thread epilogue; cleanup success cannot replace a failed operation result.

The wait control declares only worker control-to-mailbox readiness nesting; main never waits while holding the mailbox. Supported call-site coverage, effective contention, raw monotonic timing and actual loaded-addon association are separately required. Hidden native/engine locks and production consumers remain outside this fixture's demonstrated coverage.

## BDD

Given fresh disposable state, a complete reviewed call inventory and qualified capture, when the owning worker completes both native lifecycles and recovery, then candidate evidence must establish supported ownership, parity and absence of forbidden main entries. Intentional controls must expose correctly attributed real main SQLite work and contended waiting. Missing, ambiguous or ineffective observations leave an explicit unqualified result rather than an invented zero.

The public seam is `tests/integration/test_persistence_thread_affinity.gd::test_direct_sqlite_worker_lifecycle_has_complete_fixture_coverage`. The initial edit is only a missing-fixture guard at that seam; it supplies no lifecycle or measurement implementation.

## TDD and validation

First retain the parse-safe named missing-fixture assertion and stop for root-coordinated RED qualification. No fixture implementation precedes that checkpoint. After qualified RED, add the bounded fixture, complete behavior assertions and meaningful coverage/capture controls in a separately reviewed logical edit.

Exact commands, selected inputs, controller/source/provenance bindings and detailed evidence remain in private owned validation records. Static ownership and record-sync checks accompany source edits. Root exclusively coordinates native qualification. Standard full GUT and independent Standards/Spec review remain required before delivery closure; a focused result does not replace them.

## Foundation and delivery status

The foundation marker is absent. Issue, Project and milestone/parent records were verified by the coordinator before this source edit. Current status is source preparation; RED, lifecycle, effective controls, loaded-addon association and full delivery remain NOT_OBSERVED. Next actor is the root coordinator reviewing the frozen tracer and privately bound validation plan.

## Root-cause learning and rollback

No runtime observation is claimed in this source-only checkpoint. Unexpected failures require private symptom/cause/countermeasure evidence and a permitted status-only governing update. The root coordinator owns remaining validation and acceptance gaps.

Rollback reverts the additive experiment files. Future cleanup removes only known-owned disposable state after process/path qualification; unknown state is retained. No production database is touched.
