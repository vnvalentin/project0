# Slice 079 — Optional dedicated Canon store (opt-in canon/accounts DB split)

Status: **delivered**

Phase: 10 (Authoritative runtime and action input), advancing
[P-014](../FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)
and the [login/persistence boundary](../../.scratch/container-platform/map.md).
The game server currently opens one SQLite handle (`accounts.db`) and Slice 045
made Canon **share** it. This slice lets the game server give Canon its **own**
store so a split deployment isolates the world record from the accounts file —
without moving or risking any existing data.

## User outcome

An operator can run the game server with `PROJECT0_CANON_DB_PATH=/data/canon.db`
and the authoritative world (starting-town Canon and any JIT sectors) is stored
there, fully separated from the accounts database. Unset, the server behaves
exactly as before (Canon shares the accounts handle), so existing combined
deployments are untouched and need no migration.

## Scope and non-goals

In scope:
- `server/server_main.gd`: when `PROJECT0_CANON_DB_PATH` is set, open a dedicated
  `SqliteStore` for Canon and back `CanonRepository` with it; unset keeps the
  Slice 045 shared handle. Fail closed if the dedicated store cannot open.

Out of scope (deliberately): migrating existing Canon rows out of a combined
`accounts.db` into a new `canon.db` (a fresh dedicated path starts empty and the
starting town re-canonicalizes idempotently); the canon mutation repository is
not in the boot path and is unchanged; changing the default (still shared);
flipping any client/game split default. This is the opt-in seam only.

## Public seam

- `server/server_main.gd` (`_start_server` Canon store selection).
- `PROJECT0_CANON_DB_PATH` environment variable.

## Safety invariant

The change is opt-in: with `PROJECT0_CANON_DB_PATH` unset every existing boot,
file, and test is unchanged — no migration, no data movement, no data-loss risk.
When set, Canon and accounts are isolated stores; a dedicated-store open failure
fails closed (the server refuses to start) exactly like the accounts store.

## ADR rationale

No new ADR. This applies the established server-owned persistence boundary
(CLAUDE.md Runtime Ownership) to give Canon its own file for a split deployment,
consistent with the login server already owning `login_accounts.db`.

## BDD / TDD

`tests/integration/test_canon_store_split.gd`: with a dedicated Canon store a
canonicalized sector is present only in the canon store and absent from the
accounts store (and an account is present only in the accounts store); with the
shared store (the default) both records are reachable through the one handle.

## Validation

- Full suite: `scripts/run_gut_validation.sh` on the Linux host — **passed, 58/58
  scripts, exit 0** (adds `tests/integration/test_canon_store_split.gd`).
- Runtime on Linux: `server/server_main.gd` booted headless with
  `PROJECT0_CANON_DB_PATH=split_canon.db` logged `Starting town Canon ready: ok
  (canon db: split_canon.db)` and created both `split_acc.db` and
  `split_canon.db` under `user://`; booted unset it logged `(canon db:
  shared:shared_acc.db)` — the shared-handle default unchanged. File-level table
  inspection was not possible (`sqlite3` absent on the host); the repository-seam
  integration test proves Canon/accounts isolation deterministically.
- `scripts/check_record_sync.sh` exit 0.

## Root-cause learning

None. No unexpected failure surfaced during delivery.
