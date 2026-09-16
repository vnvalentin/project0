# Project0 Flow Dashboard

Read-only local Kanban and Andon dashboard for the authoritative markdown
records in the parent repository.

## Run

From `dashboard/`:

```bash
docker compose up --build
```

Open http://127.0.0.1:8080. Health: http://127.0.0.1:8080/health

The dashboard is localhost-only by default. To make it reachable from other
machines on the local LAN, bind Docker to this host's LAN address (rather than
all interfaces):

```bash
DASHBOARD_BIND_ADDRESS=192.168.1.254 DASHBOARD_HOST_PORT=18083 docker compose up --build -d
```

The resulting LAN URL is http://192.168.1.254:18083. The host firewall must
permit TCP `18083` on the LAN interface. To expose the service on every host
interface, explicitly set `DASHBOARD_BIND_ADDRESS=0.0.0.0`; this is not the
default.

The container mounts the repository read-only and has no write endpoint. It
refreshes the tracker files every 15 seconds, so status changes appear without
rebuilding the image.

The Reality page also reads open GitHub issues from `GITHUB_REPO` (default
`vnvalentin/project0`) and caches the result for `GITHUB_ISSUE_CACHE_SECONDS`
(default `300`). This makes GitHub Issues the live planning board while the
markdown records remain the evidence and delivery-history base. If GitHub is
temporarily unreachable, the page shows a visible source warning rather than
silently inventing a status.

## Reflecting GitHub `origin/main` instead of the local working tree

By default the dashboard renders the parent working tree (`..`), so it shows
whatever branch or uncommitted edits are checked out locally. To make it
reflect the canonical GitHub `main` instead, point it at a mirror checkout that
is kept synced to `origin/main`:

```bash
git clone https://github.com/vnvalentin/project0.git /data/code/project0-flow-mirror
sudo install -m 644 project0-flow-mirror-sync.service /etc/systemd/system/
sudo install -m 644 project0-flow-mirror-sync.timer /etc/systemd/system/
sudo systemctl enable --now project0-flow-mirror-sync.timer   # fetch + reset --hard origin/main every 2 min
DASHBOARD_REPO_SOURCE=/data/code/project0-flow-mirror \
  DASHBOARD_BIND_ADDRESS=192.168.1.254 DASHBOARD_HOST_PORT=18083 \
  docker compose up -d --force-recreate
```

`DASHBOARD_REPO_SOURCE` (default `..`) selects the source; a host-local
`dashboard/.env` can persist it. `GITHUB_REPO` can point the issue feed at a
different repository if the tracker is forked. The sync unit also normalizes file
permissions to world-readable, because this host's `umask` (077) otherwise
writes checkouts as `0600`, which the container's `nobody` user cannot read.

If port `8080` is already occupied, start the same image on another local
port, for example:

```bash
docker compose run -d --name project0-flow-visual -p 127.0.0.1:18083:8080 project0-flow
```

Then open http://127.0.0.1:18083.
