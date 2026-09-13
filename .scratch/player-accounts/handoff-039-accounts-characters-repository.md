# Handoff — Slice 039: Accounts & characters persistence repository

Filled-in [handoff template](../../docs/templates/claude-code-handoff-template.md)
by Copilot (orchestration/review layer) for implementation by Claude Code CLI.
Governing decision: [player-accounts spec](spec.md) (complete) +
[issue 06](issues/06-account-character-persistence-design.md) (persistence
design). Foundation gate is closed. Consumes the Wave 4 SQLite engine
([Slice 038](../../docs/slices/038-shared-sqlite-persistence-foundation.md),
`server/sqlite_store.gd`, F-029).

## User outcome

The server durably creates, reads, selects, and soft-deletes **Accounts** and
their **Characters** through one server-only repository on the shared SQLite
engine — enforcing username uniqueness, global live Character-name uniqueness,
the 5-Character cap, and ownership — with every mutation atomic and fail-closed.
No RPC, no password hashing, no client, no world entry yet.

## Scope

- **In scope:**
  1. **Shared value contracts** (spec Implementation Slice 1, the minimum this
     repository's seam needs), pure/versioned/bounded/fail-closed, no DB handle
     or secrets, in the `shared/combat_contracts.gd` /
     `shared/sector_blueprint_schema.gd` style:
     - `shared/character_record.gd` (`class_name CharacterRecord`):
       `schema_version`, `character_id`, `account_id`, `display_name`,
       `cosmetic` (bounded typed dict), `created_at`, `last_played_at`,
       `deleted` (bool), `vessel_seam` (versioned, nullable; **no Phase 12
       values**).
     - `shared/account_handle.gd` (`class_name AccountHandle`): `account_id` +
       `username` only — **never** salt/hash.
     - Bounded **rejection enums** (auth: `UNSUPPORTED_VERSION`, `MALFORMED`,
       `BAD_CREDENTIALS`, `USERNAME_TAKEN`, `ACCOUNT_LOCKED` (reserved),
       `ALREADY_AUTHENTICATED`; character: `NAME_TAKEN`, `NAME_INVALID`,
       `CHARACTER_CAP_REACHED`, `NOT_OWNER`, `NO_SUCH_CHARACTER`,
       `ALREADY_DELETED`). Place in `shared/` (own file or on the contracts).
     - `display_name` **validation**: length 3–20, charset `[A-Za-z0-9 _-]`, no
       leading/trailing/double spaces; unknown enum ⇒ reject; all numbers
       finite/bounded.
  2. **Domain schema** created through the `SqliteStore` seam (idempotent
     `CREATE TABLE IF NOT EXISTS`), owned by the repository (e.g.
     `ensure_schema()`):
     - `accounts(account_id PK, username UNIQUE NOT NULL, pbkdf2_salt,
       pbkdf2_hash, pbkdf2_iterations, created_at, schema_version)`
     - `characters(character_id PK, account_id NOT NULL REFERENCES accounts,
       display_name, cosmetic_json, vessel_json NULL, created_at,
       last_played_at, deleted INTEGER NOT NULL DEFAULT 0, schema_version)`
     - a **partial unique index on `display_name` WHERE deleted = 0** and an
       index on `account_id`.
  3. **`server/account_character_repository.gd`**
     (`class_name AccountCharacterRepository`), **server-only**, wrapping a
     `SqliteStore`, with atomic, parameter-bound, fail-closed operations, each
     returning a bounded structured `Dictionary` (never raising):
     - `create_account(username, pbkdf2_salt, pbkdf2_hash, pbkdf2_iterations)`
       → `AccountHandle` | `USERNAME_TAKEN`/`MALFORMED`. Server assigns opaque
       `account_id` + `created_at`. One `BEGIN`/`COMMIT`. **Stores the
       credential bytes it is given; never computes PBKDF2.**
     - `find_account_by_username(username)` → stored credential row (server-only;
       for the later auth slice to verify) | `NO_SUCH_*`. Never a client DTO.
     - `create_character(account_id, display_name, cosmetic)` →
       `CharacterRecord` | `NAME_INVALID`/`NAME_TAKEN`/`CHARACTER_CAP_REACHED`/
       account-missing. Validates name, global live-name uniqueness, 5-cap,
       account existence; assigns opaque `character_id` + timestamps. One
       `BEGIN`/`COMMIT`.
     - `list_characters(account_id)` → `CharacterRecord[]` (non-deleted; client
       DTOs).
     - `select_character(account_id, character_id)` → `CharacterRecord` |
       `NOT_OWNER`/`NO_SUCH_CHARACTER`. Sets `last_played_at`. One
       `BEGIN`/`COMMIT`. (**Data operation only** — session binding + world
       entry are later slices.)
     - `soft_delete_character(account_id, character_id)` → ack |
       `NOT_OWNER`/`NO_SUCH_CHARACTER`/`ALREADY_DELETED`. Sets `deleted=1`
       (row retained). One `BEGIN`/`COMMIT`.
  4. **Tests (test-first):** `tests/unit/test_character_record.gd` (pure
     contract/validation) and
     `tests/integration/test_account_character_repository.gd` (repository seam
     against a temp `user://` DB, unique per-test filename, cleaned up in
     `after_each` like `tests/integration/test_sqlite_store.gd`).
  5. **Delivery records** (see gates below).

- **Out of scope (explicit non-goals):**
  - ENet RPC wiring (register/login/list/create/select/delete) — spec slices 3–4.
  - PBKDF2 hashing/verification, `Crypto` credential compare, session objects —
    spec slice 3. The repository stores/returns credential bytes only.
  - Client screens (identity-gate replacement, character select/create) — slice 5.
  - Character → Player instantiation / `start_for_peer` — slice 6.
  - Wiring the repository into `server/server_main.gd` boot — deferred to the
    first runtime consumer (the auth slice). The public seam here is the
    repository class, exercised directly by tests.
  - `vessel_seam` / `vessel_json` values — carry the nullable forward-compatible
    column only (Phase 12 owns values).
  - Character rename (not in v1).

## Repository context

- Governing ticket: [spec.md](spec.md),
  [issue 06](issues/06-account-character-persistence-design.md),
  [issue 05](issues/05-character-data-model-and-lifecycle.md),
  [issue 01](issues/01-domain-model-account-character-user-player.md).
- Primary phase / slice: **Phase 14** / **Slice 039** (reserve in
  [SLICE-REGISTRY.md](../../docs/slices/SLICE-REGISTRY.md)); **new feature
  F-030**.
- Files Claude may create/change: `shared/character_record.gd`,
  `shared/account_handle.gd`, an optional `shared/` enums file,
  `server/account_character_repository.gd`, `tests/unit/test_character_record.gd`,
  `tests/integration/test_account_character_repository.gd`,
  `docs/slices/039-accounts-characters-repository.md`, `docs/FEATURE-LIST.md`,
  `docs/PROJECT-TRACKER.md`, `docs/slices/SLICE-REGISTRY.md`. `CONTEXT.md` only
  if a term genuinely needs adding (Account/Character already present).
- Files to preserve: everything else — especially `server/sqlite_store.gd`
  (consume, do **not** modify), `server/server_main.gd`, all `client/*`, and
  other slices' code/tests.

## Public seam

`AccountCharacterRepository` (server-only) methods above, plus the pure
`CharacterRecord` / `AccountHandle` contracts and their validation. Exercised by
GUT tests against a temporary `user://` SQLite database. No networking, UI, or
gameplay boundary is crossed by this slice.

## Safety invariants

- **Server-only:** `shared/` and `client/` never reference
  `AccountCharacterRepository`, `SqliteStore`, or the DB handle. `shared/`
  contracts hold no DB handle and no secrets.
- **Parameter-bound only:** every statement carrying data goes through
  `SqliteStore.query_with_bindings` — no string-concatenated SQL. Injection-safe.
- **Atomic:** every mutating op is one `BEGIN`/`COMMIT` via
  `SqliteStore.transaction`; no partial durable record on any failure path.
- **Fail-closed:** malformed / oversized / unknown-enum input rejected with a
  bounded reason; an unsupported `user_version` refuses to open (inherited from
  `SqliteStore`).
- **Opaque server-generated ids** (never client-supplied).
- **Defense in depth for name uniqueness:** enforce it at BOTH the app layer
  (pre-check) and the DB layer (partial unique index) so a race can't
  double-insert; the DB-layer violation must surface as a bounded `NAME_TAKEN`,
  not a crash.
- **Bounded telemetry** (per CLAUDE.md "Telemetry And Andon Signals") on
  accept/reject with the reason and no secrets/PII (never log password
  material).

## Known spec tension to resolve and document

Ticket 06 (the authoritative persistence-design decision) specifies a **partial
unique index on `display_name` WHERE deleted = 0** — i.e. uniqueness among
**live** Characters only. Ticket 05 prose says a soft-deleted "name stays
reserved to the Account." These conflict. **Resolution (default):** follow
ticket 06's explicit DDL as authoritative — the live-name namespace is globally
unique; a soft-deleted row is **retained** (history / possible future restore)
but does not lock the name against other Accounts. Document this reconciliation
in the slice record. Strict cross-account reservation across deletes, if ever
wanted, is a separate documented follow-up, not this slice.

## Acceptance scenarios (write the failing tests first)

1. Given a fresh repo, when `create_account("alice", …)`, then an
   `AccountHandle` is returned; a second `create_account("alice", …)` →
   `USERNAME_TAKEN` and no second row.
2. Given one account, when it creates 5 characters, then all succeed; the 6th →
   `CHARACTER_CAP_REACHED`.
3. Given two accounts, when both request display name `"Rowan"`, then the first
   succeeds and the second → `NAME_TAKEN` (global live uniqueness).
4. Given a soft-deleted character, then it is absent from `list_characters`, its
   owner is back under the cap and can create again, and (per the resolved
   tension) another account may reuse the freed name; the soft-deleted row is
   retained.
5. Given account B, when it `select_character`/`soft_delete_character` on account
   A's character, then `NOT_OWNER`; an unknown `character_id` → `NO_SUCH_CHARACTER`.
6. Given a hostile value reaching the DB through a parameter-bound insert
   (a string with a quote and `;`), then it is stored/retrieved literally and no
   injected statement runs (mirror Slice 038 scenario 5). Note `display_name`
   charset validation rejects such characters, so probe injection through a
   field that legitimately reaches the DB, and separately assert the charset
   validator rejects a hostile `display_name` (`NAME_INVALID`).
7. Given a duplicate name that slips past the app pre-check, when the DB partial
   unique index rejects it inside the transaction, then no partial row is left
   and the result is a bounded `NAME_TAKEN` (atomic rollback).
8. Given a created account+character, when the store closes and reopens, then
   both are still present (durability across restart).
9. `display_name` validation: `"ab"` (too short), a 21-char name, `" Rowan"`,
   `"Rowan "`, `"Ro  wan"`, and `"Ro$wan"` each → `NAME_INVALID`; `"Rowan"`,
   `"Ro-wan_1"` accepted.

## Validation

Run from the repository root and report exit codes + counts:

1. Reimport + focused GUT run (GUT can't sub-select one script in this project,
   per the Slice 038 note — run the full suite and read the two new suites):
   ```
   godot --headless --import
   godot --headless -s addons/gut/gut_cmdln.gd -gjunit_xml_file=/tmp/gut_039.xml -gdisable_colors -gexit
   ```
   Expected: `tests/unit/test_character_record.gd` and
   `tests/integration/test_account_character_repository.gd` both green.
2. Full validation gate:
   ```
   scripts/run_gut_validation.sh
   ```
   Expected: **exit 0**; `build/validation/validation-summary.json`
   `"status": "passed"` with `scripts_expected == scripts_ran` (DT-007 gate — no
   script silently skipped). Baseline before this slice: 28 scripts / 213 tests;
   expect **+2 scripts**.

## Delivery gates (satisfy BEFORE implementation, verify AFTER)

1. Reserve **Slice 039** and **feature F-030** in
   [SLICE-REGISTRY.md](../../docs/slices/SLICE-REGISTRY.md).
2. Create `docs/slices/039-accounts-characters-repository.md` with SDD, BDD,
   TDD, an explicit no-ADR rationale (or an ADR if a real cross-cutting decision
   is made), validation results, and related work — mirror Slice 038's record.
3. Create the **F-030** feature record in `docs/FEATURE-LIST.md` (In Progress)
   and **atomically sync all 4 sections of `docs/PROJECT-TRACKER.md`**: Phase 14
   is already `in-progress`; add F-030 to the Phase 14 work index with its badge,
   recompute the percentage, set the Phase 14 **Current slice** pointer to 039,
   add Slice 039 to the Implementation slice index, and update the Work queue.
4. **Test-first:** commit the failing public-seam tests conceptually first
   (red → green → refactor). Do **not** `git commit`.
5. **Jidoka:** stop on any unexpected failure and report; do not proceed past a
   red gate.

## Return report

Report: files changed; exact commands run and their exit codes; behavior
observed (suite counts, sample accept/reject outcomes); the name-reservation
reconciliation as implemented; known limitations (no boot wiring, no
RPC/auth/client); and any scope deviation for Copilot review.
