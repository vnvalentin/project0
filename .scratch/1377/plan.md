# M4.2 boundary and persistence evidence

Governing issue: https://github.com/vnvalentin/project0/issues/1377
Parent: #204. Milestone 4 / M4.2.
Implementation brief and SDD/BDD/TDD: https://github.com/vnvalentin/project0/issues/1377#issuecomment-5954622774

Linux-only isolated component evidence. No production behavior changes.
First increment proves rejected Canon requests make zero SQL INSERT/UPDATE attempts and preserve exact database/sidecar digests and raw rows. Positive writes and missing observations are deliberate detector controls.
User-approved scope evaluates supported unilateral, concurrent same-tick, and synchronous interaction boundary state. Repair/claim flags, persistent in-flight interactions, and native saved occupancy bitmasks are explicitly unsupported. Component reference and crossed worlds use real ServerPlayerState movement, SectorBoundaryDetector reloads, usable target references, EnvironmentalInteractionService and Canon reconstruction. M4.1 separately owns networked load/package evidence. Never report component checks as deployed-stack acceptance.

Owned files: tests/integration/test_m4_boundary_parity.gd and scripts/m4_canon_evidence.gd.
Rollback: close owned stores, remove only unique fixture files/sidecars, and discard owned XDG directory. Production paths and services are excluded.
Validation: machine-readable plan alongside this note; focused GUT then full GUT and record sync at final revision. Review remains required.

## Reproduction boundary

For direct focused GUT invocation, set
`M4_SOURCE_REVISION="$(git rev-parse HEAD)"` as shown in the validation plan;
the harness rejects absent or malformed source identity. The standard GUT
runner supplies the checkout HEAD automatically and rejects conflicting input.
The hosted runner supplies its qualified host SHA explicitly to the image. Reports retain the
source SHA and actual helper/test hashes. For exact-final evidence, use a clean
committed worktree. Hold `flock /tmp/project0-m4-01a0fcfa-validation.lock` across
setup, execution and cleanup, use a fresh owned `XDG_DATA_HOME`, and set
`DASHBOARD_RESULTS_DIR` inside that same temporary root. Remove that root in a
shell EXIT trap before releasing the lock. Logs, JUnit and case JSON remain in
the worktree as evidence. Never use the shared Godot data directory or publish
results to the live dashboard.

## Standard runner source identity follow-up

Records-first checkpoint: https://github.com/vnvalentin/project0/issues/1377#issuecomment-5956853608
User outcome: ordinary GUT commands produce source-bound M4 evidence without
requiring an undocumented environment override. Scope is Linux validation
commands only; no gameplay, schema, thresholds or production changes. The
unacceptable outcome is a report attributed to a different or malformed source.
Hypothesis: the standard runner omits the checkout SHA and the hosted runner's
explicit empty environment discards it. Cheapest discriminating check: execute
the public runner commands in an owned temporary Git checkout with substituted
external engine/container executables, observing their allowed source input.
These command seams are the assigned parent-approved test boundaries.

The standard runner must derive the checkout HEAD when Git metadata exists and
reject a conflicting supplied identity before engine launch. A source artifact
without Git metadata requires a supplied full 40-hex SHA. The hosted runner
qualifies the host checkout HEAD and passes it explicitly through env -i. Direct
M4 test invocation still refuses absent or invalid source identity. Tests create
only temporary Git repos and fake external executables; cleanup owns that root.
Rollback is reverting the runner changes and removing owned temporary fixtures.

## Root-cause learning: standard command source identity

Symptom: M4 parity requires a complete source SHA, but the standard GUT command
did not supply one, and hosted env -i removed ambient values. Public seam:
`scripts/run_gut_validation.sh` / `scripts/run_hosted_gut_container.sh`.
Hypothesis and discriminating check: substitute only the external engine and
container executable in an owned temporary Git checkout, then observe the
source given to those command boundaries. The initial ordinary runner control
failed (source absent); hosted propagation and refusal controls also failed.
Confirmed root cause: missing source qualification/propagation in both runners.
Existing focused tests missed this because their caller explicitly set the SHA.
Countermeasure: derive HEAD in a checkout, refuse malformed/conflicting supplied
identity before launch, and require complete host-provided identity for artifacts
without Git. Hosted qualification occurs before any Docker operation and is
passed through env -i. Direct parity missing/invalid identity checks remain.

Regression evidence at code revision
`3e7d3f20d863796d7cae2f9e3cd9c80d84df5cac`: seven public command controls passed,
22 existing CI routing controls passed, Bash syntax and record sync passed,
ownership plan/inventory passed. Reports are
`build/validation/m4-source-identity-final.json`,
`build/validation/m4-source-routing-final.json`, and
`build/validation/m4-source-inventory-final.json`. Temporary fixture roots are
removed by unittest cleanup. These are substituted command evidence; native
parity, full GUT and independent reviews remain separate gates.

## Final accepted-main integration and complete recipes

Records-first integration checkpoint:
https://github.com/vnvalentin/project0/issues/1377#issuecomment-5957487132
Accepted main `9702827c918cbf34719e11123e349c20af76fc1f` was integrated without
conflicts at `c654db80177853d66000cbffd2de8a6782ac2651`. Parity test/helper and
runner code are unchanged by that merge. Earlier native observations retain
their original source identities. Pending #1397 remains a final full-suite
dependency; integrate its accepted merge before qualifying final native evidence.

The JSON now declares the complete current unit/integration inventory and exact
focused/full shell recipes. Each holds the session flock through EXIT cleanup,
creates fresh owned XDG/config/cache/dashboard/test-state directories, binds
the source SHA and retains output at explicit paths. Focused output is captured
as `build/validation/m4-1377-focused/gut.{xml,log}`. Full GUT uses
`RESULT_DIR=build/validation/m4-1377-full` and retains XML/log/summary there.
Ownership preflight must pass before execution. A coordinated quiet window plus
external process-ancestry monitoring, engine-error scan, exact XML coverage and
all source-bound case verdicts/cleanup observations remain qualification gates.
A passing static command control is not native execution. Record-sync and
independent review remain required before merge or issue closure.
