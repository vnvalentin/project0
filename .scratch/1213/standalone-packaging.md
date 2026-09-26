# Standalone Windows Client Packaging

Governing issue: https://github.com/vnvalentin/project0/issues/1213
Issue-first checkpoint: https://github.com/vnvalentin/project0/issues/1213#issuecomment-5849368601
Parent feature: #551 (roadmap #318)
Milestone: 14 - Milestone 0: Solo Playable Foundation
Project #2 item 255626539: In Progress; see GitHub for current validation and dependency status
Outcome: C Authoritative content systems
Branch/worktree: `fix/1213-standalone-packaging` at `D:/code/project0-1213` (SETSUJOKU)

This ticket is a local planning aid only; #1213 and Project #2 remain the
delivery record.

## Root cause in this slice

`scripts/build_current_deployment.ps1` unconditionally requires Go, builds and
tests the launcher, installs rcedit through npm, and deletes `dist/`,
`native/windows_launcher/payload`, and shared `build/deployment-work` before
exporting. A standalone client package therefore cannot be produced without
launcher prerequisites, and a failed build destroys previous artifacts.

## Public seam

`pwsh -NoProfile -File scripts/build_current_deployment.ps1 -Version <x.y.z>`
produces `dist/standalone/<version>/` containing
`Project0-client-windows-x64-<version>.zip` and `deployment-manifest.json`
(full source commit, dirty flag, archive and EXE/PCK sizes and SHA-256).

## Invariants

- No Go, launcher build, launcher tests, or npm install on this path.
- Version is explicit; no default and no change to server required-version.
- Always a fresh Godot export from current source; no restamping old PCKs.
- Existing version output is refused, never overwritten; `dist/current` and the
  launcher payload are never touched.
- Only a unique owned staging directory is created and it is removed in
  `finally`; output is published by a single directory rename.
- Export, rcedit, git, and archive failures, and missing/empty EXE/PCK, fail
  closed.

## TDD

Focused command: `pwsh -NoProfile -File scripts/test_build_current_deployment.ps1`
(temporary fixture git repository, fake Godot/rcedit/go/launcher tools).
Red first, then minimal build-script change, then failure-path cases.

## Real export (0.14.0)

`dist/standalone/0.14.0/` ZIP 31534187 bytes, SHA-256 3F6BA948…6F7794; EXE
84214784 / 5157BB5E…C06C; PCK 566448 / 6038DCE8…DD16; source 6068e61 dirty.
Export exit 0 but logged the excluded-yet-enabled GUT editor plugin, ObjectDB
leaks, and `7 resources still in use at exit`. Hypothesis (unproven): editor
export-process teardown noise, not runtime. Recorded on #1213
(issuecomment-5849422519).

## Packaged-client verification

Command: `pwsh -NoProfile -File scripts/verify_standalone_package.ps1 -Version 0.14.0`
(probe `scripts/standalone_package_probe.gd`). Copies the ZIP into owned temp
state, checks the archive and extracted EXE/PCK size+SHA-256 against the manifest,
launches the extracted EXE (no editor, no `--main-pack`) headless with
isolated APPDATA/LOCALAPPDATA/TEMP, `PROJECT0_*` stripped, and backend knobs
pinned to 127.0.0.1/off. Bounded wait; only the owned PID is killed in
`finally`; temp root removed on every path. Evidence:
`build/validation/standalone-package-<version>-<run>/` (`result.json`,
`probe.json`, client stdout/stderr, isolated Godot user log). Any
`ERROR`/`SCRIPT ERROR`/leak line fails the run; nothing is suppressed.
`-FaultInjection ArchiveHash|PckHash` gives the focused fail-closed checks.

Results (2026-09-26, SETSUJOKU):
- ArchiveHash → exit 1, stage integrity, "Archive hash mismatch", client not
  launched, cleanup true (`…-5842d07c63cf43afb9ad64dded8d7fb1`).
- PckHash → exit 1, stage integrity, "Extracted Project0.pck hash mismatch",
  client not launched, cleanup true (`…-6ab934837be34a2d8113c9994b8a5de3`).
- Real package → **FAILED** (`…-98b18cd3922e46929f0487b360ca8cf6`), exit 1.
  Passed: hashes/sizes, PCK mounted by the real EXE, scripts compiled (.gdc, no
  source), CLIENT_BUILD_VERSION 0.14.0, receive_sector_blueprint 3 args
  (blueprint, ingress, trace; 2 defaults), safe-ingress readiness (valid,
  assembled, navigation ready, 2 path points), no network peer
  (OfflineMultiplayerPeer), no leak/resources-in-use lines at runtime (release
  template, 4.3-stable: weak evidence for the export-teardown hypothesis).
  Failed: unsafe ingress returns `fallback_unavailable`, not `fallback_selected`.

Diagnosis: `client/network_client.gd:1067` (344e0f8, #1019) loads
`res://server/starting_town_hub_fixture.gd`, but `server/**` is excluded by
`export_presets.cfg` (8a3c027) and by the build's robocopy staging. Every
packaged client lacks the deterministic spatial fallback; unit tests run from
source and cannot see this. The fixture depends only on `shared/`.
Second error, independent: `Parameter "m" is null`
(`servers/rendering/dummy/storage/mesh_storage.h:120`) is emitted when freeing
valid rendered sector geometry under the headless dummy renderer (isolated with
a safe-only diagnostic on the same EXE). Likely headless-only, not proven for the
windowed client. Not suppressed, so the strict gate stays red.

Not repaired: repair touches client/export files outside this handoff. Options
for decision: move the fixture (or a client-owned copy) under `shared/`/`client/`,
or carve the one file into the export include filter and staging. The headless
mesh-teardown error also needs a decision (free order, or a narrowly documented
allowance) before a packaged run can pass. The compiled contract and startup
passing is not gameplay acceptance.

## Follow-up outside this handoff

The earlier "Not repaired" paragraph records the first Claude handoff, not the
current implementation. Copilot took the standing direct fallback after the
repair handoff was permission-blocked for gh and edits. Checkpoint:
https://github.com/vnvalentin/project0/issues/1213#issuecomment-5849492089.

The single fallback resource is now included without other server code, and
the staged export exclusion is changed strictly. The focused regression went
red (export exit 12), then green; nine failure cases now pass, including
exit-zero export errors. Evidence is durable JSON; caller environment is
restored and paths with spaces are exercised. Setup is inside cleanup protection,
and export staging is removed before atomic package finalization.

## Root-cause learning and blocked evidence

The packaging omission was confirmed by the real PCK, not source tests. The
repaired `0.14.1` PCK contains compiled fallback code, version 0.14.1 and the
three-argument receiver; both safe and unsafe-ingress fallback complete
navigation with two-point paths. Server runtime is absent and no network peer
is opened. Source-only and fake-tool tests could not prove exported resources.

Build evidence: `build/validation/standalone-build-0.14.1-383d598c982f4d3283d1d7b2f578dde8/`.
Godot exits zero but reports ObjectDB leaks and seven resources still in use.
The build now exits one and keeps only a quarantined diagnostic package with
`release_eligible: false`; staging was removed. The exporter root cause remains
unresolved, not declared harmless.

Real Windows GL verification evidence:
`build/validation/standalone-package-0.14.1-4e9ba074474d49489ddac60ca84b266d/`.
All contract assertions pass but Area3D signal-disconnect diagnostics fail the
overall run. Immediate destruction, deferred destruction, and draining owned
area monitoring each left errors. Cleanup timing alone is not a confirmed root
cause. No errors were filtered. Stop this repair loop; the next owner must
diagnose the Godot overlap/lifecycle behavior before claiming a clean runtime.

No publication, installation, server required-version change, Canon mutation,
or production deployment occurred. Previous packages and original launcher edits
remain untouched. Full GUT is not run on Windows (its runner forbids it), and
this Windows branch has not been sent to Linux. A full validation plan respecting
that boundary, clean export/runtime checks, independent final review, and actual
compatible-server movement/LAN/WAN/player evidence remain gates before merge or
closing #1213. Rollback is this isolated branch; never delete previous packages
or user data. Next owner: Copilot/user on SETSUJOKU for a bounded lifecycle
diagnosis; server operator only after controlled admission is agreed.

## Lifecycle remediation (supersedes the diagnostic blocker above)

Checkpoint: https://github.com/vnvalentin/project0/issues/1213#issuecomment-5850516058.
The user authorized root-cause diagnosis and repair on SETSUJOKU.

- A minimal Area3D/StaticBody3D case, with no Project0 code, isolates the 4.3
  release-template active-monitor cleanup defect. Ordinary exits pass; clearing
  an overlapping monitor leaves native tree callbacks connected after the body
  map is cleared. The editor/debug controls pass. The same case passes on the
  verified 4.4.1 release template; the full 0.14.5 packaged runtime also passes.
- The exporter diagnostics are retained GDScript resources on older toolchains.
  Verbose logs identify translator/lookup, effective-mechanics/schema, and three
  Nakama scripts. Static-unload, import-first, text export and deferred factory
  probes were not fixes. Removing translator static caches reduced seven to five
  but was unnecessary with the qualified newer engine; all such product probes
  were restored, preserving caching, type contracts and SDK source.
- SHA-512-verified official Godot 4.7.2 exports the original application code
  cleanly. Tools/templates are isolated under build/tools; no global tool or
  server installation was changed. Build preflight now requires qualified 4.7.2
  stable and records the actual engine version. Ten failure cases pass, including
  rejection of 4.3 before export and retained rejection of exit-zero error logs.
- The official 4.7.2 release template restricts external path overrides. The old
  external-script probe did not run, so the same fixed probe now lives in the
  PCK as client/standalone_package_probe.gd. Only --verify-package user args select
  it before login setup; no arbitrary external code is loaded. It verifies the
  actual release engine and compiled resources, RPC arguments, safe/fallback
  readiness and no network peer, then exits. Existing evidence is not overwritten.
- Real 0.14.12 EXE/PCK verification passed; archive/PCK tampering was rejected
  before launch, and omitting the flag did not enter self-test mode. These are
  offline artifact checks, not authentication or gameplay acceptance. Final guards
  are to be validated on a clean committed-source build, not inferred from 0.14.12.

Independent read-only correctness/safety and specification reviews found no
actionable defects. Keep PR #1224 draft until the qualified engine is validated
against a controlled compatible server and the full applicable validation route,
normal movement/frontier/LAN/WAN checks and user approval are satisfied. #1213
must remain open with an explicit dependency handoff. No errors are suppressed,
no launcher work resumed, and nothing has been installed or published for players.
