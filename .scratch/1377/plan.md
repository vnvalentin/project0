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

Set `M4_SOURCE_REVISION="$(git rev-parse HEAD)"` as shown in the validation plan;
the harness rejects absent or malformed source identity. Reports retain the
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
