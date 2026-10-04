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

The foundation marker is absent. Issue, Project and milestone/parent records were verified by the coordinator before this source edit. Current focused qualification is blocked by a fixture script failure before complete owner evidence. Supported lifecycle coverage, effective controls and full delivery remain NOT_OBSERVED. The bounded countermeasure uses explicit typed cycle selection. Next actor is the root coordinator qualifying the unchanged public behavior and independent evidence controls at the corrected source.

## Root-cause learning and rollback

A pre-native source review found that the main-task state reader would consume the complete bounded stat line before selecting its state. That exceeded the approved state-prefix capture boundary. The confirmed source cause was reuse of a generic line-prefix reader with a later delimiter search; the existence-only tracer could not exercise this observer. The focused countermeasure consumes only the reviewed own-task header, one state byte and its separator, then closes immediately, rejecting unknown or ambiguous headers. Independent source-audit controls must reject whole-line or tail reads. No fixture execution or runtime exposure occurred before this correction; native behavior and the actual contention observation remain unverified.

A separate pre-native source review found that directory opens could follow ancestor links even though leaf links were rejected. The source cause was checking only the terminal entry. The focused countermeasure freezes and rechecks the bounded ordinary canonical chain around exclusive leaf creation and known-state deletion; an ancestor-link mutation control must preserve outside bytes. The existing existence-only tracer and pure lifecycle receipts did not exercise filesystem custody. Native behavior remains unobserved, and same-path replacement and atomic race protection remain explicit limits. A further pre-native review found that the second file enumeration used for deletion lacked the original allowlist check. The actual deletion guard now rechecks membership as well as chain and link status; any newly enumerated unknown name preserves state. This correction does not claim atomic race protection.

A focused qualification stopped before complete owner evidence. A bounded source-location diagnostic identifies the cycle-selection initializer and its downstream result access. The source-supported hypothesis is that the conditional array expression lacks the declared element-type context during runtime assignment. The countermeasure initializes a typed array from a direct literal and conditionally appends the worker reopen cycle, preserving the fixed lifecycle order. The initial existence-only tracer and pure evidence controls did not execute this GDScript assignment. The same fixed public three-mode case is the discriminating regression; its assertions, workload and bounds remain unchanged. Regression and native affinity qualification are pending, so this checkpoint does not claim a confirmed runtime repair. The root coordinator owns remaining validation and acceptance gaps.

Rollback reverts the additive experiment files. Future cleanup removes only known-owned disposable state after process/path qualification; unknown state is retained. No production database is touched.


### Affinity failure discriminator before further acceptance work

The isolated owning-runtime qualification passed, while the hosted full-suite gate remains failed. That difference narrows the next investigation but does not establish a cause or clear acceptance.

Outcome and scope: classify the existing failing affinity assertion using fixed source-authored status categories. Only the assertion message and a small pure diagnostic helper change; application behavior, supported fixture operations, workload, deadlines, assertions, controls and fail-closed unknowns remain unchanged. No production persistence adoption or broader Milestone 3 acceptance follows from this change.

Hypothesis and cheapest discriminating check: the generic assertion currently conflates owner completion, native lifecycle, synchronization observation and teardown qualification. A closed literal-message classification at that same assertion can distinguish the observed boundary in one changed-source hosted run. Missing or inconsistent fields remain unknown, and no dynamic runtime values or detailed evidence are published.

Root keeps the issue and draft pull request pending, independently reviews the source change, verifies source-only ownership and record checks before a normal candidate commit, and binds subsequent owning-runtime acceptance to the actual final revision. An unchanged hosted retry, relaxed assertion or timing limit, and inference of a common historical cause are unacceptable.

Changed-source owning-runtime and hosted acceptance remain pending. Governing checkpoint: https://github.com/vnvalentin/project0/issues/1444#issuecomment-5982538207


### Bounded wait-observation discriminator before the next source change

Outcome: identify the observed reason the existing sleep corroboration remains unqualified in the hosted context. Primary kernel documentation supports wait-helper name portability as one hypothesis; unavailable observations, unresolved channels and sampling state remain alternatives. The underlying hosted cause is not confirmed.

Scope and cheapest discriminating check: add a single fixed source-authored status on an unsuccessful observation, derived only from the state and channel values already read by the existing fixture. It will distinguish unavailable state, unavailable channel, a missing sleeping-state pair, an unresolved channel, a specifically documented alternative futex helper, and other unknown channels. No raw strings or dynamic runtime values will be output.

The existing successful predicate, failure result, evidence schema, process reads, sample loop, workload, deadlines, ownership and cleanup remain unchanged. This diagnostic supplies no new acceptance and makes no permission or exact-target identity claim. Zero, unavailable or other unknown observations remain unqualified. No generic futex-name pattern, skip, relaxed assertion, privilege change or timing extension is permitted by this investigation.

Root will review the source and capture contract before a normal slice checkpoint, then use one changed-source hosted result to classify the boundary. Prior failed runs remain retained. Owning-runtime qualification must still bind the actual final source; full delivery and Milestone 3 remain pending.

Changed-source checkpoint: the fixture-only diagnostic is prepared for a normal slice commit. The existing public assertions remain unchanged. The fixed label describes the last unsuccessful sample and does not identify root cause. Current owning-runtime, hosted and full-suite acceptance remain pending.

Governing checkpoint: https://github.com/vnvalentin/project0/issues/1444#issuecomment-5982753651


### Root-cause learning and bounded wait-name correction plan

Symptom and public seam: the native affinity fixture remains unqualified in hosted validation after successful owner lifecycle and cleanup. The fixed diagnostic identifies a documented alternative futex wait helper inside the existing sleeping-state brackets. Detailed runtime evidence remains private.

Confirmed cause of this observed rejection: the source predicate recognizes only one kernel helper spelling. Official versioned kernel documentation identifies an alternative name for the same queue-and-wait operation. Existing tests missed this portability boundary because their qualified environment used the original spelling. This does not explain every historical failure or prove an exact target address or uninterrupted wait duration.

Outcome and scope: admit that specific documented helper alongside the existing helper, while retaining both sleeping-state samples. Preserve all reads, deadlines, workload, transaction assertions, native ownership, cleanup, evidence schema and NOT_OBSERVED limitations. Zero, unavailable observations, unrelated or unknown helpers remain rejected; no generic pattern, additional privilege, timing extension or skip is permitted.

Hypothesis and cheapest discriminating check: the exact-name correction removes this observed source rejection. Independently review the one-predicate change, qualify source-bound copied controls, then run changed-source hosted and owning-runtime focused validation. Full validation and delivery remain pending until the final revision passes all required gates. Rollback is the source predicate; no application persistence adoption is included. Root owns execution; independent Standards and Spec reviews remain required.

Primary source: https://www.kernel.org/doc/html/v6.16/kernel-hacking/locking.html#c.futex_do_wait

Governing checkpoint: https://github.com/vnvalentin/project0/issues/1444#issuecomment-5982981913
