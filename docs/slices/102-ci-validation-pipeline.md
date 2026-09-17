# Slice 102 - Full-stack CI validation gate
GitHub issue: #95

Status: **delivered**

Phase: 7 (Delivery workflow capabilities), advancing F-005.

## User outcome

Every push and pull request validates the whole repository, not just the Godot
suite: GDScript tests, delivery-record sync, the Python enrollment and operator
services, the wgnetstack bridge build, and the Windows launcher tests all gate
the branch automatically. A regression in a non-Godot component can no longer
reach `main` unnoticed because its suite only ran on one contributor's machine.

## Scope and non-goals

In scope: `.github/workflows/validation.yml` job expansion, and
`scripts/stage_launcher_payload_placeholders.sh` so the embed-dependent launcher
package compiles on a clean checkout.

Out of scope: deployment, release artifact publication, the Windows client
package build, self-hosted runners, and any change to test content. This slice
only changes what CI runs, never what the tests assert.

## Public seam

`.github/workflows/validation.yml` — jobs `godot`, `records`, `python`, `go`,
and `launcher`. Each job runs the same command a developer runs locally.

## Design notes

- The `godot` job is unchanged in behaviour and still uploads
  `build/validation/` telemetry on success and failure.
- `records` runs `scripts/check_record_sync.sh`, which previously had no CI
  enforcement at all and was only ever run by hand.
- `python` installs both service requirement files and runs the enrollment and
  operator suites together (183 tests).
- Every file in `native/windows_launcher` is `//go:build windows`, so those
  tests **cannot** compile on Linux. They run on `windows-latest` in the
  `launcher` job rather than being reduced to a `GOOS=windows` typecheck, so CI
  actually executes them.
- `native/wgnetstack` has no test files, so the `go` job builds it rather than
  claiming a test run it does not have.
- `main.go` declares `//go:embed payload/**` and `payload/` is intentionally
  gitignored, so a clean checkout cannot compile the launcher at all. The
  placeholder script satisfies the embed directive only; it refuses to overwrite
  a real payload, and both real packaging paths wipe and repopulate the
  directory, so a placeholder cannot be shipped.
- `concurrency` cancels superseded runs per ref to avoid queue pileup.

## Safety invariants

- No job deploys, publishes, or mutates any host; `permissions: contents: read`.
- The placeholder script is inert when a real payload is present.
- Placeholders are never produced by a packaging path, only by the test job.

## Acceptance scenarios

1. Given a push, when CI runs, then the GUT suite, record-sync, Python suites,
   wgnetstack build, and launcher tests all execute and gate the branch.
2. Given a clean checkout with no `payload/`, when the launcher job runs, then
   placeholders are staged and `go test ./...` compiles and passes.
3. Given a local checkout with a real payload, when the placeholder script runs,
   then it exits without modifying the payload.
4. Given a record-sync error, when CI runs, then the `records` job fails.

## Validation

Focused validation: workflow YAML parsed; placeholder path forced on a clean
payload directory and the launcher suite compiled and passed uncached; each new
job's command executed directly on the Linux host before being encoded in CI.

## Validation evidence

- `.github/workflows/validation.yml` parsed by PyYAML; jobs resolve to
  `godot`, `records`, `python`, `go`, `launcher` with the intended runners.
- `scripts/run_gut_validation.sh` on okami: 72 scripts, 493 tests, 493 passing,
  exit 0.
- `scripts/check_record_sync.sh` on okami: 0 errors, 6 pre-existing warnings,
  exit 0.
- `python -m pytest infra/enrollment/tests infra/operator/tests -q`: 183 passed.
- `go build ./...` in `native/wgnetstack`: succeeded (no test files present).
- Launcher: real payload moved aside, placeholder script staged the payload, and
  `go test -count=1 ./...` reported `ok project0/windows-launcher 0.818s`; the
  real payload was then restored.
- Guard check: with a real payload present the script printed
  "Real launcher payload present; leaving ... untouched" and exited 0.

## Root-cause learning

- Symptom: the first draft ran the launcher tests on `ubuntu-latest`.
- Public seam: `.github/workflows/validation.yml`, job `launcher`.
- Hypothesis: the launcher package is portable Go and compiles anywhere.
- Discriminating check: inspected build constraints on every file in
  `native/windows_launcher`.
- Confirmed root cause: `main.go`, `enrollment.go`, and `enrollment_test.go` are
  all `//go:build windows`, so a Linux job would report "build constraints
  exclude all Go files" or silently test nothing.
- Why existing tests missed it: the launcher suite had never run in CI; it was
  only ever run on a Windows workstation where the constraint is satisfied.
- Countermeasure: the job moved to `windows-latest`, and the slice records the
  constraint so the job is not "optimized" back onto Linux later.
- Remaining limitation: `native/wgnetstack` still has no tests, only a build.

## Record links

- Feature: [F-005](../FEATURE-LIST.md#f-005-automated-validation-gate-and-test-telemetry)
- Phase tracker: [PROJECT-TRACKER.md](../PROJECT-TRACKER.md#phase-7--delivery-workflow-capabilities)
- Registry: [SLICE-REGISTRY.md](SLICE-REGISTRY.md), reservation 102
