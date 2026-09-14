# Slice 057 — Game-server persistent data boundary and SQLite backup/restore

Status: **in progress**

Phase: 10 (Authoritative runtime and action input), advancing
[P-014](../FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime).
Third delivery of the
[container-platform map](../../.scratch/container-platform/map.md), implementing
the [persistence decision](../../.scratch/container-platform/issues/03-persistence-and-data-ownership.md)
for the containerized game server.

## User outcome

The containerized authoritative server keeps its durable state (accounts and
Canon) on the host under `/var/lib/project0`, so the data survives container
replacement, and an operator can take a consistent SQLite backup and restore it,
without touching the native server or gameplay behavior.

## Scope and non-goals

In scope: bind-mount the container's writable `user://` data to a host path
(default `/var/lib/project0/game`); add the `sqlite3` CLI to the image for the
SQLite online-backup API; add `deploy/game-server/backup.sh` (consistent
`.backup` of the live game DB into `/var/backups/project0` with an integrity
check) and `deploy/game-server/restore.sh` (guarded restore into the data dir);
document the one-time host directory setup and ownership.

Out of scope (later slices): physically splitting accounts into a separate
`login/accounts.sqlite3` from `game/canon.sqlite3` — that lands with the
login-service extraction (Slices 058–060), which takes ownership of the
accounts database; scheduled/automated backups (a systemd timer follow-up); the
production cutover from the native service (migration decision). This slice
changes no `.gd` file, so the GUT suite is unaffected.

## Public seam

- `deploy/game-server/docker-compose.yml` — the data volume becomes a host
  bind mount `${GAME_DATA_DIR:-/var/lib/project0/game}:/data`, plus a
  `${GAME_BACKUP_DIR:-/var/backups/project0}:/backup` mount for backups.
- `deploy/game-server/Dockerfile` — adds `sqlite3`.
- `deploy/game-server/backup.sh` — consistent online backup of the running
  container's game DB to `/backup/project0-game-<timestamp>.sqlite3`, then
  `PRAGMA integrity_check`.
- `deploy/game-server/restore.sh` — guarded restore: stop the container, replace
  the data DB from a chosen backup, clear stale WAL/SHM, restart.

## Safety invariant

The data boundary is explicit and host-owned: writable state lives only under
`/var/lib/project0`, backups only under `/var/backups/project0`, both outside
the `/apps/project0` application tree and outside the image. The container stays
non-root; the native `project0-server.service` and its data are never touched.
Backups use the SQLite online-backup API (`.backup`) so a live WAL database is
copied consistently, never a torn file copy.

## ADR rationale

No new ADR. The `/var/lib/project0` data boundary, `/var/backups/project0`
backups, server-only ownership, and consistent-backup requirement are already
fixed by the accepted persistence decision.

## BDD / TDD

No GUT seam; delivery evidence is runtime on the Linux host `192.168.1.254`,
beside the native server:

1. **Host boundary.** After one-time setup, the container writes its DB under
   `/var/lib/project0/game` on the host.
2. **Durability across replacement.** Boot writes Canon (`ok`); after
   `stop && rm` and a fresh `up`, the second boot reports Canon `idempotent`,
   proving the DB persisted independently of the container.
3. **Consistent backup.** `backup.sh` produces a timestamped backup in
   `/var/backups/project0` that passes `PRAGMA integrity_check`.
4. **Restore.** `restore.sh` restores a backup into a fresh data dir and the
   server boots against it (Canon `idempotent`).
5. **Non-interference.** The native server and its data are untouched.

## Validation

- Full GUT gate on the Linux host: `scripts/run_gut_validation.sh` (expected
  unchanged 326/326 across 45/45 scripts, exit 0 — no `.gd` change).
- `scripts/check_record_sync.sh` (exit 0).
- Runtime persistence evidence (host path, durability across replacement,
  backup integrity, restore) captured on `192.168.1.254`. Recorded on
  completion.

## Root-cause learning

Observed: the independent restore path via a one-shot `docker run <image> sh -c
...` started the game server instead of running the copy/`sqlite3` commands.

Hypothesis and check: the image `ENTRYPOINT` is `tini -- entrypoint.sh`, which
`exec`s the server and ignores the container `CMD`; a `docker run` override
replaces `CMD`, not `ENTRYPOINT`. Discriminating check: the run logged
`Server listening` rather than the restore commands.

Root cause and countermeasure: a one-shot maintenance container must override
the entrypoint. `restore.sh` now uses `docker run --rm --entrypoint sh ... -c
"..."`. `backup.sh` was already correct because it uses `docker exec`, which
runs a command in the already-started container and bypasses the entrypoint.
Regression evidence: the restore proof below (wipe data → restore → boot Canon
`idempotent`) exercises the fixed path.
