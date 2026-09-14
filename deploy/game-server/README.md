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

## Boundaries

- Non-root (`uid 10001`); no OPNsense credentials or client keys.
- Writable state is confined to the `/data` volume (`user://`); the source tree
  is otherwise read-only at runtime.
- Persistence split to `/var/lib/project0` and backup/restore are Slice 057.
- Health snapshot wiring (Slice 055 `ServerHealth`) to a machine-readable
  endpoint is a later slice; this image uses a port-bound `HEALTHCHECK`.
