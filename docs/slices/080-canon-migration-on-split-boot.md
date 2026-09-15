# Slice 080 — One-time Canon migration into a dedicated store on first split boot

Status: **delivered**

Phase: 10 (Authoritative runtime and action input), advancing
[P-014](../FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime).
Completes [Slice 079](079-optional-dedicated-canon-store.md): the opt-in
canon/accounts DB split is now **safe for existing combined deployments**, not
just fresh ones. On the first boot with a dedicated (empty) Canon store, the
game server copies any Canon out of the shared accounts store so a previously
combined world is preserved.

## User outcome

An operator with an existing combined `accounts.db` (accounts + Canon in one
file) can set `PROJECT0_CANON_DB_PATH=/data/canon.db` and, on the next boot, the
authoritative world (starting town and any JIT sectors) is copied into the new
file automatically — with its original `created_at` intact — instead of starting
empty. Source rows are never deleted; a re-boot finds the dedicated store
non-empty and skips. Unset (shared handle) never migrates.

## Scope and non-goals

In scope:
- `server/canon_repository.gd`: `list_all_records()` (verbatim rows, ordered
  oldest-first) and `restore_record()` (insert preserving the original
  `created_at`, validating the blueprint, idempotent on identical, conflict on
  differing).
- `server/server_main.gd`: on first split boot (dedicated store empty), copy all
  Canon from the accounts store via those seams before canonicalizing the town.

Out of scope: Canon mutation rows (the mutation repository is not wired into the
boot path, so no runtime mutations exist yet); deleting or archiving the source
Canon; changing any default (the split stays opt-in).

## Public seam

- `server/canon_repository.gd` (`list_all_records`, `restore_record`).
- `server/server_main.gd` (`_start_server` first-split-boot migration).

## Safety invariant

Migration only runs when a dedicated store is selected **and** it is empty, and
it only ever inserts into that empty store — the source is read-only and never
deleted, so the change is non-destructive and re-runnable. A differing sector_id
collision fails closed as a conflict rather than overwriting immutable Canon.
Unset preserves the shared-handle default with no migration.

## ADR rationale

No new ADR. This applies the server-owned persistence boundary: the immutable
Canon record (including `created_at`) is preserved faithfully when it moves to
its own file, consistent with Slice 045's canonicalization semantics.

## BDD / TDD

`tests/integration/test_canon_store_split.gd` adds: migration copies Canon into
the empty dedicated store preserving `created_at` and leaves the source intact;
`restore_record` is idempotent (no duplicate); `restore_record` refuses a
conflicting blueprint for an existing sector.

## Validation

- Full suite: `scripts/run_gut_validation.sh` on the Linux host — **passed, 58/58
  scripts, exit 0** (adds three migration cases to
  `tests/integration/test_canon_store_split.gd`).
- Runtime on Linux (three boots): boot shared seeded a combined `mig_acc.db`
  (`canon db: shared:mig_acc.db`); boot split into a fresh `mig_canon.db` logged
  `Migrated 1 Canon sector(s) from the accounts store into mig_canon.db` and then
  `Starting town Canon ready: idempotent` (proving the migrated town was
  preserved); a second split boot logged no migration and stayed idempotent
  (skipped because the dest is non-empty).
- `scripts/check_record_sync.sh` exit 0.

## Root-cause learning

None. No unexpected failure surfaced during delivery.
