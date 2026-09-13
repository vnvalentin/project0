Type: research
Status: resolved

## Question

Investigate, against primary sources (Godot 4.3 official docs and engine
source), how a packaged Godot client can apply a downloaded patch and relaunch
itself on Windows without an installer.

Investigate:

- **Runtime pck loading**: how does
  `ProjectSettings.load_resource_pack(pack, replace_files, offset)` behave? Can
  a running client swap or override its own `Project0.pck` at runtime, or is a
  relaunch required to pick up new scripts/scenes? What are the constraints
  (load order, `res://` overriding of already-loaded resources, script/class
  cache)?
- **Main-pack override**: the `--main-pack` command-line option, and the
  same-name-pck-next-to-exe auto-load convention — how each selects which pack
  the client boots from.
- **Windows self-replace**: a running `Project0.exe` cannot overwrite itself in
  place. What are the supported patterns to replace the exe and/or pck and
  relaunch? (Download to a temp name; a small launcher/updater helper process; a
  batch/PowerShell hand-off; wait-for-exit-then-swap-then-relaunch.) What does
  Godot expose to drive it: `OS.create_process`, `OS.execute`,
  `OS.get_executable_path`, `DirAccess.rename` / `copy_absolute`?
- **Constraints**: any `--headless` / packaged-export limitations, and what
  `HTTPRequest` provides for downloading the patch bytes to disk.

Output: a recommended runtime-apply + relaunch mechanism for a portable
(no-installer) Windows client, with primary sources cited. Feeds the patch-unit
and the apply/restart/rollback tickets.

Findings file: `.scratch/client-auto-update/research/02-godot-pck-and-windows-self-replace.md`.

## Answer

Use **full-`Project0.pck` replacement with a mandatory relaunch**, not a runtime
pck-swap. A running client *can* mount another pck with
`ProjectSettings.load_resource_pack(pack, replace_files, offset)` and override
same-path files, but the engine source (`PackedData::add_path`,
`_load_resource_pack`) shows the override only changes the virtual-FS lookup for
**future** loads and re-registers global classes — it does **not** reload cached
resources or hot-swap the already-running scripts/scenes/autoloads. So an overlay
is only good for additive/lazy content; patching the core requires a restart.
Godot picks the boot pack deterministically (`ProjectSettings::_setup`):
`--main-pack` wins, else the same-name pck next to the exe (`Project0.exe` →
`Project0.pck`). On Windows the running exe and the open boot pck are file-locked,
and `res://` is read-only once a datapack is used (`DirAccessPack` mutators →
`ERR_UNAVAILABLE`), so the swap must happen on `user://`/native absolute paths
after the process exits. Recommended mechanism: `HTTPRequest.download_file` →
verify (fail-closed) → stage `*.new` → `OS.create_process` a detached updater →
`quit()` → updater waits for exit, `DirAccess.rename_absolute` swaps files
(keeping a `.bak` for rollback), then relaunches `OS.get_executable_path()`.
`OS.set_restart_on_exit` can cover relaunch only for an overlay-style pck-only
patch; the general exe+pck case needs the external updater.

Findings file: .scratch/client-auto-update/research/02-godot-pck-and-windows-self-replace.md
