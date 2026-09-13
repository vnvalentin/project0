Type: research finding
Status: complete
Date: 2026-09-13
Godot target: 4.3 / 4.4 (verified against 4.3 docs, 4.3-stable engine source, current stable docs, godot-sqlite `master`/v4.9, and sqlite.org)
Scope: server-owned durable storage for Accounts + Characters on a home-hosted, headless, single-host Godot server, and how it relates to the future Phase 9 SQLite "Canon" store. Design decision input for [06 — persistence design](../issues/06-account-character-persistence-design.md); the storage-engine *build* is a downstream slice.

---

## Summary / Recommendation (TL;DR)

- **Converge on SQLite via the `godot-sqlite` GDExtension (2shady4u) as the single,
  shared, server-owned persistence mechanism** for both the Account/Character
  store and the future Canon world-state store. CLAUDE.md already commits Canon
  to a "server-owned SQLite database", and [the map](../map.md) intends the
  account/character engine to share Phase 9 infra — so standing up two different
  persistence stacks is the outcome to avoid. `godot-sqlite` is **MIT-licensed**,
  is a drop-in GDExtension (no engine recompile), tracks Godot 4.x (latest **v4.9**,
  built against Godot 4.7.1), and is **explicitly supported on a headless/dedicated
  server** ([README FAQ #4](https://github.com/2shady4u/godot-sqlite#4-is-this-plugin-compatible-with-a-godot-server-binary-how-to-set-it-up)).
- **SQLite gives the exact durability contract CLAUDE.md requires for free.**
  SQLite transactions "appear to be atomic even if the transaction is interrupted
  by an operating system crash or power failure"
  ([sqlite.org/atomiccommit.html §1](https://www.sqlite.org/atomiccommit.html)),
  which is precisely "atomic — no partial durable record" plus automatic
  restart-recovery (hot-journal rollback on next open). Wrap each multi-statement
  mutation (create account, create/delete character) in `BEGIN … COMMIT` / `ROLLBACK`.
- **Use parameterized queries only.** `godot-sqlite`'s `query_with_bindings()` /
  `query_with_named_bindings()` bind values so the parameters are sanitized,
  stopping SQL injection
  ([README](https://github.com/2shady4u/godot-sqlite#how-to-use)). Never build SQL
  by string concatenation with player-supplied usernames/character names.
- **Enable WAL + a schema version.** `db.query("PRAGMA journal_mode=WAL;")` (WAL
  is persistent across reconnects and reduces fsync pressure — [sqlite.org/wal.html §3.3](https://www.sqlite.org/wal.html))
  and `PRAGMA user_version` (or a `meta` table) to fail **closed** when the on-disk
  schema is newer/unsupported. The writable DB must live in `user://` (or an
  absolute server path), **not** `res://`, which is read-only in an export.
- **Zero-dependency interim (only if the account slice must ship before the
  GDExtension clears governance):** a single flat file written with the
  **write-temp-then-`DirAccess.rename` atomic-replace pattern** is viable and
  correct for torn-write protection, because Godot's `DirAccess.rename` maps
  directly to POSIX `rename(2)` (atomic same-filesystem replace). But native
  `FileAccess` is **not** atomic by default (see §1) and Godot exposes **no
  `fsync`** from GDScript, so this interim is weaker on durability and gives no
  referential integrity, transactions, or indexed queries. Since Canon is SQLite
  regardless, prefer vetting `godot-sqlite` once and sharing it over building a
  throwaway file store.
- **Governance:** adopting `godot-sqlite` is a new native binary dependency and
  therefore needs the documented safety + rollback note required by
  [AGENTS.md](../../../AGENTS.md). This is a one-time cost amortized across
  Accounts/Characters **and** Canon — the single biggest lever, and a human
  decision (see open questions).

---

## 1. Native option A — `FileAccess` (`store_var` / `store_string`)

`FileAccess` is the base file I/O class (`RefCounted`, headless-safe). It can
persist a small structured store two ways: **binary** via `store_var()` /
`get_var()` (engine-native Variant encoding, same as `@GlobalScope.var_to_bytes`),
or **text** via `store_string()` paired with `JSON`/`ConfigFile`.
Source: [class_fileaccess (4.3)](https://docs.godotengine.org/en/4.3/classes/class_fileaccess.html).

**Capabilities (documented):**

| Method | Behavior | Source |
| --- | --- | --- |
| `FileAccess.open(path, WRITE)` | Creates or **truncates** the file; cursor at start | [ModeFlags.WRITE (4.3)](https://docs.godotengine.org/en/4.3/classes/class_fileaccess.html#enum-fileaccess-modeflags) |
| `store_var(value, full_objects=false)` | Stores any Variant via the `var_to_bytes` encoder | [store_var (4.3)](https://docs.godotengine.org/en/4.3/classes/class_fileaccess.html#class-fileaccess-method-store-var) |
| `get_var(allow_objects=false)` | Reads the next Variant; **keep `allow_objects=false`** for untrusted data (object decoding can execute code) | [get_var (4.3)](https://docs.godotengine.org/en/4.3/classes/class_fileaccess.html#class-fileaccess-method-get-var) |
| `store_string(s)` | Appends UTF-8, no length/terminator | [store_string (4.3)](https://docs.godotengine.org/en/4.3/classes/class_fileaccess.html#class-fileaccess-method-store-string) |
| `flush()` | Writes the buffer to disk; "can be used to ensure the data is safe even if the project crashes" | [flush (4.3)](https://docs.godotengine.org/en/4.3/classes/class_fileaccess.html#class-fileaccess-method-flush) |

**Atomicity / corruption characteristics — the important part (verified in engine source):**

- **`WRITE` truncates the target the instant you open it.** `FileAccessUnix::open_internal`
  maps `WRITE` → `fopen(path, "wb")`. If the process crashes (or is `SIGKILL`ed,
  or loses power) after the truncating `open` but before the full content is
  written, the file is left **truncated / partially written** — the old record is
  already gone. Source: [`drivers/unix/file_access_unix.cpp`](https://github.com/godotengine/godot/blob/4.3-stable/drivers/unix/file_access_unix.cpp).
  The docs also warn that if the process is killed (e.g. stopped via F8) the file
  "won't be closed", recommending periodic `flush` — [class_fileaccess (4.3), Note](https://docs.godotengine.org/en/4.3/classes/class_fileaccess.html).

- **There is a safe-save (temp-file + rename) path, but it is OFF by default and
  not reachable from GDScript.** `open_internal` only writes to a `mkstemp`
  temporary file and `rename()`s it over the target on close **when
  `is_backup_save_enabled()` is true**:

  ```cpp
  // drivers/unix/file_access_unix.cpp
  if (is_backup_save_enabled() && (p_mode_flags == WRITE)) {
      save_path = path;
      path = path + "-XXXXXX";
      int fd = mkstemp(cs.ptrw());       // temp file in the same dir
      f = fdopen(fd, mode_string);
  } else {
      f = fopen(path.utf8().get_data(), mode_string);  // DIRECT, truncating write
  }
  // ...in _close(): if (!save_path.is_empty()) rename(temp, save_path);
  ```

  The backing flag defaults to **false** and is only toggled by the editor for
  resource saving — it is **not** a `FileAccess.open` parameter:

  ```cpp
  // core/io/file_access.cpp
  bool FileAccess::backup_save = false;
  ```

  Source: [`core/io/file_access.cpp`](https://github.com/godotengine/godot/blob/4.3-stable/core/io/file_access.cpp).
  **Conclusion: a normal runtime `FileAccess.open(path, FileAccess.WRITE)` from
  GDScript performs a direct, in-place, truncating write with no atomic-replace
  safety net.** You must implement the atomic pattern yourself (§4).

- **`flush()` / `close()` do not `fsync`.** `FileAccessUnix::flush()` calls
  `fflush(f)` and `_close()` calls `fclose(f)` — both push data to the OS page
  cache, **neither issues `fsync`**. Source:
  [`drivers/unix/file_access_unix.cpp`](https://github.com/godotengine/godot/blob/4.3-stable/drivers/unix/file_access_unix.cpp).
  So even a cleanly closed file can be lost on a power cut if the OS had not yet
  written the cache to disk. Godot exposes **no** `fsync` to GDScript — a hard
  durability ceiling for any pure-`FileAccess` design.

**Verdict:** fine for tiny data, but on its own it satisfies neither "no partial
durable record" (in-place truncation) nor strong durability (no fsync). It
becomes acceptable **only** wrapped in the atomic-replace pattern of §4, and even
then is inferior to SQLite for a multi-record relational store.

---

## 2. Native option B — `ConfigFile`

`ConfigFile` stores Variant values in INI-style `[section] key=value` text, with
`set_value` / `get_value` / `save(path)` / `load(path)` (plus AES `save_encrypted`).
Source: [class_configfile (4.3)](https://docs.godotengine.org/en/4.3/classes/class_configfile.html).

- **Same atomicity story as §1:** `ConfigFile.save()` writes through the same
  `FileAccess` layer, so it is a direct, non-atomic, in-place write — wrap it in
  the §4 pattern if used.
- **Structural limitations for an account/character store:** section and key
  names **cannot contain spaces** ("Anything after a space will be ignored"), and
  comments are lost on save — [class_configfile (4.3), Description](https://docs.godotengine.org/en/4.3/classes/class_configfile.html).
  Modeling N characters per account as sections is workable but awkward, and there
  is no querying, indexing, or referential integrity.
- **Best fit:** static server *config* (bind address, tuning file path), not a
  growing relational record set. The docs themselves frame it as "dedicated
  server configuration files".

---

## 3. Native option C — `JSON`

`JSON` converts Variants ↔ JSON strings: `JSON.stringify(data, indent="",
sort_keys=true, full_precision=false)` and the static `JSON.parse_string()` (or
instance `parse()` with `get_error_line()` / `get_error_message()`).
Source: [class_json (4.3)](https://docs.godotengine.org/en/4.3/classes/class_json.html).

- **No file I/O of its own** — it is a pure string codec; you pair it with
  `FileAccess.store_string()` + `FileAccess.get_as_text()`, so it inherits the §1
  non-atomic write behavior and needs the §4 pattern.
- **Gotcha — numbers become floats.** "converting a Variant to JSON text will
  convert all numerical values to `float` types" — [stringify Note (4.3)](https://docs.godotengine.org/en/4.3/classes/class_json.html#class-json-method-stringify).
  Integer IDs / timestamps round-trip as floats; store IDs as **strings** (opaque
  string ids match CLAUDE.md's "Versioned Data Contracts") or re-cast on load.
- **Gotcha — lenient parser.** Trailing commas are ignored, some invalid input is
  "cleansed" rather than rejected — [class_json (4.3), Note](https://docs.godotengine.org/en/4.3/classes/class_json.html).
  Acceptable for a file you wrote yourself, but do explicit schema validation on
  load (fail closed) rather than trusting shape.
- **Best fit as an interim:** a single human-readable `accounts.json` written
  atomically (§4) is the most legible zero-dependency option; still no
  transactions/integrity/indexing.

---

## 4. The atomic file-replace pattern (for any flat-file interim)

Because native writes are in-place and truncating (§1), the crash-safe idiom is
**write to a temp file, then atomically rename it over the target**:

1. `FileAccess.open("user://accounts.json.tmp", WRITE)` → write full content →
   `flush()` → `close()`.
2. `DirAccess.rename("user://accounts.json.tmp", "user://accounts.json")`.

**Why the rename is the atomic point (verified in source):** `DirAccess.rename`
maps directly to the POSIX `rename(2)` syscall —

```cpp
// drivers/unix/dir_access_unix.cpp
Error DirAccessUnix::rename(String p_path, String p_new_path) {
    ...
    return ::rename(p_path.utf8().get_data(), p_new_path.utf8().get_data()) == 0 ? OK : FAILED;
}
```

Source: [`drivers/unix/dir_access_unix.cpp`](https://github.com/godotengine/godot/blob/4.3-stable/drivers/unix/dir_access_unix.cpp).
The docs confirm the semantic: rename "will be overwritten" if the destination
exists — [DirAccess.rename (4.3)](https://docs.godotengine.org/en/4.3/classes/class_diraccess.html#class-diraccess-method-rename).
POSIX guarantees `rename()` is an **atomic replace on the same filesystem**, so a
concurrent/after-crash reader sees **either** the complete old file **or** the
complete new file — never a truncated one. Keep the temp file in the **same
directory** as the target (same filesystem) or the rename may fall back to a
non-atomic cross-device copy.

**Restart recovery:** on boot, if a leftover `*.tmp` exists, discard it — the
canonical file was never replaced, so the last committed state is intact.

**Residual limitation (be honest):** this protects against *torn writes*, not
against *power-loss durability*, because Godot issues no `fsync` (§1). The window
is small (data already handed to the OS cache) but nonzero. SQLite closes this
gap with real fsync barriers at commit (§6); pure GDScript cannot.

This is the best that native Godot offers for the CLAUDE.md "atomic — no partial
durable record" rule; it is sufficient for a tiny home-server account file, but
it does not scale to relational Accounts↔Characters with integrity constraints.

---

## 5. SQLite access — the `godot-sqlite` GDExtension (2shady4u)

**What it is / maturity / license.** A GDExtension C++ wrapper exposing SQLite3 to
Godot 4 "without any additional compilation or mucking about with build scripts."
**MIT-licensed**, 34 releases, **latest v4.9** (README: "Update to Godot 4.7.1";
the vendored `godot-cpp` submodule tracks `godot-4.7-stable`). The `master`
branch targets Godot 4.x (3.x lives on `godot-3.x`).
Source: [README](https://github.com/2shady4u/godot-sqlite#godot-sqlite),
[LICENSE — MIT](https://github.com/2shady4u/godot-sqlite/blob/master/LICENSE.md),
[releases](https://github.com/2shady4u/godot-sqlite/releases).

**Headless / dedicated-server support (directly relevant).** README FAQ #4 "Is
this plugin compatible with a Godot Server binary? How to set it up?" → yes,
follow the Godot dedicated-server export docs. **Caveat:** the CI Linux binary is
built on Ubuntu 22.04 (glibc 2.35); on an older server (glibc < 2.35) you must
recompile the Linux binary. Source:
[README FAQ #4](https://github.com/2shady4u/godot-sqlite#4-is-this-plugin-compatible-with-a-godot-server-binary-how-to-set-it-up).
(Our dev host runs Godot 4.3 on modern Linux, so the stock binary should load —
**validate on the actual server binary** before relying on it; see open questions.)

**Where the DB file lives.** A read+write DB **cannot** be packaged in the export
PCK (`res://` is read-only once exported); the writable DB must be in `user://`
or an absolute server path. The demo uses `user://my_database`. `res://`
databases are only for `read_only=true` static data via a custom VFS. Source:
[README "How to export?"](https://github.com/2shady4u/godot-sqlite#how-to-export)
and [demo `database.gd`](https://github.com/2shady4u/godot-sqlite/blob/master/demo/database.gd).

**API surface (from README + demo):**

| Capability | API | Notes |
| --- | --- | --- |
| Open / close | `open_db()`, `close_db()` (set `path` first) | Multiple concurrent connections allowed |
| Raw SQL | `query(sql)` | Runs arbitrary SQL incl. `PRAGMA`, `CREATE`, `BEGIN`/`COMMIT` (demo runs `query("PRAGMA encoding;")`, `CREATE TRIGGER/VIEW/INDEX`) |
| **Parameterized (injection-safe)** | `query_with_bindings(sql, Array)` / `query_with_named_bindings(sql, Dictionary)` | "stops any possible attempts at SQL data injection as the parameters are sanitized" |
| Helper CRUD | `create_table`, `drop_table`, `insert_row(s)`, `select_rows`, `update_rows`, `delete_rows` | Table schema as a Dictionary; supports `primary_key`, `auto_increment`, `unique`, `not_null`, `default`, `foreign_key` |
| Referential integrity | `foreign_keys = true` **before** `open_db()` | Enables SQLite FK enforcement |
| Results | `query_result` (by value, loop-safe), `last_insert_rowid` | |
| Blobs | `PackedByteArray` bound via bindings | For salt / derived-key bytes from research [02](02-godot-password-hashing.md) |
| Online backup | `backup_to(path)` / `restore_from(path)` | Useful for save/restore snapshots |

Source: [README "How to use?"](https://github.com/2shady4u/godot-sqlite#how-to-use),
[demo `database.gd`](https://github.com/2shady4u/godot-sqlite/blob/master/demo/database.gd).

**Transactions.** There are **no dedicated `begin()/commit()/rollback()` methods**;
issue them as raw SQL: `db.query("BEGIN TRANSACTION;")` … `db.query("COMMIT;")`
(or `db.query("ROLLBACK;")` on validation failure). The plugin also exposes
`get_autocommit()` (wraps `sqlite3_get_autocommit`), confirming transaction-state
awareness. This is the seam for CLAUDE.md's "commit … atomically" requirement:
wrap each account creation and each character create/delete in one transaction.
Source: [README (Methods)](https://github.com/2shady4u/godot-sqlite#how-to-use).

**WAL mode.** Not a first-class documented feature of the plugin, but reachable
the same way as any PRAGMA: `db.query("PRAGMA journal_mode=WAL;")`. The demo
proves raw PRAGMA works (`query("PRAGMA encoding;")`). **Validate at runtime** that
the pragma returns `"wal"` on this build/VFS (§6 notes the VFS shared-memory
requirement); treat "WAL enabled" as a checked fact, not an assumption.

**Not supported:** at-rest DB encryption ("Database encryption of any kind is not
supported … Nor are there any plans"). Not needed for this trust level; credential
material is already salted+hashed per research [02](02-godot-password-hashing.md).
Source: [README FAQ #6](https://github.com/2shady4u/godot-sqlite#6-does-this-plugin-support-some-kind-of-encryption).

**First-party alternative:** none. The Godot 4 class reference exposes **no**
GDScript `SQLite` class (Godot links an internal SQLite copy for editor UID/asset
caches, but it is not scriptable). The only routes are the `godot-sqlite`
GDExtension, a fork (e.g. an SQLCipher variant), or a custom module/GDExtension.
Source: [Godot class index (authoritative for the GDScript API)](https://docs.godotengine.org/en/stable/classes/index.html).

---

## 6. SQLite's own atomicity + WAL guarantees (owning source: sqlite.org)

**Atomic commit across crashes/power loss.** "SQLite has the important property
that transactions appear to be atomic even if the transaction is interrupted by
an operating system crash or power failure." In the default rollback-journal
mode, SQLite writes original pages to a `-journal` file, flushes it, then writes
the DB; the transaction **commits** when the journal is deleted; a crash mid-way
leaves a **hot journal** that the next process to open the DB automatically rolls
back. Source: [sqlite.org/atomiccommit.html §1, §3.11, §4.2](https://www.sqlite.org/atomiccommit.html).
This *is* the CLAUDE.md "atomic — no partial durable record" + automatic
restart-recovery contract, provided by the engine rather than hand-rolled.

- Durability depends on the default `PRAGMA synchronous=FULL` (SQLite fsyncs the
  journal and the DB at the critical points) — §3.7/§3.10 and §6.2.
- Multi-statement work is atomic as a unit inside `BEGIN … COMMIT`; a `ROLLBACK`
  (or crash) leaves **no** partial rows — matching "reject … no partial durable
  record."

**Write-Ahead Logging (WAL).** `PRAGMA journal_mode=WAL;` (since SQLite 3.7.0)
inverts the journal: readers use the original DB while the writer appends to a
`-wal` file; a commit is a WAL record. Benefits: faster, "readers do not block
writers and a writer does not block readers", fewer `fsync()`s. Key facts for us:

- **Persistent across reconnects** — set once, stays WAL until explicitly changed
  ([wal.html §3.3](https://www.sqlite.org/wal.html)). Good for a long-lived server DB.
- **Single host only** — "All processes using a database must be on the same host
  computer; WAL does not work over a network filesystem." Fine: our server is a
  single host ([wal.html §1](https://www.sqlite.org/wal.html)).
- Adds sidecar `-wal` and `-shm` files that must travel with the DB and require a
  VFS that supports shared memory (or `PRAGMA locking_mode=EXCLUSIVE` for a
  single-connection process) — [wal.html §4, §7, §8](https://www.sqlite.org/wal.html).
- With `synchronous=NORMAL` in WAL, the last transactions may roll back on power
  loss (integrity preserved, some durability traded); use `FULL` if every commit
  must survive a hard reboot — [wal.html §2.3](https://www.sqlite.org/wal.html).

**Schema versioning / fail-closed.** Use SQLite's built-in `PRAGMA user_version`
(a 32-bit integer stored in the DB header) or an explicit `meta(schema_version)`
row; on open, if the stored version is greater than the server's supported
version, **refuse to operate** (fail closed) rather than guessing — satisfying
CLAUDE.md's "fail closed on unsupported schema versions." (`user_version` is
standard SQLite, settable via `db.query("PRAGMA user_version=1;")`.)

---

## 7. Meeting CLAUDE.md's persistence rules — mechanism comparison

| Requirement (CLAUDE.md) | Flat file + `DirAccess.rename` (§4) | SQLite via `godot-sqlite` (§5–6) |
| --- | --- | --- |
| Atomic — no partial durable record | Whole-file swap only; torn-write safe, **no** fsync | Per-transaction atomic commit, crash/power-safe |
| Restart recovery | Discard leftover `.tmp` on boot | Automatic hot-journal / WAL recovery on open |
| Referential integrity (Account owns N Characters) | Manual, in-app | Native `FOREIGN KEY` (`foreign_keys=true`) |
| Concurrent/atomic multi-record change | Rewrite whole file each time | `BEGIN … COMMIT` around multiple statements |
| Injection-safe queries | N/A (no query layer) | `query_with_bindings` parameters sanitized |
| Fail closed on unsupported version | `schema_version` field check | `PRAGMA user_version` check |
| Server-only handle (shared/ never holds it) | `FileAccess` used only in `server/` | `SQLite` object instantiated only in `server/` |
| New-dependency governance cost | **none** | GDExtension binary → document safety + rollback |

Both can be made correct for a handful of accounts; **only SQLite** cleanly gives
transactions, integrity, indexed lookups, and real power-loss durability without
hand-rolling, and it is the mechanism Canon already requires.

---

## 8. Share one store with Canon, or keep separate? — verdict

**Share one mechanism (SQLite). Do not build a second, permanent persistence
subsystem.**

- **CLAUDE.md already fixes Canon on SQLite** ("frozen historical Canon only after
  a successful atomic insert into the server-owned SQLite database"; "Canon SQLite
  migrations, repositories, transactions … are server-only"). Choosing SQLite for
  Accounts/Characters means one storage technology, one dependency to vet, one set
  of transaction/atomicity idioms, and one backup story.
- **The map already intends this** — the account/character engine is "a downstream
  slice sharing infra with Phase 9 (Canon persistence)" ([map.md](../map.md)).
- **Separation of concerns is still preserved** without separate *tech*: keep
  Accounts/Characters and Canon as **distinct tables/domains** (or even distinct
  DB files) behind the **same** server-owned SQLite access layer. They have
  different lifecycles (player identity vs frozen world Canon) but identical
  durability needs, so different schemas — not different engines.
- **Interim divergence is acceptable only as a bridge, not a destination.** If the
  Account/Character slice must land before `godot-sqlite` clears governance, ship
  the §4 flat-file store *with a migration path* into the shared SQLite store when
  Phase 9 builds it — do not let the interim ossify into a parallel permanent
  store.

**Net:** adopt `godot-sqlite` as the shared server-owned engine; model Accounts,
Characters, and Canon as separate schemas within it; wrap every mutation in a
transaction; enable WAL + `user_version`; keep the DB in `user://`/an absolute
server path; keep the handle strictly inside `server/`.

---

## Version / license notes

- **`godot-sqlite`**: MIT license; latest **v4.9** (built against Godot 4.7.1),
  `master` compatible with Godot 4.x, GDExtension (no engine recompile). Verified
  today against the repo. For a Godot 4.3/4.4 client+server, use the matching
  release binary or recompile; **pin a specific release** and record it in the
  dependency/rollback note. Sources:
  [README](https://github.com/2shady4u/godot-sqlite#godot-sqlite),
  [releases](https://github.com/2shady4u/godot-sqlite/releases),
  [LICENSE](https://github.com/2shady4u/godot-sqlite/blob/master/LICENSE.md).
- **Native `FileAccess` / `DirAccess` / `ConfigFile` / `JSON`**: API is stable
  across Godot 4.x; the WRITE-truncates behavior, `backup_save=false` default, and
  `DirAccess.rename`→`::rename` mapping are unchanged in current `master`/source.
- **SQLite** atomic-commit and WAL semantics are engine-version properties of
  SQLite itself (WAL since 3.7.0), independent of Godot; note the WAL-reset bug is
  fixed in SQLite ≥ 3.51.3 and only affects multi-connection concurrent
  checkpointing — [wal.html §11](https://www.sqlite.org/wal.html).

---

## Primary sources

| # | Source (owner of the claim) | Used for |
| --- | --- | --- |
| 1 | [Godot 4.3 docs — `FileAccess`](https://docs.godotengine.org/en/4.3/classes/class_fileaccess.html) | `store_var`/`get_var`/`store_string`/`flush`; WRITE truncates; kill-does-not-close note |
| 2 | [godot 4.3-stable `drivers/unix/file_access_unix.cpp`](https://github.com/godotengine/godot/blob/4.3-stable/drivers/unix/file_access_unix.cpp) | WRITE→`fopen("wb")`; temp-file+`rename` only if `is_backup_save_enabled()`; `flush`=`fflush`, `_close`=`fclose` (no fsync) |
| 3 | [godot 4.3-stable `core/io/file_access.cpp`](https://github.com/godotengine/godot/blob/4.3-stable/core/io/file_access.cpp) | `bool FileAccess::backup_save = false;` (safe-save OFF by default); `store_var` uses `encode_variant` |
| 4 | [Godot 4.3 docs — `DirAccess`](https://docs.godotengine.org/en/4.3/classes/class_diraccess.html) | `rename` overwrites destination; `remove`, `copy` |
| 5 | [godot 4.3-stable `drivers/unix/dir_access_unix.cpp`](https://github.com/godotengine/godot/blob/4.3-stable/drivers/unix/dir_access_unix.cpp) | `DirAccess.rename` → POSIX `::rename` (atomic same-FS replace) |
| 6 | [Godot 4.3 docs — `ConfigFile`](https://docs.godotengine.org/en/4.3/classes/class_configfile.html) | INI store; save/load; no-spaces + comment-loss limits |
| 7 | [Godot 4.3 docs — `JSON`](https://docs.godotengine.org/en/4.3/classes/class_json.html) | `stringify`/`parse_string`; numbers→float; lenient parser |
| 8 | [godot-sqlite README](https://github.com/2shady4u/godot-sqlite) | GDExtension; Godot 4.x; MIT; headless/server FAQ; `query_with_bindings` injection-safe; `foreign_keys`; PRAGMA; export/`user://`; no encryption |
| 9 | [godot-sqlite releases](https://github.com/2shady4u/godot-sqlite/releases) / [LICENSE](https://github.com/2shady4u/godot-sqlite/blob/master/LICENSE.md) | v4.9 latest; MIT |
| 10 | [godot-sqlite demo `database.gd`](https://github.com/2shady4u/godot-sqlite/blob/master/demo/database.gd) | Raw `query()` PRAGMA works; `user://` persistent DB; FK demo |
| 11 | [sqlite.org — Atomic Commit](https://www.sqlite.org/atomiccommit.html) | Atomicity across crash/power loss; rollback journal; hot-journal recovery; `synchronous=FULL` |
| 12 | [sqlite.org — Write-Ahead Logging](https://www.sqlite.org/wal.html) | WAL via PRAGMA; persistent; single-host; `-wal`/`-shm`; synchronous tradeoff; WAL-reset bug fix ≥3.51.3 |
| 13 | [Godot class index](https://docs.godotengine.org/en/stable/classes/index.html) | No first-party GDScript `SQLite` class exists |

---

## Open questions for human decision

1. **Take the `godot-sqlite` dependency now, or ship the flat-file interim first?**
   The single biggest lever. Recommendation: vet + adopt `godot-sqlite` once and
   share with Canon; use the §4 flat-file store only if the Account/Character
   slice must land before the dependency clears governance. Either way, write the
   AGENTS.md safety + rollback note (pinned release, binary provenance, removal
   plan) before merging.
2. **Validate the plugin binary on the real headless server.** Confirm the stock
   Linux `v4.x` binary loads under `godot --headless` on this host's glibc, or
   recompile per README FAQ #4. Never claim runtime behavior without runtime
   evidence.
3. **WAL vs rollback journal + `synchronous` level.** Recommend `journal_mode=WAL`
   + `synchronous=FULL` for a durable single-host server; verify the WAL PRAGMA
   returns `"wal"` on this VFS, and decide `NORMAL` vs `FULL` against the
   durability-vs-latency budget.
4. **One DB file vs two (accounts/characters vs Canon).** Same engine either way;
   decide whether Canon and identity share one `.db` (simpler backup, cross-domain
   transactions possible) or separate files (cleaner lifecycle/retention
   boundaries). Note WAL atomicity is per-database-file across `ATTACH`.
5. **Schema-version mechanism.** `PRAGMA user_version` vs an explicit `meta` table;
   define the fail-closed behavior and the migration story before the first write.
