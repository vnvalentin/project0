# Slice 006: Portable Windows client package

Tracker context: Phase 6 — Windows client package; advances
[F-002](../FEATURE-LIST.md#f-002-portable-windows-client-package).
Planning ticket: [game-vision issue 12](../.scratch/game-vision/issues/12-windows-client-package.md).

## SDD

Goal: A tester can receive a versioned, portable Windows 64-bit ZIP
containing only the exported client runtime, extract it without the Godot
editor or the Linux source share, and launch it to the identity gate. The
tester configures the Linux server's LAN address using the same
`--server-host=<address>` CLI argument / `PROJECT0_SERVER_HOST` environment
variable mechanism the client already supports (Slice 003), with no
in-client settings UI and no source edit required. This slice adds only the
packaging boundary — reproducible export configuration, a build script, and
a tester guide — over the existing identity-gate/LAN-connection/
authoritative-movement/prediction-reconciliation behavior from Slices
001–005; it does not change any client or server runtime behavior.

Domain boundary: This slice owns exactly three new things: a Godot Windows
Desktop export preset (`export_presets.cfg`), a build script that runs the
export and produces a versioned ZIP (`scripts/export_windows_client.sh`),
and a tester-facing guide (`docs/windows-client-tester-guide.md`). It does
not add an installer, auto-update, code signing, authentication,
matchmaking, or Docker deployment, and it does not modify
`client/`, `server/`, or `shared/` runtime behavior — the preset's file list
is a packaging-time selection of pre-existing files, not a code change.

Public seam:
- `export_presets.cfg` — one preset, `"Windows Desktop"`
  (`platform="Windows Desktop"`, `binary_format/architecture="x86_64"`),
  `export_filter="selected_files"` with an explicit `[preset.0.files]` list
  containing only:
  - every existing `client/*.gd` and `client/*.tscn` file (the full client
    runtime: identity gate, gameplay scene, camera, connection status,
    network client, player, networked player, player identity),
  - `shared/network_config.gd` (the shared port/host-resolution constants
    the client depends on),
  - `project.godot` (engine/input/autoload configuration).

  It deliberately excludes `server/`, `scripts/`, and
  `shared/local_llm_client.gd` by never listing them — `export_filter`
  is an inclusion list, so anything not named is never packaged. No secrets,
  credentials, Ollama, or SQLite files exist in this repository to
  accidentally include (confirmed by inspection; see Validation).
- `scripts/export_windows_client.sh` — runs
  `godot --headless --path . --export-release "Windows Desktop" <path>`
  against the preset above, then stages the export output into a
  `Project0-client-windows-x64-<version>/` folder and zips it to
  `dist/Project0-client-windows-x64-<version>.zip`. Version defaults to
  `PROJECT0_CLIENT_VERSION` or `0.6.0`, overridable by a positional
  argument. Fails (`set -euo pipefail`, non-zero exit) rather than producing
  a partial or fake ZIP if the export step fails, e.g. when Windows export
  templates are not installed.
- `docs/windows-client-tester-guide.md` — tester-facing instructions for
  extraction, the two supported ways to set the server address (shortcut
  with `--server-host=`, or the `PROJECT0_SERVER_HOST` environment
  variable), LAN prerequisites, and the expected
  `Server: connected: player spawned` status plus common failure states.

Inputs/outputs: no new RPC, no new autoload, no new `NetworkConfig` constant,
no wire-protocol change. The only new artifact is the packaged ZIP itself
and its two build-time inputs (the preset and the build script). The
existing `--server-host=` / `PROJECT0_SERVER_HOST` resolution
(`shared/network_config.gd`, unchanged since Slice 003) is the only
configuration surface exposed to the tester.

Non-goals (explicit scope cut, per user direction and
[game-vision issue 12](../.scratch/game-vision/issues/12-windows-client-package.md)):
no MSI/Inno Setup installer, no auto-update, no code signing, no
authentication, no matchmaking, no internet deployment, no Linux server
packaging or Docker deployment, no Ollama/SQLite/world-generation work, and
no new gameplay. This slice packages existing behavior only.

Safety invariant: The exported package contains no server-only code
(`server/`), no test/build tooling (`scripts/`), and no local-LLM client
(`shared/local_llm_client.gd`) — enforced structurally by
`export_filter="selected_files"` naming only client-runtime files, not by a
post-hoc exclude pattern that could silently miss a newly added server file.
Any future file added under `server/` or `scripts/`, or any new file under
`client/`/`shared/` not added to `[preset.0.files]`, is excluded from the
package by default (fails closed) rather than included by default. No
credentials or secrets exist in this repository to leak (confirmed by
inspection below). The build script never reports success without a real
`godot --export-release` exit code of 0 backing it — if Windows export
templates are absent, the script fails loudly and produces no ZIP, matching
the Engineering Constitution's rule to never claim runtime behavior without
runtime evidence.

## BDD

### Normal path: tester extracts and connects over LAN

Given a tester receives `Project0-client-windows-x64-<version>.zip` and a
Linux server LAN address
When they extract the ZIP to a folder, launch `Project0.exe` with
`--server-host=<LAN IP>` (or the `PROJECT0_SERVER_HOST` environment
variable set), enter a display name at the identity gate, and select
**Enter**
Then the on-screen status reaches `Server: connected: player spawned`, and
the red locally-controlled Player and blue server-driven NetworkedPlayer
both render, exactly matching the already-validated Slice 002–005 client
behavior — this slice changes none of it.

### Highest-risk: package must not leak server-only or dev-only files

Given the `"Windows Desktop"` preset's `[preset.0.files]` list
When the preset is inspected or a real export is produced
Then no file under `server/`, no file under `scripts/`, and no
`shared/local_llm_client.gd` appears in the packaged file list or resulting
`.pck` contents — packaging is inclusion-based (only named client-runtime
files are ever considered), so a new server-only file added later is
excluded by default rather than requiring a maintainer to remember to add it
to an exclude list.

### Safety: export failure must never produce a fake or partial package

Given the Windows export templates are not installed (this sandbox's actual
state)
When `scripts/export_windows_client.sh` is run
Then `godot --export-release` exits non-zero, the script exits non-zero
(`set -euo pipefail`), and no `dist/Project0-client-windows-x64-<version>.zip`
file is created — the script never zips a partial or missing export
directory into a ZIP that would look successful.

## TDD evidence

No GDScript test framework is installed yet
([DT-002](../TECHNICAL-DEBT-TRACKER.md#dt-002-no-automated-gdscript-test-framework),
unchanged from Slices 001–005), and this slice adds no new GDScript
behavior to test — it is a packaging-configuration and tooling slice. The
public seam is exercised directly rather than through a GDScript smoke test:

1. **Preset file-list inspection** (highest-risk BDD scenario): read
   `export_presets.cfg`'s `[preset.0.files]` list and confirmed by direct
   `grep` that it contains no `server/`, no `scripts/`, and no
   `shared/local_llm_client.gd` entry, and that no credentials/secrets exist
   anywhere in the repository to leak.
2. **Preset syntax validity**: `godot --headless --path . --editor --quit`
   with `export_presets.cfg` present opens and closes the project cleanly
   (exit 0), and a real `godot --export-release "Windows Desktop"` invocation
   parses the preset far enough to resolve the platform and check for
   Windows export templates — i.e. Godot accepted the preset's syntax and
   option keys and reached the template-lookup step, rather than rejecting
   the file as malformed.
3. **Fail-closed export behavior** (safety BDD scenario): ran
   `scripts/export_windows_client.sh 0.6.0` in this sandbox (which has no
   Windows export templates installed) and confirmed it exited non-zero with
   no ZIP produced — see Validation for the exact output.
4. **Regression**: all five existing headless smoke tests
   (`test_identity_gate_and_movement.gd`, `test_client_server_connection.gd`,
   `test_lan_config.gd`, `test_authoritative_movement.gd`,
   `test_prediction_reconciliation.gd`) were re-run after adding
   `export_presets.cfg` and confirmed unchanged (ALL PASS, exit 0), proving
   the packaging-only change does not alter any client/server runtime
   behavior.

## ADR decision

No new ADR. This slice adds a build/export configuration and a
tester-facing document; it introduces no new architectural, security, or
persistence boundary and does not change which side owns the authoritative
position (unchanged from [ADR 0001](../adr/0001-client-side-authority-for-first-slice.md)
and Slice 004/005). The packaging inclusion-list approach (fail-closed by
omission) is documented above as a safety invariant rather than a
standalone ADR, matching how Slice 003 documented its safety posture inline.

## Validation

Run from the repository root (`/data/code/project0`):

- `godot --headless --path . --editor --quit`: PASS, exit 0 — confirms the
  project, including the new `export_presets.cfg`, opens and closes cleanly
  under the editor codepath with no import, parse, or preset-configuration
  errors.
- File-list inspection (highest-risk BDD scenario):
  ```
  grep -o 'path="res://[^"]*"' client/*.tscn
  grep -rl "server/\|local_llm_client" client/ shared/network_config.gd
  ```
  confirmed no client `.tscn` references anything under `server/` and no
  client/shared file referenced by the preset mentions `local_llm_client`.
  The preset's `[preset.0.files]` list was read directly and contains
  exactly: every `client/*.gd`/`client/*.tscn` file, `shared/network_config.gd`,
  and `project.godot` — no `server/`, no `scripts/`, no
  `shared/local_llm_client.gd`. A repository-wide search found no
  credentials, tokens, or database files to accidentally include.
- `bash scripts/export_windows_client.sh 0.6.0`: **FAILS, exit 1**, as
  expected in this sandbox — output:
  ```
  ERROR: Cannot export project with preset "Windows Desktop" due to configuration errors:
  No export template found at the expected path:
  /home/vic/.local/share/godot/export_templates/4.3.stable/windows_debug_x86_64.exe
  No export template found at the expected path:
  /home/vic/.local/share/godot/export_templates/4.3.stable/windows_release_x86_64.exe
  ERROR: Project export for preset "Windows Desktop" failed.
  ```
  This confirms the preset's syntax, platform name, and file selection are
  all valid — Godot parsed the config and reached the template-lookup step —
  and that the only blocker is the absence of the Godot 4.3 Windows export
  templates in this Linux sandbox (`~/.local/share/godot/export_templates/`
  is empty; no `.tpz` template package exists anywhere on this system,
  confirmed by a full-filesystem search). No ZIP was produced; the script
  correctly failed closed rather than fabricating a package. **Actual
  artifact generation requires either running this export on a machine with
  the Godot 4.3 Windows export templates installed, or installing those
  templates in this sandbox first** (e.g. via the Godot editor's
  Export Templates Manager, or downloading
  `Godot_v4.3-stable_export_templates.tpz` and extracting it to
  `~/.local/share/godot/export_templates/4.3.stable/`).
- `godot --headless --path . -s scripts/test_identity_gate_and_movement.gd`
  (Slice 001 regression): **ALL PASS**, exit 0.
- `godot --headless --path . -s scripts/test_client_server_connection.gd`
  (Slice 002 regression): **ALL PASS**, exit 0.
- `godot --headless --path . -s scripts/test_lan_config.gd` (Slice 003
  regression): **ALL PASS**, exit 0.
- `godot --headless --path . -s scripts/test_authoritative_movement.gd`
  (Slice 004 regression): **ALL PASS**, exit 0.
- `godot --headless --path . -s scripts/test_prediction_reconciliation.gd`
  (Slice 005 regression, 14 assertions): **ALL PASS**, exit 0.

  All five regression runs were repeated after `export_presets.cfg` was
  added and confirmed identical to their pre-slice baseline (also captured
  above before any change was made), proving this packaging-only slice made
  no client/server behavior change.

### Completion evidence: Windows package exported and LAN-tested

The user exported the Windows client successfully after correcting the export
preset to remove the invalid custom debug template and disable executable PCK
embedding. The resulting portable client was launched outside the Godot editor
and outside the Linux source share, connected to the Linux server over LAN, and
reached `Server: connected: player spawned`. The package consists of the
exported executable and adjacent PCK/runtime files required by Godot.

The remaining product work is not packaging correctness; it is future release
hardening such as code signing, an installer, and auto-update, all outside this
slice's scope.
