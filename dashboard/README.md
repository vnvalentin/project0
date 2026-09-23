# Project0 Master Roadmap

Read-only roadmap for the technology-neutral master game vision. It presents
the player promise, outcome goals A-H, the Party/traversal vertical slice, the
delivery order, and live GitHub planning focus. The roadmap is not an
implementation status claim and does not choose storage, model, messaging, or
map-builder technology.

## Run

From a development checkout's `dashboard/`:

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

The master roadmap page is available at
http://192.168.1.254:18083/roadmap. The root URL serves the same page for
backward compatibility.

The container mounts the repository read-only and has no write endpoint. It
refreshes the roadmap every 30 seconds, so charter and planning changes appear
without rebuilding the image.

The page reads GitHub issues from `GITHUB_REPO` (default
`vnvalentin/project0`) and caches the result for `GITHUB_ISSUE_CACHE_SECONDS`
(default `300`). The markdown vision remains the local source of truth. If
GitHub is temporarily unreachable, the page shows a visible source warning
rather than silently inventing a status. The `/tracker` page is retained only
as a read-only viewer of the frozen `docs/PROJECT-TRACKER.md` archive; it does
not project active status or enforce tracker parity.

The `/delivery` page is the local operational view for active GitHub Issues. It
shows the active delivery table and groups work by Outcome and Phase, with
milestones, blocked state, evidence, parent issue, and assignee visibility.
These fields are projected from issue labels, milestones, assignees, and
structured body lines, so the view does not depend on GitHub Project #2 custom
field access.

## Host deployment under `/apps/project0/dashboard`

The production host layout is self-contained and does not depend on a user's
home directory:

- `/apps/project0/dashboard/docker-compose.yml` — the compose project.
- `/apps/project0/dashboard/Dockerfile` and `roadmap.py` — the dashboard image
  source/fallback.
- `/apps/project0/dashboard/repo` — a dedicated clone of `origin/main`, mounted
  read-only into the container at `/repo`.

Install or refresh the app directory from a clean checkout:

```bash
sudo mkdir -p /apps/project0/dashboard
sudo rsync -a dashboard/ /apps/project0/dashboard/
sudo git clone https://github.com/vnvalentin/project0.git /apps/project0/dashboard/repo
sudo install -m 644 project0-flow-mirror-sync.service /etc/systemd/system/
sudo install -m 644 project0-flow-mirror-sync.timer /etc/systemd/system/
sudo systemctl enable --now project0-flow-mirror-sync.timer   # fetch + reset --hard origin/main every 2 min
cd /apps/project0/dashboard
DASHBOARD_BIND_ADDRESS=192.168.1.254 DASHBOARD_HOST_PORT=18083 \
  docker compose up --build -d --force-recreate
```

`DASHBOARD_REPO_SOURCE` defaults to `./repo`, so the compose file works from
`/apps/project0/dashboard` without extra environment. A host-local `.env` can
override it for development. `GITHUB_REPO` can point the issue feed at a
different repository if the tracker is forked. The sync unit also normalizes
file permissions to world-readable, because this host's `umask` (077) otherwise
writes checkouts as `0600`, which the container's `nobody` user cannot read.

If port `8080` is already occupied, start the same image on another local
port, for example:

```bash
docker compose run -d --name project0-flow-visual -p 127.0.0.1:18083:8080 project0-flow
```

Then open http://127.0.0.1:18083.
