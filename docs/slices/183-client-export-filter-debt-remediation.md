# Slice 183: client export filter debt remediation

GitHub issue: #421
Issue link: https://github.com/vnvalentin/project0/issues/421

## Traceability

- Feature: [F-002](../FEATURE-LIST.md#f-002-portable-windows-client-package)
- Primary goal: Goal A, trusted access and playable client
- Technical debt: [DT-011](../TECHNICAL-DEBT-TRACKER.md#dt-011-client-export-filter-ships-the-test-framework-and-build-artifacts)

## Outcome

A packaged Windows client excludes the GUT test framework, validation build
artifacts, and repository lock metadata while retaining the expected executable
and PCK and launching successfully.

## Public seam and invariants

- `export_presets.cfg` excludes `addons/gut/**`, `build/**`, and
  `skills-lock.json` from the Windows export.
- The export script creates the package through the existing Windows Desktop
  preset and does not mutate the source version contract after exit.
- The package contains `Project0.exe` and `Project0.pck`.
- Internal validation resources are absent from the package.
- The packaged client starts with exit code 0 under the bounded headless launch
  check.

## Non-goals

- No installer, signing, updater, or controller changes.
- No change to server, login, Canon, or gameplay behavior.
- No claim that first-install or live update/rollback evidence is complete; that
  remains the separate Goal A / F-037 gate.

## BDD

- Given a clean Windows Desktop export, when the package contents are inspected,
  then no `addons/gut/**`, `build/**`, or `skills-lock.json` path is present.
- Given the resulting package, when the packaged executable runs with
  `--headless --quit-after 2`, then it exits successfully without startup errors.

## Validation

- `bash scripts/export_windows_client.sh 0.12.0` passed after adding the
  PowerShell archive fallback.
- ZIP inspection found no `addons/gut/`, `build/`, or `skills-lock.json` paths.
- `Project0.exe` and `Project0.pck` were present.
- `Project0.exe --headless --quit-after 2` exited 0 with no startup errors.
- `bash scripts/check_record_sync.sh` passed with 0 errors and 6 known warnings.

## Rollback

Revert this slice to restore the prior export filter and archive fallback. No
runtime database, deployment, or permission change is introduced.

## Root-cause learning

- Symptom: DT-011 resources were included by the `all_resources` export filter,
  and the export script could not package on a Windows shell without `zip` or
  Python.
- Hypothesis: missing explicit export exclusions caused resource leakage, while
  the archive fallback assumed Python availability. The discriminating checks
  were ZIP content inspection and the available native PowerShell command.
- Root cause: the preset omitted the internal resource paths, and the script
  lacked a native Windows archive fallback.
- Countermeasure: add the three exclusions and use `Compress-Archive` before
  the Python fallback.
- Regression evidence: successful export, package-content inspection, and
  bounded packaged-client launch.
- Remaining limitation: full first-install and live update/rollback evidence
  remains tracked under Goal A and F-037.
