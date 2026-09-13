Type: research finding
Status: complete
Date: 2026-09-13
Godot target: 4.3 (every claim verified against the Godot 4.3 class reference,
the 4.3 tutorials, and the `4.3-stable` engine source tree)
Scope: how a packaged, portable (no-installer) Godot 4.3 **Windows** client
(`Project0.exe` + a separate `Project0.pck`, `embed_pck=false`) can apply a
downloaded patch and relaunch itself. Resolves ticket
[02-research-godot-pck-and-windows-self-replace](../issues/02-research-godot-pck-and-windows-self-replace.md).
Does **not** decide the patch unit, transport, integrity model, or the
apply/restart/rollback design — it supplies the primary-source facts those
tickets need.

---

## Summary / Recommendation (TL;DR)

- **A running client can mount another `.pck` at runtime** with
  `ProjectSettings.load_resource_pack(pack, replace_files, offset)`, and with
  `replace_files = true` it **overrides files that share the same `res://`
  path** — but the override only changes the **virtual-filesystem lookup for
  future loads**. It does **not** reload resources already in memory, does not
  swap the already-running scripts/scenes/autoloads, and cannot change
  `project.godot`/autoload wiring that was applied at boot. So a runtime pck
  overlay is safe for **additive / lazily-loaded content** (mods, DLC, a
  not-yet-loaded scene), but **not** for patching the core the client is
  already executing.
- **Therefore, to apply a real client update a relaunch is mandatory.** The
  clean, engine-supported way to change the code/scenes the client boots from is
  to change *which pck it boots* and restart the process.
- **The boot pck is chosen deterministically**: `--main-pack <file>` wins if
  given; otherwise Godot auto-loads a pck with the **same basename as the
  executable, next to the executable** (`Project0.exe` → `Project0.pck`). This
  is exactly our distribution shape, so the natural patch unit is the whole
  `Project0.pck` (plus the `.exe` only when the engine/exe itself changes).
- **On Windows a running `.exe` cannot overwrite itself**, and the **boot pck is
  held open** by the running process, so neither can be replaced in place while
  the client runs. The supported pattern is **download-to-temp → hand off to a
  small detached updater → quit → updater waits for exit, swaps the files,
  relaunches**. Godot drives every step: `HTTPRequest.download_file`,
  `OS.create_process` (a child that *outlives* Godot), `OS.get_executable_path`,
  and absolute `DirAccess.rename_absolute` / `copy_absolute`.
- **`res://` is read-only at runtime once a datapack is in use.** All staging
  and swapping must happen on `user://` or native absolute paths
  (`ProjectSettings.globalize_path`), never on `res://`.

Recommended mechanism (detail in [§7](#7-recommendation)): **full-`.pck`
replacement, applied by a tiny external updater helper after the client exits,
then relaunch** — a `wait-for-exit → swap → relaunch` hand-off. A runtime
pck-swap-in-place is **not** viable for a mandatory whole-client version gate.

---

## 1. Runtime pck loading — `ProjectSettings.load_resource_pack`

### 1.1 Signature and documented behavior

`bool load_resource_pack(pack: String, replace_files: bool = true, offset: int = 0)`

> "Loads the contents of the .pck or .zip file specified by `pack` into the
> resource filesystem (`res://`). Returns `true` on success.
> **Note:** If a file from `pack` shares the same path as a file already in the
> resource filesystem, any attempts to load that file will use the file from
> `pack` unless `replace_files` is set to `false`.
> **Note:** The optional `offset` parameter can be used to specify the offset in
> bytes to the start of the resource pack. This is only supported for .pck
> files."
> — [class_projectsettings (4.3), `load_resource_pack`](https://docs.godotengine.org/en/4.3/classes/class_projectsettings.html#class-projectsettings-method-load-resource-pack)

The patch/DLC use case is explicitly documented: a PCK loaded this way "can fix
the content of a previously loaded PCK", and same-path files are replaced by
default — "it is also a way of creating patches for one's own game."
— [Exporting packs, patches, and mods (4.3)](https://docs.godotengine.org/en/4.3/tutorials/export/exporting_pcks.html)

### 1.2 What "override" actually does (engine source)

The binding calls `_load_resource_pack`, which forwards to
`PackedData::add_pack(...)` and, importantly, **only refreshes the global class
registry and UID cache** — it does not rebuild already-loaded resources:

```cpp
// core/config/project_settings.cpp — ProjectSettings::_load_resource_pack
bool ProjectSettings::_load_resource_pack(const String &p_pack, bool p_replace_files, int p_offset) {
    if (PackedData::get_singleton()->is_disabled()) { return false; }
    bool ok = PackedData::get_singleton()->add_pack(p_pack, p_replace_files, p_offset) == OK;
    if (!ok) { return false; }
    if (project_loaded) {
        // This pack may have declared new global classes (make sure they are picked up).
        refresh_global_class_list();
        // This pack may have defined new UIDs, make sure they are cached.
        ResourceUID::get_singleton()->load_from_cache(false);
    }
    // if data.pck is found, all directory access will be from here
    DirAccess::make_default<DirAccessPack>(DirAccess::ACCESS_RESOURCES);
    using_datapack = true;
    return true;
}
```
— [`core/config/project_settings.cpp` @ 4.3-stable](https://github.com/godotengine/godot/blob/4.3-stable/core/config/project_settings.cpp)

The override is a **map replacement in the virtual filesystem**. `add_pack` walks
its sources; the PCK source parses the directory and calls `add_path`, which only
overwrites the path→file entry when `replace_files` is set:

```cpp
// core/io/file_access_pack.cpp — PackedData::add_path
void PackedData::add_path(..., bool p_replace_files, bool p_encrypted) {
    String simplified_path = p_path.simplify_path();
    PathMD5 pmd5(simplified_path.md5_buffer());
    bool exists = files.has(pmd5);
    PackedFile pf; /* ...offset/size/md5/src... */
    if (!exists || p_replace_files) {
        files[pmd5] = pf;          // <-- override applies here, to the FS lookup table
    }
    if (!exists) { /* add to directory tree */ }
}
```
— [`core/io/file_access_pack.cpp` @ 4.3-stable](https://github.com/godotengine/godot/blob/4.3-stable/core/io/file_access_pack.cpp) (`PackedData::add_path`, `PackedSourcePCK::try_open_pack`)

**Consequence (the answer to the ticket's core question):** mounting a pck at
runtime changes what `FileAccess`/`ResourceLoader` return **for subsequent
loads of that path**. It does **not**:
- reload a resource already held in `ResourceCache` (a scene/script already
  loaded stays the old version until it is freed and loaded again);
- re-run or hot-swap the already-executing scripts, the current main scene, or
  autoloads that were instantiated at boot;
- re-read `project.godot` / autoload / main-scene settings (those are applied
  once, during `_setup`, before any script runs — see §2).

`refresh_global_class_list()` re-registers `class_name` entries from the freshly
mounted pck ("This is called after mounting a new PCK file to pick up class
changes.") into `ScriptServer`, so **newly referenced** global classes resolve
to the new paths — but this is a registry update, not a reload of instances or
of scripts already compiled into memory:

```cpp
// core/config/project_settings.cpp — ProjectSettings::refresh_global_class_list
// "This is called after mounting a new PCK file to pick up class changes."
```
— [`core/config/project_settings.cpp` @ 4.3-stable](https://github.com/godotengine/godot/blob/4.3-stable/core/config/project_settings.cpp)

**Net:** runtime pck overlay is a legitimate mechanism for **additive / not-yet-
loaded** content, and can *pre*-empt base files if the overlay is mounted early
(before those files are first loaded). It is **not** a reliable way to patch the
core of an already-running client — for that, restart with a new boot pck.

---

## 2. Boot pack selection — `--main-pack` and the exe-name auto-load

Both selection mechanisms in the ticket are confirmed by the authoritative boot
routine `ProjectSettings::_setup`, whose header comment enumerates the merit
order and whose body implements it:

```text
 *  - If --main-pack was passed by the user (`p_main_pack`), load it or fail.
 *  - Search for project PCKs automatically ... Steps:
 *    o Bundled PCK in the executable.
 *    o [macOS only] PCK with same basename as the binary in the .app resource dir.
 *    o PCK with same basename as the binary in the binary's directory. We handle both
 *      changing the extension to '.pck' (e.g. 'win_game.exe' -> 'win_game.pck') and
 *      appending '.pck' to the binary name (e.g. 'linux_game' -> 'linux_game.pck').
 *    o PCK with the same basename as the binary in the current working directory.
```
```cpp
if (!p_main_pack.is_empty()) {
    bool ok = _load_resource_pack(p_main_pack);
    ERR_FAIL_COND_V_MSG(!ok, ERR_CANT_OPEN, "Cannot open resource pack '" + p_main_pack + "'.");
    /* ...then load res://project.godot + optional override.cfg next to the pack... */
}
String exec_path = OS::get_singleton()->get_executable_path();
bool found = _load_resource_pack(exec_path);                       // embedded PCK
String exec_dir = exec_path.get_base_dir();
String exec_filename = exec_path.get_file();
String exec_basename = exec_filename.get_basename();
if (!found) {
    found = _load_resource_pack(exec_dir.path_join(exec_basename + ".pck")) ||  // Project0.exe -> Project0.pck
            _load_resource_pack(exec_dir.path_join(exec_filename + ".pck"));
}
```
— [`core/config/project_settings.cpp` @ 4.3-stable](https://github.com/godotengine/godot/blob/4.3-stable/core/config/project_settings.cpp) (`ProjectSettings::_setup`)

- **`--main-pack <file>`** — "Path to a pack (.pck) file to load." (available in
  release export templates)
  — [Command line tutorial (4.3), Run options](https://docs.godotengine.org/en/4.3/tutorials/editor/command_line_tutorial.html#command-line-reference)
- **Same-name-next-to-exe auto-load** — for `Project0.exe`, Godot loads
  `Project0.pck` from the exe's directory (it tries `<basename>.pck` and
  `<filename>.pck`). This is "the usual case when distributing a Godot game" per
  the source comment.

**Implication for the updater:** you never have to hot-swap inside the running
process to change what the client boots. Either (a) overwrite `Project0.pck`
in place *while the client is not running* and start `Project0.exe` normally
(auto-load picks it up), or (b) keep versioned pcks and relaunch with
`Project0.exe --main-pack <path-to-new.pck>`. Both require a **restart**.

---

## 3. `res://` is read-only at runtime (hard constraint)

Once a data pack is mounted, `res://` directory access is served by
`DirAccessPack`, whose mutating operations are all disabled:

```cpp
// core/io/file_access_pack.cpp — DirAccessPack
Error DirAccessPack::make_dir(String p_dir) { return ERR_UNAVAILABLE; }
Error DirAccessPack::rename(String, String) { return ERR_UNAVAILABLE; }
Error DirAccessPack::remove(String)         { return ERR_UNAVAILABLE; }
```
— [`core/io/file_access_pack.cpp` @ 4.3-stable](https://github.com/godotengine/godot/blob/4.3-stable/core/io/file_access_pack.cpp)

Writing pack-referenced files also fails (`FileAccessPack::store_*` → `ERR_FAIL`,
`open_internal` → `ERR_UNAVAILABLE`). In an exported build `res://` *is* the pck,
so it is not writable. **All patch bytes and all file swaps must therefore
target `user://` (writable) or native absolute paths obtained via
`ProjectSettings.globalize_path()`** — never `res://`.
- `user://` maps to a real, per-project OS directory
  (`%AppData%\Godot\app_userdata\<project>` on Windows) —
  [OS.get_user_data_dir (4.3)](https://docs.godotengine.org/en/4.3/classes/class_os.html#class-os-method-get-user-data-dir).
- To operate on the install folder (next to the exe), use
  `OS.get_executable_path().get_base_dir()` for the directory and the static
  absolute `DirAccess` variants (§5) with `chmod`/overwrite semantics.

---

## 4. Downloading the patch — `HTTPRequest.download_file`

`HTTPRequest` (a `Node`) can stream a response body straight to disk:

- `download_file: String = ""` — "The file to download into. Will output any
  received file into it."
- `download_chunk_size: int = 65536`, `body_size_limit: int = -1` (no limit),
  `timeout: float = 0.0` (no timeout — recommended for large downloads),
  `use_threads: bool = false`.
- Completion signal: `request_completed(result, response_code, headers, body)`.
- Relevant result codes: `RESULT_SUCCESS = 0`,
  `RESULT_DOWNLOAD_FILE_CANT_OPEN = 10`, `RESULT_DOWNLOAD_FILE_WRITE_ERROR = 11`,
  `RESULT_BODY_SIZE_LIMIT_EXCEEDED = 7`, `RESULT_TLS_HANDSHAKE_ERROR = 5`,
  `RESULT_TIMEOUT = 13`.
- gzip/deflate response bodies are auto-decompressed.
— [class_httprequest (4.3)](https://docs.godotengine.org/en/4.3/classes/class_httprequest.html)
(`download_file`, `download_chunk_size`, `body_size_limit`, `timeout`,
`request_completed`, enum `Result`)

Constraints for our use:
- The `download_file` path must be **writable** → `user://…` or a globalized
  absolute path (see §3). Writing to a `res://` path fails
  (`RESULT_DOWNLOAD_FILE_CANT_OPEN`).
- For a whole-pck download set `timeout = 0.0` and either leave
  `body_size_limit = -1` or set a generous bound; verify integrity **after**
  download and **before** staging (integrity model is ticket 03).
- TLS security caveats inherit from `HTTPClient`
  ([HTTPRequest description warning](https://docs.godotengine.org/en/4.3/classes/class_httprequest.html)).

---

## 5. Windows self-replace — supported patterns and the Godot APIs that drive them

**Why in-place replacement is impossible while running:**
- A running `Project0.exe` cannot overwrite its own image (Windows keeps the
  running executable file locked). *(Standard Windows file-sharing behavior —
  an OS constraint, not a Godot-doc claim; it is the stated premise of this
  ticket.)*
- The **boot `Project0.pck` is also held open** by the running process:
  `FileAccessPack` keeps a live handle (`f(FileAccess::open(pf.pack, READ))`)
  — [`core/io/file_access_pack.cpp`, `FileAccessPack` ctor @ 4.3-stable](https://github.com/godotengine/godot/blob/4.3-stable/core/io/file_access_pack.cpp).
  So even a *pck-only* replacement cannot happen in place while the client runs;
  the process must exit first to release the lock.

**Godot primitives available (all implemented on Windows):**

| API | Signature / behavior | Source |
| --- | --- | --- |
| Spawn a **detached** child that **outlives** Godot | `OS.create_process(path, arguments, open_console=false) -> int (pid)` — "Creates a new process that runs independently of Godot. **It will not terminate when Godot terminates.**" Returns pid or `-1`. Example: `OS.create_process(OS.get_executable_path(), [])`. | [OS.create_process (4.3)](https://docs.godotengine.org/en/4.3/classes/class_os.html#class-os-method-create-process) |
| Blocking run (helper *building* only, not the swap) | `OS.execute(path, arguments, output=[], read_stderr=false, open_console=false) -> int (exit code)` — "Executes the given process in a **blocking** way." Main thread blocks until it returns. | [OS.execute (4.3)](https://docs.godotengine.org/en/4.3/classes/class_os.html#class-os-method-execute) |
| Path of the running client (to relaunch / find install dir) | `OS.get_executable_path() -> String` | [OS.get_executable_path (4.3)](https://docs.godotengine.org/en/4.3/classes/class_os.html#class-os-method-get-executable-path) |
| Auto-relaunch the **same** exe on exit | `OS.set_restart_on_exit(restart, arguments=[])` — restarts on `SceneTree.quit`; "only effective on desktop platforms, and only when the project isn't started from the editor." | [OS.set_restart_on_exit (4.3)](https://docs.godotengine.org/en/4.3/classes/class_os.html#class-os-method-set-restart-on-exit) |
| Move/replace a file by absolute path | `DirAccess.rename_absolute(from, to)` (static) — "Renames (move)… If the destination … exists and is not access-protected, it will be overwritten." | [DirAccess.rename / rename_absolute (4.3)](https://docs.godotengine.org/en/4.3/classes/class_diraccess.html#class-diraccess-method-rename-absolute) |
| Copy a file by absolute path | `DirAccess.copy_absolute(from, to, chmod_flags=-1)` (static) | [DirAccess.copy_absolute (4.3)](https://docs.godotengine.org/en/4.3/classes/class_diraccess.html#class-diraccess-method-copy-absolute) |
| Check the client actually exited | `OS.is_process_running(pid)` / `OS.get_process_exit_code(pid)` | [OS.is_process_running (4.3)](https://docs.godotengine.org/en/4.3/classes/class_os.html#class-os-method-is-process-running) |

Note: `DirAccessPack.rename/remove` are the read-only `res://` versions and
return `ERR_UNAVAILABLE` (§3); the **static** `*_absolute` variants operate on
the real OS filesystem and are what the swap must use, with globalized paths.

**Supported self-replace patterns (all resolve to "exit first, then swap"):**

1. **External updater helper (general, handles exe *and* pck).** The running
   client downloads new artifacts to temp names, launches a small helper
   **detached** with `OS.create_process`, then quits. The helper waits for the
   client's pid to exit, `rename_absolute`s the `*.new` files over the
   originals, and relaunches `Project0.exe` via `OS.create_process`. The helper
   can be a tiny second executable, a bundled `--headless` Godot script, or a
   generated `.bat` / PowerShell script (e.g. a loop on `tasklist` /
   `Wait-Process`, then `move`, then `start`). `OS.execute` can *launch* such a
   detached `cmd /c start …` but should not itself perform the swap (it blocks
   the still-running client).
2. **`set_restart_on_exit` for a pck-only, overlay-style patch.** If the patch
   is delivered as a **separate overlay pck** loaded early at boot (so it
   overrides base files for all later loads — §1), the client never overwrites
   the locked boot pck; it stages the overlay to `user://`/install dir and calls
   `OS.set_restart_on_exit(true)` + `quit()` to relaunch the same exe, which then
   loads the overlay. This avoids a helper but (a) cannot patch the `.exe`,
   (b) requires very-early bootstrap code to mount the overlay before the
   overridden files are first loaded, and (c) still cannot *overwrite* the boot
   pck itself (only add overlays on top).

`OS.create_process` is the load-bearing primitive: it is the only one that
produces a child which **survives the client's own exit**, which is exactly what
a wait-for-exit-then-swap updater needs.

---

## 6. `--headless` and other packaged-export constraints

- `--headless` only forces `--display-driver headless --audio-driver Dummy`
  ("Useful for servers and with `--script`") —
  [Command line tutorial (4.3)](https://docs.godotengine.org/en/4.3/tutorials/editor/command_line_tutorial.html#command-line-reference).
  It does **not** restrict `OS.create_process`, `OS.execute`, or `DirAccess`, so
  a headless Godot **updater helper** is viable if you prefer reusing the same
  engine binary over shipping a `.bat`/PowerShell script. The player-facing
  client itself is windowed (not headless).
- `OS.create_process` / `execute` / `set_restart_on_exit` /
  `is_process_running` / `get_process_exit_code` are all documented as
  implemented on Windows. `set_restart_on_exit` is explicitly desktop-only and
  no-ops in the editor — fine for a shipped client, but it means this path
  cannot be exercised from an editor run.
- Reading interactive stdin in an exported Windows build needs the console
  wrapper; irrelevant here because the updater is non-interactive
  ([OS.read_string_from_stdin note, 4.3](https://docs.godotengine.org/en/4.3/classes/class_os.html#class-os-method-read-string-from-stdin)).

---

## 7. Recommendation

**Patch unit: replace the whole `Project0.pck`** (and the `.exe` only when the
engine/export template itself changes). This matches our distribution shape
(`embed_pck=false`, exe auto-loads same-name pck — §2) and sidesteps the
"already-loaded resources aren't reloaded" hazard of runtime overlays (§1). A
runtime **pck-swap-in-place is not viable** for a mandatory whole-client version
gate: the boot pck is file-locked while running (§5), `res://` is read-only
(§3), and an overlay cannot replace core scripts/scenes/autoloads already loaded
(§1).

**A relaunch is mandatory.** The engine only changes the code/scenes it runs by
choosing a boot pck at `_setup` time (§2); there is no supported hot-reload of
the running core.

**Concrete apply + relaunch mechanism (wait-for-exit → swap → relaunch):**

1. **Download** the new `Project0.pck` (and any new `Project0.exe`) with
   `HTTPRequest.download_file` to a **temp name** on a writable path — e.g.
   `<exe_dir>/Project0.pck.new` (via `OS.get_executable_path().get_base_dir()`)
   or `user://update/Project0.pck.new`. Set `timeout = 0.0` (§4).
2. **Verify integrity/authenticity before staging** (hash/signature — ticket
   03). Fail-closed: a bad artifact is deleted and never staged, per the map's
   fail-closed law.
3. **Launch a detached updater** with
   `OS.create_process(updater, [client_pid, src_new, dst_final, exe_to_relaunch])`
   (§5). The updater is a tiny helper (`.bat`/PowerShell, or a bundled
   `--headless` Godot script — §6).
4. **Quit** the client (`get_tree().quit()`), releasing the exe/pck file locks.
5. **Updater**: wait until `client_pid` has exited (`OS.is_process_running`, or
   `Wait-Process`/`tasklist` in a script), then `DirAccess.rename_absolute` each
   `*.new` over its target (overwrite semantics — §5), then relaunch
   `Project0.exe` (`OS.create_process`, or `start`). Because the auto-load
   convention (§2) is in effect, the relaunched exe boots the new
   `Project0.pck` with no extra flags; a versioned layout can instead relaunch
   with `--main-pack <new.pck>`.
6. **Rollback**: keep the previous `Project0.pck` (e.g. `Project0.pck.bak`)
   until the new build has connected/validated once; on updater failure or a
   post-swap failed launch, the updater restores the backup and relaunches the
   old build. (Full rollback design is ticket 08.)

**Feeds the downstream tickets:**
- *Patch unit* (05): favor whole-`.pck` replacement over a runtime overlay for a
  mandatory core update; overlays remain an option only for additive content.
- *Apply / restart / rollback* (08): the mechanism above (external updater +
  mandatory relaunch + keep-old-pck rollback) and its exact hand-off contract
  (`create_process` args, backup naming, verify-before-stage ordering).
- *Transport* (06): `HTTPRequest.download_file` streams to disk with size/timeout
  controls; must target writable paths; handles gzip; surfaces distinct
  can't-open / write-error / size-limit / TLS results to gate on.
- *Integrity* (03/07): verification must happen **after download, before stage**;
  `res://` immutability means the trusted baseline can't be tampered in place,
  but the *downloaded* artifact and the *swap* both happen on writable OS paths
  and are the attack surface to sign/verify.

---

## Sources

Primary — Godot 4.3 class reference:
- [ProjectSettings.load_resource_pack](https://docs.godotengine.org/en/4.3/classes/class_projectsettings.html#class-projectsettings-method-load-resource-pack)
- [OS.create_process](https://docs.godotengine.org/en/4.3/classes/class_os.html#class-os-method-create-process),
  [OS.execute](https://docs.godotengine.org/en/4.3/classes/class_os.html#class-os-method-execute),
  [OS.get_executable_path](https://docs.godotengine.org/en/4.3/classes/class_os.html#class-os-method-get-executable-path),
  [OS.set_restart_on_exit](https://docs.godotengine.org/en/4.3/classes/class_os.html#class-os-method-set-restart-on-exit),
  [OS.is_process_running](https://docs.godotengine.org/en/4.3/classes/class_os.html#class-os-method-is-process-running)
- [DirAccess.rename_absolute / copy_absolute](https://docs.godotengine.org/en/4.3/classes/class_diraccess.html#class-diraccess-method-rename-absolute)
- [HTTPRequest (download_file, timeout, Result enum)](https://docs.godotengine.org/en/4.3/classes/class_httprequest.html)

Primary — Godot 4.3 tutorials:
- [Command line tutorial (`--main-pack`, `--headless`, `--export-pack`)](https://docs.godotengine.org/en/4.3/tutorials/editor/command_line_tutorial.html)
- [Exporting packs, patches, and mods](https://docs.godotengine.org/en/4.3/tutorials/export/exporting_pcks.html)

Primary — engine source at tag `4.3-stable`:
- [`core/config/project_settings.cpp`](https://github.com/godotengine/godot/blob/4.3-stable/core/config/project_settings.cpp)
  — `_load_resource_pack`, `_setup` (boot pack merit order), `refresh_global_class_list`
- [`core/io/file_access_pack.cpp`](https://github.com/godotengine/godot/blob/4.3-stable/core/io/file_access_pack.cpp)
  — `PackedData::add_pack` / `add_path` (override semantics), `PackedSourcePCK::try_open_pack`,
  `FileAccessPack` (keeps the pack file open), `DirAccessPack` (read-only `res://`)

Not independently verified against a Godot primary source (flagged honestly):
- **The specific Windows file-locking behavior** (a running `.exe` and an open
  `.pck` cannot be overwritten in place) is standard Win32 share-mode behavior
  and the stated premise of the ticket, not a claim from the Godot docs. The
  Godot-verifiable half is that the process **holds the pack file open** while
  running (`FileAccessPack` ctor, source above), which is why the swap must wait
  for process exit. Exact Win32 sharing semantics were not re-derived from a
  Microsoft primary source here.
