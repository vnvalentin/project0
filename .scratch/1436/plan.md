# #1436: recovered authored-profile identity

Governing issue: https://github.com/vnvalentin/project0/issues/1436.
Parent delivery #1341; accepted primitive #1425; Feature #950.
Milestone 3, named group M3.2 item ownership and transactions. Existing issue,
owner and Project links are preserved. Foundation prerequisites are closed.

## Outcome, scope and hypothesis

A caller recovering committed item creation properties must receive corrupt_record
and null properties when the companion pins different authored content from its
stored profile, with no writes, repair or rederivation. This protects the existing
versioned identity contract; it introduces no new schema or item fields.

Hypothesis: recovery checks each record's own digest and metadata/units but omits
the cross-record digest match. A self-consistent changed authored rule under the
same pins can therefore recover an incompatible unchanged companion.

Current stage is records and one behavior-first regression only. Product repair
waits for root-qualified native RED. Root owns runtime scheduling and controller
review; this record is not execution authorization.

## SDD and safety

Use the existing public ItemLedgerRepository.create_instance_with_properties and
get_creation_properties seams, real owned fixture SQLite, and existing setup and
teardown. Deliberate corruption changes only the stored profile JSON and matching
self-digest. Companion, receipt, item, IDs, versions and units remain unchanged.
Read after close/reopen; begin DML observation after corruption/reopen so fixture
setup is not misrepresented as rejected-command writes. Reject with no automatic
repair. Unavailable observations or failed cleanup are failures.

Non-goals: live Canon access, output rederivation, schema/migration/dependency or
balance changes, creation tuning defaults, passive wear, client/Windows changes,
threading/executor authority, #1435 replay repair or M3 acceptance. The separate
#1435 full-gate blocker and #1339 investigation remain independent.

No new ADR is required: this repairs the established pinned authored-content
identity invariant at the existing recovery seam, without schema, authority,
threading, migration or architecture change. Future production routing is outside
this scope and cannot be accepted through this repair.

## BDD and TDD tracer

Given a healthy committed item and exact typed creation-property companion,
when only the authored durability fixture offset changes from 10 to 12 together
with its matching canonical JSON digest while pins and units remain identical,
then recovery after reopen returns corrupt_record/null, attempts zero DML and
preserves both inconsistent records.

Selected public test:
`tests/integration/test_item_ledger_repository.gd::test_creation_properties_reject_different_self_consistent_authored_content_after_reopen`.
One expected combined RED assertion label:
`1436 recovered creation properties reject conflicting authored profile digest`.
Healthy profile/digest/companion premises are checked before the mutation.
Fixture-only row queries construct and verify the deliberate corruption; the
behavior verdict comes from the public recovery API. Existing healthy typed
recovery and self-digest/corruption cases remain mandatory.

## Validation and review frontier

The ignored private build plan precedes the test edit and declares Linux ownership,
actual selected test, proposed root-owned controller interface, artifacts and
cleanup. Static ownership preflight checks ownership only; the controller must be
implemented, source-bound and independently reviewed before execution. Native RED,
GREEN, focused regressions, exact-final-source Standards and Spec review, unchanged
full scripts/run_gut_validation.sh and scripts/check_record_sync.sh remain required.
A complete actual full-suite inventory plan must precede the full run. No test
selection or runtime evidence may be invented to make a gate pass.

Public records contain scope/status/next actions only. Precise source, host,
controller and runtime evidence remain private. At this stage native evidence is
NOT_OBSERVED; no Godot, parse check, preparer or controls have been executed.

## Root-cause learning

Symptom: source predicts success for individually self-consistent but incompatible
profile/companion records. Public seam: get_creation_properties. Cheapest
falsifying check is the profile-only replacement tracer above. Confirmed native
cause is unknown pending RED. Existing tests cover self-digest/payload corruption,
not this cross-record mismatch. Countermeasure is not yet implemented; regression
and final delivery evidence remain pending.

## Rollback and next owner

Revert only this governed test/record change; owned fixture cleanup removes only
its disposable DB/WAL/SHM/journal after close/quiescence. No production state is
mutated. Implementer prepares/pushes the tracer and draft PR. Root reviews the
exact source/controller and owns one bounded native RED attempt before any
product repair. This issue remains open and awaiting native evidence.
