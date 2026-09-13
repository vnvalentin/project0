# Slice 038 — Shared server-owned SQLite persistence foundation

Status: **delivered** (engine seam only; no domain tables).

Phase: 9 (Canon persistence and world mutation) and 14 (Player accounts and
characters) — this is Wave 4 of the delivery roadmap
([PROJECT-TRACKER.md](../PROJECT-TRACKER.md#delivery-order-and-parallelization)):
"Shared SQLite persistence foundation (linchpin, build once)." It advances both
phases without belonging to either one's domain schema.

Design basis (already resolved, no new decisions made here):
[player-accounts issue 03](../../.scratch/player-accounts/issues/03-research-godot-persistence-sqlite.md)
(persistence research: recommends `godot-sqlite`, WAL, `PRAGMA user_version`
fail-closed, parameter-bound queries, one shared engine with Canon), and
[player-accounts issue 06](../../.scratch/player-accounts/issues/06-account-character-persistence-design.md)
(accepted decision: "Storage = one shared server-owned SQLite engine... same
mechanism Phase 9 Canon uses... this map decides the schema... the downstream
slice (shared with Phase 9 — the Wave 4 SQLite foundation) builds the
`godot-sqlite` integration, migrations, and repositories").

## User outcome

The server durably persists and reloads structured records across restarts
through one server-owned SQLite engine, with atomic transactions and
fail-closed schema versioning — the shared foundation both Accounts/Characters
(Phase 14) and Canon (Phase 9) will build their domain tables on.

## Scope

**In scope (this slice = the engine foundation only):**

- Vendor the `godot-sqlite` GDExtension (2shady4u, MIT) at a pinned release
  into `addons/godot-sqlite/`.
- `server/sqlite_store.gd` (`class_name SqliteStore`): opens a DB in
  `user://` (never `res://`), enables `PRAGMA journal_mode=WAL`, reads/writes
  `PRAGMA user_version` and fails closed on an unsupported version, exposes an
  atomic transaction helper (`BEGIN`/`COMMIT`, `ROLLBACK` on error), and a
  parameter-bound query API (`query_with_bindings` — never string-concatenated
  SQL). A minimal init creates the DB and sets `user_version = 1` on first
  open.

**Out of scope (later slices):**

- Account/Character tables and repositories (Phase 14).
- Canon tables, blueprint insert, and mutation transactions (Phase 9).
- Any client code — the handle and the DB file are server-only; clients never
  see either.
- Networking, gameplay, UI.

## Pinned dependency: `godot-sqlite`

- Source: <https://github.com/2shady4u/godot-sqlite>
- Pinned tag: **`v4.4`** ("Update to Godot 4.3, Add optional FTS5 Extension
  support", published 2024-08-18). The release notes state "Godot v4.3-stable,
  SQLite v3.46.1" as its dependency versions — an exact match for this
  repository's Godot 4.3.stable engine, so no compatibility gap is assumed.
- License: MIT (Piet Bronders & Jeroen De Geeter). Full text vendored at
  `addons/godot-sqlite/LICENSE.md`.
- What was vendored: `gdsqlite.gdextension` (trimmed to the `linux.debug.x86_64`
  / `linux.release.x86_64` library entries actually shipped — the upstream
  file also lists macOS/Windows/Android/iOS/Web entries this repository does
  not vendor binaries for, so those platform keys were removed rather than
  left dangling), `godot-sqlite.gd` and `plugin.cfg` (upstream tool-plugin
  shell, unmodified), `LICENSE.md`, and the two Linux x86_64 binaries
  (`libgdsqlite.linux.template_debug.x86_64.so`,
  `libgdsqlite.linux.template_release.x86_64.so`) from the release's
  `bin.zip`. Windows/other-platform binaries were intentionally not vendored —
  this slice's server target is Linux headless; a future slice adds Windows
  binaries only if a Windows-hosted server becomes a real target.
- **Dependency safety/rollback note** (per `AGENTS.md`'s "document safety and
  rollback implications" rule):
  - Safety: MIT license (no copyleft/attribution-burden concerns beyond
    keeping `LICENSE.md`); GDExtension (no engine source patch/recompile);
    binary is loaded only by the headless server process, never by `shared/`
    or `client/`; confirmed to load under `godot --headless` on this host
    (see Validation below) before being treated as load-bearing.
  - Rollback: remove `addons/godot-sqlite/` and `server/sqlite_store.gd`; no
    other file depends on this slice's code yet (no domain tables exist). If
    `godot-sqlite` ever fails to load in a future environment (different
    glibc/OS), the documented interim fallback is an atomic flat-file store
    (write-temp-then-`DirAccess.rename`, atomic via POSIX `rename(2)`) per
    ticket 03 — that is a separate future decision, not exercised by this
    slice, because the extension loaded successfully here.

## Public seam

- `server/sqlite_store.gd` (`class_name SqliteStore`):
  - `open(relative_path: String) -> Dictionary` — rejects `res://`; creates
    the DB under `user://` on first use; enables WAL; initializes
    `user_version = 1` on a fresh DB; fails closed
    (`OUTCOME_UNSUPPORTED_VERSION`) without mutating the file if an existing
    DB's `user_version` is not the one supported version.
  - `close() -> Dictionary`
  - `is_open() -> bool`
  - `get_user_version() -> int`
  - `transaction(body: Callable) -> Dictionary` — `BEGIN`; runs `body` (which
    must return `true`/`false`); `COMMIT` on `true` and no query failure,
    otherwise `ROLLBACK`. No partial durable record on any failure path.
  - `query_with_bindings(sql: String, bindings: Array) -> Dictionary` — the
    only entry point for SQL carrying variable/untrusted data; always
    parameter-bound.
  - `query(sql: String) -> Dictionary` — for DDL/PRAGMA statements with no
    variable data.
- `addons/godot-sqlite/` (vendored, pinned, MIT).

No domain tables, repositories, or schemas are introduced by this seam.

## BDD scenarios

1. **Fresh open.** Given a fresh `user://` dir, when the store opens, then the
   DB file is created, WAL journal mode is enabled, and `user_version` is 1.
2. **Durability across restart.** Given an open store, when a transaction
   inserts a row into a temp test table and commits, then after close+reopen
   the row is present.
3. **Atomic rollback.** Given an open store, when a transaction inserts a row
   then a later statement in the same transaction errors (a UNIQUE-constraint
   violation) before commit, then after reopen no partial row exists.
4. **Fail-closed version gate.** Given a DB whose `user_version` exceeds the
   one supported version, when the store opens, then it fails closed with a
   bounded `OUTCOME_UNSUPPORTED_VERSION` result and does not mutate the DB
   (verified by re-reading the on-disk `user_version` and confirming a
   pre-existing table survives untouched).
5. **Injection safety.** Given a parameter-bound query with a hostile string
   value (a name containing a quote and a semicolon, e.g.
   `"Robert'); DROP TABLE injection_probe; --"`), then it is stored and
   retrieved literally and no injected statement executes.

Additionally covered: opening a `res://` path is rejected outright (defense
for the "NEVER res://" invariant).

## TDD

`tests/integration/test_sqlite_store.gd` — 6 test functions, one per scenario
above (`test_open_rejects_res_path` covers the `res://` guard in addition to
the 5 BDD scenarios). Each test uses a unique per-test `user://` filename
(`before_each`) and deletes the DB/WAL/SHM/journal files afterward
(`after_each`) so the suite leaves no artifacts and tests cannot collide.

## Validation

All commands run from the repository root on this host (Godot
`4.3.stable.official.77dcf97d8`, x86_64 Linux, glibc 2.39).

1. **Headless extension-load proof** (ad hoc script, not committed —
   `sqlite_smoke_test.gd` was created under the project root, run, and
   deleted after the proof):
   ```
   godot --headless --path . --script sqlite_smoke_test.gd
   ```
   Output: `Opened database successfully (...)`, `opened=true`,
   `rows=[{ "id": 1, "name": "hello" }]`, `Closed database (...)`,
   `SMOKE_OK`. **Exit 0.** No load error, no missing-symbol error. (First
   attempt against a stale `.godot` import cache produced `Native class
   "SQLite" not found`; a `godot --headless --import` reimport — the same
   step `scripts/run_gut_validation.sh` already runs before GUT — resolved it.
   This is a one-time cache-population effect of adding a new GDExtension, not
   a load failure.)

2. **Focused GUT suite** (new test file only, run within the full suite since
   GUT's `-gtest` flag does not sub-select a single script in this project's
   configuration):
   ```
   godot --headless --import
   godot --headless -s addons/gut/gut_cmdln.gd -gjunit_xml_file=/tmp/gut3.xml -gdisable_colors -gexit
   ```
   Result: `tests/integration/test_sqlite_store.gd` — **6/6 passed**, 22
   assertions, 0.14s. Full run: **28 scripts, 213 tests, 213 passing, 830
   asserts, exit 0.**

3. **Full validation gate:**
   ```
   scripts/run_gut_validation.sh
   ```
   **Exit 0.** `build/validation/validation-summary.json`:
   `"status": "passed"`, `"scripts_expected": 28`, `"scripts_ran": 28` (DT-007
   gate satisfied — no test script silently skipped).

## Known limitations

- Linux x86_64 only; no Windows/macOS/Android/iOS/Web godot-sqlite binaries
  are vendored (the `.gdextension` file was trimmed accordingly). The server
  target is Linux headless, matching every other server-only seam in this
  repository.
- No domain schema exists yet — `SqliteStore` is inert until a consumer (the
  Phase 14 Account/Character slice or the Phase 9 Canon slice) opens a
  database and creates its own tables through `query`/`query_with_bindings`.
- `transaction()`'s `body` Callable contract (must return a `bool`) is
  enforced at the call site with a bounded rejection, not by GDScript's type
  system (`Callable` cannot declare a return type), so a future consumer must
  still be tested against a body that forgets to return `true`/`false`
  correctly — covered here only indirectly (the rollback scenario's body does
  return `false`/query-failure correctly).

## Related work

[PROJECT-TRACKER.md](../PROJECT-TRACKER.md#delivery-order-and-parallelization)
(Wave 4), [FEATURE-LIST.md](../FEATURE-LIST.md#f-029-shared-server-owned-sqlite-persistence-foundation),
[player-accounts spec](../../.scratch/player-accounts/spec.md),
[player-accounts issue 03](../../.scratch/player-accounts/issues/03-research-godot-persistence-sqlite.md),
[player-accounts issue 06](../../.scratch/player-accounts/issues/06-account-character-persistence-design.md).
