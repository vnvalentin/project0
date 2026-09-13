# Slice 039 — Accounts and characters persistence repository

Status: **delivered** (server-only data layer; no RPC, no PBKDF2 hashing, no
client, no world entry).

Phase: 14 (Player accounts and characters). New feature: **F-030**.

Design basis: [player-accounts spec](../../.scratch/player-accounts/spec.md)
(complete, ticket 01/04/05/06 synthesis) and
[.scratch/player-accounts/handoff-039-accounts-characters-repository.md](../../.scratch/player-accounts/handoff-039-accounts-characters-repository.md)
(the bounded implementation brief for this slice). Consumes the Wave 4
[Slice 038](038-shared-sqlite-persistence-foundation.md) `SqliteStore` engine
seam (`server/sqlite_store.gd`, F-029) — **consumed unmodified**, per the
handoff's explicit "files to preserve" list.

## User outcome

The server durably creates, reads, selects, and soft-deletes Accounts and
their Characters through one server-only repository on the shared SQLite
engine — enforcing username uniqueness, global live Character-name
uniqueness, the 5-Character cap, and ownership — with every mutation atomic
and fail-closed. No RPC, no password hashing, no client, no world entry yet.

## Scope

**In scope (this slice):**

1. Shared value contracts (spec Implementation Slice 1), pure, versioned,
   bounded, fail-closed, no DB handle or secrets:
   - `shared/character_record.gd` (`class_name CharacterRecord`):
     `schema_version`, `character_id`, `account_id`, `display_name`,
     `cosmetic` (bounded typed dict), `created_at`, `last_played_at`,
     `deleted` (bool), `vessel_seam` (versioned, nullable; carries no Phase 12
     values). Also hosts the bounded rejection-reason String constants (auth:
     `UNSUPPORTED_VERSION`, `MALFORMED`, `BAD_CREDENTIALS`, `USERNAME_TAKEN`,
     `ACCOUNT_LOCKED`, `ALREADY_AUTHENTICATED`; character: `NAME_TAKEN`,
     `NAME_INVALID`, `CHARACTER_CAP_REACHED`, `NOT_OWNER`,
     `NO_SUCH_CHARACTER`, `ALREADY_DELETED`) and the `display_name` validator
     (`is_valid_display_name`).
   - `shared/account_handle.gd` (`class_name AccountHandle`): `account_id` +
     `username` only — never salt/hash.
2. Domain schema created through the `SqliteStore` seam
   (`AccountCharacterRepository.ensure_schema()`, idempotent
   `CREATE TABLE IF NOT EXISTS`):
   - `accounts(account_id PK, username UNIQUE NOT NULL, pbkdf2_salt,
     pbkdf2_hash, pbkdf2_iterations, created_at, schema_version)`
   - `characters(character_id PK, account_id NOT NULL REFERENCES accounts,
     display_name, cosmetic_json, vessel_json NULL, created_at,
     last_played_at, deleted INTEGER NOT NULL DEFAULT 0, schema_version)`
   - a partial unique index on `display_name WHERE deleted = 0` and an index
     on `account_id`.
3. `server/account_character_repository.gd` (`class_name
   AccountCharacterRepository`), server-only, wrapping a `SqliteStore`, with
   atomic, parameter-bound, fail-closed operations, each returning a bounded
   structured `Dictionary` (never raising): `create_account`,
   `find_account_by_username`, `create_character`, `list_characters`,
   `select_character`, `soft_delete_character`.
4. Test-first coverage: `tests/unit/test_character_record.gd` (pure
   contract/validation) and
   `tests/integration/test_account_character_repository.gd` (repository seam
   against a temporary `user://` database, unique per-test filename, cleaned
   up in `after_each`).
5. This delivery record, the F-030 feature record, and the synchronized
   `PROJECT-TRACKER.md`/`SLICE-REGISTRY.md` entries.

**Out of scope (explicit non-goals, unchanged from the handoff):**

- ENet RPC wiring (register/login/list/create/select/delete) — spec slices 3-4.
- PBKDF2 hashing/verification, `Crypto` credential compare, session objects —
  spec slice 3. This repository stores/returns credential bytes only; it
  never computes or compares them.
- Client screens (identity-gate replacement, character select/create) —
  spec slice 5.
- Character -> Player instantiation / `start_for_peer` — spec slice 6.
- Wiring the repository into `server/server_main.gd` boot — deferred to the
  first runtime consumer (the auth slice). The public seam here is the
  repository class, exercised directly by tests.
- `vessel_seam` / `vessel_json` values — only the nullable forward-compatible
  column exists; Phase 12 owns values.
- Character rename (not in v1, per spec).

## Reconciliation: name reservation across soft-delete

The handoff flagged one spec tension between ticket 06 (persistence design,
authoritative) and ticket 05 (character lifecycle prose):

- **Ticket 06** specifies the DDL explicitly: a **partial unique index on
  `display_name` WHERE `deleted = 0`** — uniqueness among *live* Characters
  only.
- **Ticket 05**'s prose says a soft-deleted Character's "name stays reserved
  to the Account."

These conflict: the DDL only blocks a second *live* row with the same name;
it does not reserve the name for the original owning Account after a soft
delete.

**Resolution (as implemented): ticket 06's explicit DDL is authoritative.**
`AccountCharacterRepository.ensure_schema()` creates exactly the partial
unique index ticket 06 specifies
(`idx_characters_display_name_live ... WHERE deleted = 0`), and
`create_character`'s uniqueness pre-check (`_live_name_exists`) only queries
`WHERE display_name = ? AND deleted = 0`. Consequences:

- A soft-deleted Character's row is **retained** (its `display_name` is still
  present in that historical row, supporting a possible future restore
  feature), but the name is **not locked** against other Accounts once the
  row is soft-deleted.
- **Any** Account — including a different one than the original owner — may
  create a new live Character with that freed name, since only the live-row
  namespace is unique.
- This is a deliberate deviation from ticket 05's prose, not an oversight.
  Strict cross-account name reservation across deletes, if ever wanted, is a
  separate, explicitly-scoped follow-up (e.g. a `retired_names` table keyed
  by `account_id` with its own TTL/eligibility rules) — not part of this
  slice.

`tests/integration/test_account_character_repository.gd`'s
`test_soft_delete_frees_cap_slot_and_frees_name_across_accounts` is the BDD
proof: after Account A soft-deletes "Rowan", Account **B** successfully
creates a live Character also named "Rowan", and a second soft-delete attempt
on A's original row reports `ALREADY_DELETED` (proving the row still exists
rather than `NO_SUCH_CHARACTER`).

## Public seam

- `shared/character_record.gd` (`CharacterRecord`, `SCHEMA_VERSION`,
  `REJECT_*` constants, `DISPLAY_NAME_MIN_LENGTH`/`MAX_LENGTH`,
  `MAX_CHARACTERS_PER_ACCOUNT`, `is_valid_display_name`).
- `shared/account_handle.gd` (`AccountHandle`).
- `server/account_character_repository.gd` (`AccountCharacterRepository`):
  - `_init(store: SqliteStore)`
  - `ensure_schema() -> Dictionary`
  - `create_account(username, pbkdf2_salt, pbkdf2_hash, pbkdf2_iterations) -> Dictionary`
    — `{"outcome": "ok", "account": AccountHandle}` or a bounded rejection
    (`MALFORMED`, `USERNAME_TAKEN`).
  - `find_account_by_username(username) -> Dictionary` — server-only stored
    credential row (`account_id`, `username`, `pbkdf2_salt`, `pbkdf2_hash`,
    `pbkdf2_iterations`) or `NO_SUCH_ACCOUNT`/`MALFORMED`. Never a client DTO.
  - `create_character(account_id, display_name, cosmetic) -> Dictionary` —
    `{"outcome": "ok", "character": CharacterRecord}` or a bounded rejection
    (`NAME_INVALID`, `NAME_TAKEN`, `CHARACTER_CAP_REACHED`, `NO_SUCH_ACCOUNT`,
    `MALFORMED`).
  - `list_characters(account_id) -> Dictionary` —
    `{"outcome": "ok", "characters": CharacterRecord[]}` (non-deleted only).
  - `select_character(account_id, character_id) -> Dictionary` — data
    operation only (no session binding, no world entry); sets
    `last_played_at`. Bounded rejections: `NOT_OWNER`, `NO_SUCH_CHARACTER`.
  - `soft_delete_character(account_id, character_id) -> Dictionary` — sets
    `deleted = 1` (row retained). Bounded rejections: `NOT_OWNER`,
    `NO_SUCH_CHARACTER`, `ALREADY_DELETED`.

No networking, UI, or gameplay boundary is crossed by this slice.

## BDD scenarios

Numbered to match the handoff's acceptance scenarios, all covered by
`tests/integration/test_account_character_repository.gd`:

1. **Duplicate username.** Given a fresh repo, `create_account("alice", ...)`
   succeeds; a second `create_account("alice", ...)` -> `USERNAME_TAKEN`, no
   second row.
2. **5-cap.** One Account creates 5 Characters (all succeed); the 6th ->
   `CHARACTER_CAP_REACHED`.
3. **Global live-name uniqueness.** Two Accounts both request display name
   "Rowan"; the first succeeds, the second -> `NAME_TAKEN`.
4. **Soft-delete frees cap and name (resolved tension).** A soft-deleted
   Character is absent from `list_characters`; its owner is back under the
   cap and can create again; a *different* Account may reuse the freed name;
   the soft-deleted row is retained (proven via a second `ALREADY_DELETED`
   response on the same id, not `NO_SUCH_CHARACTER`).
5. **Ownership.** Account B's `select_character`/`soft_delete_character` on
   Account A's Character -> `NOT_OWNER`; an unknown `character_id` ->
   `NO_SUCH_CHARACTER` for both operations.
6. **Injection safety + charset rejection.** A hostile string
   (`"Robert'); DROP TABLE characters; --"`) reaching the DB through a
   parameter-bound field that legitimately accepts free text (`cosmetic`,
   JSON-serialized) is stored/retrieved literally with no injected statement
   executing; separately, the same hostile string used as a `display_name` is
   rejected outright by the charset validator as `NAME_INVALID` (it can never
   reach the DB through that field).
7. **DB-layer defense in depth.** A duplicate live name forced past the
   app-layer pre-check (a direct insert simulating a race winner) is rejected
   by the partial unique index at the DB layer with a bounded query failure,
   and the repository's own `create_character` call for the same name
   surfaces the same bounded `NAME_TAKEN` reason — never a crash, never a
   partial row (the transaction rolls back atomically).
8. **Durability.** A created Account + Character both survive a store
   close + reopen (new `SqliteStore`/`AccountCharacterRepository` instances
   against the same `user://` file).
9. **`display_name` validation matrix.** `"ab"` (too short), a 21-character
   name, `" Rowan"`, `"Rowan "`, `"Ro  wan"`, and `"Ro$wan"` each ->
   `NAME_INVALID`; `"Rowan"` and `"Ro-wan_1"` are accepted — exercised both at
   the pure contract (`test_character_record.gd`) and through
   `create_character` (`test_account_character_repository.gd`).

Additionally covered: `select_character` refreshes `last_played_at` and the
persisted row reflects the same value on a subsequent `list_characters` read.

## TDD

- `tests/unit/test_character_record.gd` — 10 test functions: display-name
  validation (accept/reject matrix), the `CharacterRecord` field shape
  (including the "no Phase 12 vessel values" invariant), and
  `AccountHandle`'s field shape, including a `get_property_list()` assertion
  that it declares no credential field at all.
- `tests/integration/test_account_character_repository.gd` — 10 test
  functions, one per BDD scenario above (scenario 9's matrix and the
  `select_character` timestamp behavior are each one test). Each test uses a
  unique per-test `user://` filename (`before_each`) and deletes the
  DB/WAL/SHM/journal files afterward (`after_each`), mirroring
  `tests/integration/test_sqlite_store.gd`.

Both suites were written and run red (missing `shared`/`server` scripts)
before the implementation files existed, then green after
`shared/character_record.gd`, `shared/account_handle.gd`, and
`server/account_character_repository.gd` were added — satisfying the
handoff's test-first requirement.

## No-ADR rationale

No new ADR. This slice implements the already-accepted ticket 05/06 design
decisions (schema shape, atomicity, ownership rules) with one explicitly
documented reconciliation (see above) that the handoff itself named as the
default resolution, not a new architectural choice requiring its own record.

## Validation

All commands run from the repository root on this host (Godot
`4.3.stable.official.77dcf97d8`, x86_64 Linux).

1. **Reimport + full GUT run** (GUT does not sub-select one script in this
   project's configuration, per the Slice 038 precedent — the full suite is
   run and the two new suites are read from it):
   ```
   godot --headless --import
   godot --headless -s addons/gut/gut_cmdln.gd -gjunit_xml_file=/tmp/gut_039.xml -gdisable_colors -gexit
   ```
   Result: `tests/unit/test_character_record.gd` **10/10 passed**;
   `tests/integration/test_account_character_repository.gd` **10/10
   passed**. Full run: **30 scripts, 233 tests, 233 passing, 902 asserts,
   exit 0.**

2. **Full validation gate:**
   ```
   scripts/run_gut_validation.sh
   ```
   **Exit 0.** `build/validation/validation-summary.json`:
   `"status": "passed"`, `"scripts_expected": 30`, `"scripts_ran": 30`
   (DT-007 gate satisfied — no test script silently skipped; +2 scripts over
   Slice 038's baseline of 28, as expected).

Sample accept/reject outcomes observed in the suite: `create_account`
succeeds then rejects a duplicate username as `USERNAME_TAKEN`;
`create_character` accepts 5 Characters then rejects a 6th as
`CHARACTER_CAP_REACHED`; a second Account reusing a live name is rejected as
`NAME_TAKEN`; cross-account `select_character`/`soft_delete_character`
report `NOT_OWNER`; an unknown `character_id` reports `NO_SUCH_CHARACTER`; a
repeat `soft_delete_character` on an already-deleted row reports
`ALREADY_DELETED`; a hostile `display_name` is rejected as `NAME_INVALID`
before it ever reaches the DB.

## Known limitations

- No ENet RPC, no PBKDF2 computation/verification, no session objects, no
  client screens, and no `server_main.gd` boot wiring — all explicit
  non-goals per the handoff. The repository is exercised only by tests
  against a temporary database; nothing calls it at runtime yet.
- `vessel_seam`/`vessel_json` carry no values — the column exists only as a
  forward-compatible placeholder for Phase 12.
- No character rename (matches spec v1).
- Strict cross-account name reservation across soft-deletes is not
  implemented (see the Reconciliation section above) — a live-name-only
  namespace is the accepted behavior for this slice.
- `AccountCharacterRepository.ensure_schema()` must be called once by the
  caller after opening the `SqliteStore`; the repository does not call it
  automatically from `_init`, so a future boot-wiring slice must remember
  this step (mirrors `SqliteStore.open()`'s own explicit-call pattern).

## Related work

[PROJECT-TRACKER.md](../PROJECT-TRACKER.md#phase-work-index) (Phase 14),
[FEATURE-LIST.md](../FEATURE-LIST.md#f-030-accounts-and-characters-persistence-repository),
[Slice 038](038-shared-sqlite-persistence-foundation.md) (the consumed
`SqliteStore` engine foundation, F-029),
[player-accounts spec](../../.scratch/player-accounts/spec.md),
[player-accounts issue 05](../../.scratch/player-accounts/issues/05-character-data-model-and-lifecycle.md),
[player-accounts issue 06](../../.scratch/player-accounts/issues/06-account-character-persistence-design.md),
[handoff-039](../../.scratch/player-accounts/handoff-039-accounts-characters-repository.md).
