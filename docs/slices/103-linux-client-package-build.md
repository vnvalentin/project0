# Slice 103 - Linux-hosted Windows client package build

Status: **delivered**

Phase: 7 (Delivery workflow capabilities), advancing F-002.

## User outcome

The shipped Windows client deliverable can be rebuilt from any commit by CI on
a Linux runner. Before this slice the package could only be produced on one
Windows workstation, using a DLL that had been built by hand in Slice 035 and
was never committed, against an export preset that was not in version control.
The released binary was therefore not reproducible by anyone else.

## Scope and non-goals

In scope: `scripts/package_client_linux.sh`, a `cgoarchive-windows` target in
`native/wgnetstack/Makefile`, tracking `export_presets.cfg`, and
`.github/workflows/release.yml` with the `client-package` job.

Out of scope: server deployment (Slice 104), publishing a GitHub Release,
code signing, changing what the export preset ships (recorded as
[DT-011](../TECHNICAL-DEBT-TRACKER.md#dt-011-client-export-filter-ships-the-test-framework-and-build-artifacts)),
and retiring the Windows PowerShell path, which still works.

## Public seam

`scripts/package_client_linux.sh [version]` produces, in `dist/current/`:
`Project0-client-windows-x64-<version>.zip`, `Project0-WAN-<version>.exe`, and
`deployment-manifest.json`. The `client-package` job runs the same script.

## Design notes

- The build cross-compiles in four stages: Go bridge to a Windows static
  c-archive via mingw-w64, GDExtension to a Windows DLL via scons + mingw g++,
  the Godot client via the 4.3 export templates, and the WAN launcher via
  `GOOS=windows go build`.
- `godot-cpp` is not a submodule and is not tracked, so the script clones it and
  checks out the pinned revision `d5cc777` — the revision the shipped DLL was
  built against — rather than silently building against whatever `4.3` points to.
- The Makefile had `cgoarchive` (Linux) but no Windows counterpart, even though
  `gdext/SConstruct` links `libwgnetstack.windows.a`. Slice 035 produced that
  file by hand. It is now a target so CI can reproduce it.
- The headless export emits GDExtension load errors for the Windows-only DLL and
  can exit nonzero while still writing complete artifacts, so the script treats
  the presence and non-emptiness of `Project0.exe`/`Project0.pck` as the
  pass/fail signal and records the exit code in the manifest.
- The job runs in `barichello/godot-ci:4.3`, which already carries the export
  templates, so no self-hosted runner is required for client packaging.

## Safety invariants

- The manifest records `source_commit`, `source_tree_dirty`, the godot-cpp
  revision, the export exit code, and a SHA256 per artifact.
- The script fails closed on any missing tool, with a message naming the fix.
- The release workflow keeps `permissions: contents: read` and only uploads
  build artifacts; it publishes nothing and touches no host.
- Payload staging wipes and repopulates `native/windows_launcher/payload`, so a
  test placeholder can never be embedded into a shipped launcher.

## Acceptance scenarios

1. Given a clean Linux checkout with the toolchain present, when the script
   runs, then the ZIP, launcher, and manifest are produced and exit is 0.
2. Given a missing tool, when the script runs, then it fails before any build
   work and names the tool and remedy.
3. Given the export preset is absent, then the export fails loudly rather than
   producing a partial package.
4. Given a tag push or manual dispatch, when the workflow runs, then the client
   artifacts are uploaded and retained.

## Validation

Focused validation: full script execution on the Linux host okami, with
artifact identity and manifest contents inspected. Workflow YAML parsed.

## Validation evidence

- `scripts/package_client_linux.sh 0.12.0` on okami: exit 0.
- Artifacts: `Project0-client-windows-x64-0.12.0.zip` (34,368,855 bytes,
  sha256 `c4442aff…f52`) and `Project0-WAN-0.12.0.exe` (101,357,568 bytes,
  sha256 `726474b8…b00`).
- ZIP contains exactly three entries: `Project0.exe`, `Project0.pck`, and
  `libwgnetstack_gdext.windows.template_release.x86_64.dll`.
- Manifest recorded `source_commit: 8a3c027`, `source_tree_dirty: false`,
  `godot_export_exit_code: 0`, `godot_cpp_ref: d5cc777…`.
- `.github/workflows/release.yml` parsed by PyYAML; job `client-package`.
- Toolchain confirmed on okami: godot 4.3.stable with 4.3.stable export
  templates, mingw-w64 gcc and g++, scons 4.11.1, Go 1.23.12, zip.

## Root-cause learning

- Symptom: the first cross-build run failed with "This project doesn't have an
  `export_presets.cfg` file at its root", despite the file existing locally.
- Public seam: `scripts/package_client_linux.sh`, Godot export step.
- Hypothesis: the export preset was present in the repository and the failure
  was a path or working-directory error in the script.
- Discriminating check: `git ls-files export_presets.cfg` (empty) and
  `git check-ignore -v export_presets.cfg`.
- Confirmed root cause: `.gitignore` line 4 ignored `export_presets.cfg`. The
  definition of what ships in the client package had never been committed, so
  no clean checkout — CI or a new contributor — could build the client at all.
- Why existing tests missed it: the only client build path ran on a workstation
  where the untracked file happened to exist; nothing ever built from a clean
  checkout.
- Countermeasure: the preset is now tracked, with a `.gitignore` comment stating
  why and under what condition it should be re-ignored. It was scanned for
  credentials first; it contains none.
- Remaining limitation: the preset's `exclude_filter` still ships the GUT addon
  and `build/` artifacts, recorded as
  [DT-011](../TECHNICAL-DEBT-TRACKER.md#dt-011-client-export-filter-ships-the-test-framework-and-build-artifacts).

## Record links

- Feature: [F-002](../FEATURE-LIST.md#f-002-portable-windows-client-package)
- Tech debt: [DT-011](../TECHNICAL-DEBT-TRACKER.md#dt-011-client-export-filter-ships-the-test-framework-and-build-artifacts)
- Phase tracker: [PROJECT-TRACKER.md](../PROJECT-TRACKER.md#phase-7--delivery-workflow-capabilities)
- Registry: [SLICE-REGISTRY.md](SLICE-REGISTRY.md), reservation 103
