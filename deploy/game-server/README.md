# Project0 game-server container (Slice 056)

Reproducible OCI image for the authoritative Godot server, per the
[runtime-boundary decision](../../.scratch/container-platform/issues/01-runtime-boundary-and-container-adapter.md).
It runs `server/server_main.gd` headless exactly like the native systemd unit
[`scripts/project0-server.service`](../../scripts/project0-server.service), but
isolated: pinned Godot 4.3, non-root, UDP 9999, baked import cache, graceful
`SIGTERM` shutdown via tini.

## Run beside the native server (no cutover)

From the repository root on the Linux host (`192.168.1.254`):

```sh
# Build + start the candidate on an isolated host UDP port (default 127.0.0.1:19999).
docker compose -f deploy/game-server/docker-compose.yml up --build -d

# Confirm boot and health.
docker logs project0-game-server-candidate | grep "Server listening"
docker inspect --format '{{.State.Health.Status}}' project0-game-server-candidate

# Graceful stop and cleanup (leaves the native server untouched).
docker compose -f deploy/game-server/docker-compose.yml down -v
```

Override the published binding with `GAME_HOST_BIND` / `GAME_HOST_PORT`. The
native `project0-server.service` on UDP 9999 is never modified by this slice.

## Host-persistent data and backups (Slice 057)

Durable state lives on the host, outside the image and the `/apps/project0`
application tree, per the
[persistence decision](../../.scratch/container-platform/issues/03-persistence-and-data-ownership.md).

One-time host setup (data + backup dirs owned by the container's non-root uid
`10001`):

```sh
sudo install -d -o 10001 -g 10001 -m 700 /var/lib/project0/game
sudo install -d -o 10001 -g 10001 -m 700 /var/backups/project0
```

The Compose file bind-mounts `${GAME_DATA_DIR:-/var/lib/project0/game}` at
`/data` (durable `user://` state) and `${GAME_BACKUP_DIR:-/var/backups/project0}`
at `/backup`. Data survives container replacement.

Consistent SQLite online backup (safe on a live WAL database) and restore:

```sh
# Back up the running container's DB into /var/backups/project0 (integrity-checked).
deploy/game-server/backup.sh

# Restore a chosen backup, then restart the container.
deploy/game-server/restore.sh /var/backups/project0/project0-game-<timestamp>.sqlite3
```

## Boundaries

- Non-root (`uid 10001`); no OPNsense credentials or client keys.
- Writable state is confined to the `/data` (host `/var/lib/project0/game`) and
  `/backup` (host `/var/backups/project0`) mounts; the source tree is otherwise
  read-only at runtime.
- Splitting accounts into a separate `login/accounts.sqlite3` lands with the
  login-service extraction (Slices 058–060); this slice keeps the current single
  DB but on the durable host boundary.
- Liveness (Slice 067): the server rewrites a JSON health file
  (`PROJECT0_HEALTH_FILE`, default `/data/health.json`) every ~0.5 s from the
  Slice 055 `ServerHealth` contract; the `HEALTHCHECK` (`healthcheck.sh`) fails
  when that file is missing, stale, or not `healthy`, so a frozen tick loop is
  caught even while the UDP socket stays bound. Exposing health over a socket
  endpoint remains a later slice.
