# Persistence and data ownership

Status: resolved
Assignee: Copilot
Type: grilling
Blocked by: 01-runtime-boundary-and-container-adapter, 02-account-login-service-boundary

## Question

How are Account, Character, Canon, mutation, and runtime data separated across
services and volumes? Decide whether SQLite remains one server-owned engine or
is split by ownership, migration ordering, backup/restore, locking, schema
versioning, and the read/write interface between login and game services.

## Required decision output

A data ownership and migration contract that prevents two independently
deployed processes from becoming competing SQLite authorities.

## Resolution

The production migration host is Linux `192.168.1.254`. Its Project0
application root is `/apps/project0`; persistent state is outside the
application tree under `/var/lib/project0`; backups are outside both under
`/var/backups/project0` with host access controls.

The login and game services MUST NOT open the same SQLite file. They have
separate database ownership:

```text
/var/lib/project0/login/accounts.sqlite3
/var/lib/project0/game/canon.sqlite3
/var/lib/project0/game/runtime-state/
```

The login service owns Account credentials, Account records, Character records,
login/session issuance, Character selection, and account-side audit events.
The authoritative game server owns Canon sectors, the Canon mutation log, live
Player state, runtime state, validated game-session bindings, and gameplay
telemetry.

The existing `SqliteStore` remains the persistence baseline: WAL,
parameter-bound queries, atomic transactions, and fail-closed schema versioning
are retained. The existing Account/Character repository and schema are migrated
behind the login service rather than rewritten. Canon remains in its game-owned
database and is never accessed by the login service.

Migration from the current installation on `192.168.1.254` is one-time and
rollback-preserving:

1. Stop the native game server and prevent concurrent Account writes.
2. Back up the current `user://accounts.db` and record its schema/version.
3. Validate and migrate Account/Character tables into
   `/var/lib/project0/login/accounts.sqlite3`.
4. Start the login service and verify login, Character CRUD, and assertion
   issuance.
5. Start the game server against `/var/lib/project0/game/canon.sqlite3` and
   verify signed-assertion world entry.
6. Retain the original database as rollback evidence until the cutover gate is
   accepted.

The old in-process `AuthService` is a compatibility adapter during migration,
but it MUST NOT remain a competing writable authority after external login
ownership is enabled. Cross-service data access uses the login interface and
signed assertions, never direct SQLite handles or shared files.

Each database has an independent schema version and migration owner. Unsupported
versions fail closed. Backups must capture the database plus WAL/SHM state using
a consistent SQLite backup operation, not an arbitrary file copy while active.
Restore is service-scoped, validated before start, and records the restored
schema/version and backup identity.

## Acceptance evidence

The implementation route must prove migration on `192.168.1.254` using a
rollback copy, no concurrent writers, preserved Account/Character behavior,
separate login/game database access, restart recovery, schema fail-closed
behavior, and signed-assertion world entry. No production migration occurs as
part of this planning decision.

## Decision status

Resolved by user confirmation on 2026-09-14. No production files were changed
by this planning decision.
