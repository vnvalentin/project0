# #849 two-process anchor recovery experiment

Governing issue: https://github.com/vnvalentin/project0/issues/849
Approved records-first brief: https://github.com/vnvalentin/project0/issues/849#issuecomment-5955162485
Parents #838 / #749 / #495; Milestone3, M3.1 Spatial Facility Authority.
Accepted base b1734450ba03df7f1818b966409f14658dba2b93; branch slice/849-interior-process-recovery.
Harness77de008a0f28eb91726527d543adb435735a2157 consumed. Foundation marker absent. Dirty original Linux and Mac lanes preserved.

## Outcome / SDD / BDD
A fresh native Godot process opens two existing isolated SQLite fixtures after the preparing process exits. Valid state resolves and exactly replays the original anchor/cell. Unsupported retained mutation schema fails closed on live resolution/replay while archival anchor and stored bytes remain unchanged. Compare exact persisted Canon string/UTF-8 length/SHA1, ordered mutation IDs/actor/revisions and serialized sequence hash, raw anchor/cell records and normalized anchor values. Record distinct PIDs and explicit process completion. Recover starts an OBSERVED direct-statement window after open; every operation/table disposition is zero. Native row effects remain NOT_OBSERVED.

Only scripts/test_interior_anchor_process_recovery.gd and owned planning/runner files change; all accepted product repositories remain unchanged. Existing godot-server scripts/test_*.gd inventory owns the smoke harness. Raw synthetic expected bytes live only in coordinator-owned temporary state; retained reports contain comparisons/hashes/identity metadata and scoped counters. Two new guarded DB names beneath unique XDG_DATA_HOME; never open a real database. Plot authority remains unverified. Real generation, scene assembly, authenticated physical event, permission/Area3D, client and full #849/#851 acceptance remain NOT_OBSERVED.

Coordinator runs prepare then recover, validates reports even after failure and removes only its mktemp directory in EXIT cleanup. Missing/invalid reports, script errors, nonzero unexpected process status, missing observations or incomplete cleanup reject evidence. Copied-expectation negative control must produce recovery exit1 and exactly a Canon-byte mismatch, with complete phases/observations and cleanup; coordinator reports successful negative-control rejection without presenting that failed recovery as baseline success.

## Validation / rollback
Run only Linux192.168.1.254 through verified equivalent okami SSH endpoint, existing /usr/local/bin/godot4.3 and SQLite. Preflight before Godot: python3 scripts/check_validation_ownership.py --plan .scratch/849-recovery/validation-plan.json --output <owned-result>/plan-ownership.json. Harness: bash .scratch/849-recovery/run-experiment.sh <unique-label> [negative-control]. Unique build/validation/849-recovery/<run-id> retains machine-readable result, phase logs/JSON and exact command/host/engine/revision/source fingerprints. Standard full GUT is serialized with root at frozen head, then record sync and independent Standards+Spec review. No schema/migration/deployment changes. Rollback removes/reverts harness adoption while retaining durable user state; fixture cleanup deletes owned temp state only.

## Evidence / root-cause learning
Baseline/negative-control/full/reviews pending. Accepted behavior is characterized; no invented TDD RED for already-correct repositories. Unexpected validation/runtime failures require symptom, falsifiable hypothesis, discriminating check, confirmed root cause, why existing evidence missed it, countermeasure and regression evidence here and additively on #849 before delivery. Full-suite slot is currently ledger-owned.

Static preparation: ownership preflight passed with runtime_executed=false, bash -n passed, and git diff --check passed. Native execution is explicitly held by coordinator while ledger diagnoses the shared full-suite frontier. No recovery result is claimed.

Resume source-custody addendum: https://github.com/vnvalentin/project0/issues/849#issuecomment-5956796960. Runner now rejects dirty implementation state before native work and checks clean state again in the final retained verdict alongside unchanged HEAD/source hashes. Setup rejection retains evidence and runs guarded cleanup. Static diagnosis found the prior selected-hash/HEAD checks did not independently enforce clean-worktree custody; syntax/ownership checks do not detect that omission. No native execution has occurred.

Owned import-stop correction: https://github.com/vnvalentin/project0/issues/849#issuecomment-5957086029. Bash negated rg was exempt from set-e and did not stop phases; explicit Python scan now returns failure before the next phase, with retained verdict/cleanup. Native import root cause remains unknown under #1396; no dependency/product bypass. Scanner shell controls below qualify stop logic only, not native recovery or construction acceptance.

Independent Standards finding: https://github.com/vnvalentin/project0/issues/849#issuecomment-5957467329. Final source hashing could raise uncaught OSError before retained verdict serialization. Each selected-source read now catches OSError, records identity NOT_OBSERVED and explicit error, and retains a failed final result. Shell controls use only an isolated copied runner/source context; actual tracked/unrelated sources remain preserved. Native recovery/full gates remain pending at the resulting final revision.

Static serializer follow-up: https://github.com/vnvalentin/project0/issues/849#issuecomment-5957533927. Non-object phase/scenarios JSON could cause AttributeError before final verdict. Explicit container guards now retain failure errors before storing phases. No native occurrence is claimed; direct serializer controls in copied contexts qualify only those malformed-container paths without Godot.

Systematic nested-evidence correction: https://github.com/vnvalentin/project0/issues/849#issuecomment-5957639756. Consumed scenario/observation/history containers now receive explicit shape guards; every counter window/operation map must contain complete exact-integer zero counts (no boolean/floating coercion). Retained-log read errors are also explicit failures. Copied serializer controls characterize malformed evidence only; no native incident or final acceptance is invented.
