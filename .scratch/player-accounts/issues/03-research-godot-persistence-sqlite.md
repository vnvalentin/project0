Type: research
Status: resolved

## Question

What server-owned persistence mechanisms are viable in Godot 4 for storing
Accounts and Characters durably across restarts, and how do they relate to
Phase 9's future SQLite Canon store?

Investigate against primary sources (Godot 4 official docs, the `godot-sqlite`
project, engine source):

- Native options: `FileAccess` + `ConfigFile` / JSON / `var_to_bytes`, and their
  atomicity and corruption characteristics for a small structured store.
- SQLite access: the `godot-sqlite` GDExtension (2shady4u) — maturity, license,
  headless support, transaction API — and any first-party alternative.
- What Phase 9 (Canon persistence) is likely to standardize on, so
  Accounts/Characters and Canon can share one server-owned persistence approach
  rather than diverging.
- Atomic-write and restart-recovery patterns (write-temp-then-rename, WAL) that
  satisfy CLAUDE.md's "atomic, no partial durable record" persistence rule.

Output: a recommended persistence mechanism (or a short-list with a
recommendation) for the account/character store, with the transaction/atomicity
pattern and primary sources cited. Unblocks the persistence-design ticket.

Findings file: `.scratch/player-accounts/research/03-godot-persistence-sqlite.md`.

## Answer

**Recommended: converge on one shared, server-owned SQLite engine via the
`godot-sqlite` GDExtension (2shady4u)** — MIT-licensed, GDExtension (no engine
recompile), tracks Godot 4.x (latest v4.9), and explicitly headless /
dedicated-server supported (README FAQ #4).

- Atomicity = SQLite transactions: wrap each account creation and character
  create/delete in `BEGIN … COMMIT` / `ROLLBACK`. SQLite transactions "appear
  atomic even if interrupted by an OS crash or power failure" with automatic
  hot-journal restart recovery — exactly CLAUDE.md's "atomic, no partial durable
  record."
- Enable `PRAGMA journal_mode=WAL` and `PRAGMA user_version` (fail-closed on an
  unsupported schema version). Keep the DB in `user://`, never `res://`.
- Use `query_with_bindings()` only (parameter binding → injection-safe); never
  concatenate player-supplied names into SQL.
- **Share ONE mechanism with Phase 9 Canon**: Canon is already mandated to be
  SQLite in CLAUDE.md; model Account, Character, and Canon as separate schemas
  behind a single server-owned SQLite layer rather than a second subsystem.
- Zero-dependency interim (only if the slice must ship before the GDExtension
  clears AGENTS.md governance): flat file via write-temp-then-`DirAccess.rename`
  (atomic — maps to POSIX `rename(2)`). But native `FileAccess` is not atomic by
  default (`FileAccess::backup_save = false`) and GDScript exposes no `fsync`, so
  treat it as a bridge, not the destination.

**Open (decide in the persistence-design ticket):** take the `godot-sqlite`
dependency now (pinned release + AGENTS.md safety/rollback note) vs ship the
flat-file interim first; runtime-validate the plugin binary loads under
`godot --headless` on this host's glibc (FAQ #4 flags glibc < 2.35); WAL vs
rollback journal and `synchronous=FULL` vs `NORMAL`; one shared `.db` vs
separate identity/Canon DB files; and `PRAGMA user_version` vs an explicit `meta`
table for schema versioning.

Full findings with primary-source citations:
[research/03-godot-persistence-sqlite.md](../research/03-godot-persistence-sqlite.md).
