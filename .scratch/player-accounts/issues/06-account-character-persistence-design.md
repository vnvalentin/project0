Type: grilling
Status: resolved
Blocked by: 03, 05

## Question

Decide how Accounts and Characters are persisted durably and server-owned,
deliberately breaking today's "nothing is persisted" invariant for the first
time.

Resolve:

- **Storage model**: given the persistence research, what store backs Accounts
  and Characters (e.g. SQLite via GDExtension, or a bounded file store as an
  interim), and how it relates to Phase 9's Canon SQLite store — share one
  server-owned mechanism vs keep them separate.
- **Data shape at rest**: records for Account (id, username, salted derived
  credential, created-at) and Character (id, account_id, name, cosmetic, vessel
  seam, timestamps); ownership and referential integrity.
- **Transaction / atomicity boundary**: atomic account creation, atomic
  character create/delete, and restart recovery — satisfying CLAUDE.md's
  "atomic, no partial durable record" and "fail closed on unsupported versions"
  rules.
- **Server-only ownership**: the store handle never leaves the server
  (CLAUDE.md's shared-code rule); the client only sees replicated, bounded
  results.
- **Boundary handoff**: what this map DECIDES vs what the downstream persistence
  slice (shared with Phase 9) BUILDS.

Uses the persistence research
([03](03-research-godot-persistence-sqlite.md)) and the Character data model
([05](05-character-data-model-and-lifecycle.md)).

## Decision (2026-09-13, user-accepted)

- **Storage = one shared server-owned SQLite engine** via the MIT `godot-sqlite`
  GDExtension (ticket 03), in `user://`, WAL mode, `PRAGMA user_version`
  fail-closed, parameter-bound queries only. It is the **same mechanism Phase 9
  Canon uses** — one engine module and one DB file with separate tables, not a
  second store.
- **Data at rest** (server-only):
  - `accounts(account_id PK, username UNIQUE NOT NULL, pbkdf2_salt, pbkdf2_hash,
    pbkdf2_iterations, created_at, schema_version)`
  - `characters(character_id PK, account_id NOT NULL REFERENCES accounts,
    display_name, cosmetic_json, vessel_json NULL, created_at, last_played_at,
    deleted INTEGER NOT NULL DEFAULT 0, schema_version)` with a **partial unique
    index on `display_name` WHERE `deleted = 0`** (global live-name uniqueness)
    and an index on `account_id`.
- **Atomicity**: account creation, character create, and character soft-delete
  each run in a single `BEGIN`/`COMMIT`; a failure leaves **no partial durable
  record** (CLAUDE.md). Restart recovery is WAL + `user_version`; an unsupported
  `user_version` **fails closed**, never guessed forward.
- **Server-only ownership**: the DB handle lives only on the server; `shared/`
  never holds it. The client receives only **replicated, bounded DTOs** (an
  Account handle and a Character list) — never rows or the handle.
- **Boundary handoff**: this map **decides** the schema, the transaction model,
  and the shared-engine decision; the **downstream slice (shared with Phase 9 —
  the Wave 4 SQLite foundation) builds** the `godot-sqlite` integration,
  migrations, and repositories. This is the first deliberate break of the
  "nothing is persisted" invariant.

Uses 03 (SQLite research) and 05 (Character model).
