# Slice 113 - Dashboard apps source layout
GitHub issue: #211

Status: **delivered**

Phase: 7 (Delivery workflow capabilities), advancing
[F-025](../FEATURE-LIST.md#f-025-project-flow-visual-management-dashboard).

## User outcome

The live dashboard runs as a container from a standard host app directory,
`/apps/project0/dashboard`, and reads a dedicated repo clone under that same app
directory. It no longer depends on a user's home directory checkout or the stale
`/data/code/project0` source mirror.

## Scope and non-goals

In scope: dashboard compose defaults, dashboard host deployment documentation,
the repo-sync systemd unit path, dashboard test-result publication path, and
host rollout of `/apps/project0/dashboard` with a dedicated read-only repo clone.

Out of scope: changing the dashboard UI behavior, replacing the dashboard with a
GitHub-only app, changing game server deployment paths, or moving durable game
state.

## Public seam

The dashboard compose app at `/apps/project0/dashboard` and the served dashboard
HTTP endpoints:

- `GET /`
- `GET /detail`
- `GET /health`

## SDD

The host app directory owns the container compose files and the dashboard source
fallback. Its `repo/` child is a dedicated clone of `origin/main`; the container
mounts it read-only at `/repo`. The sync unit refreshes that clone and restarts
`project0-flow` best-effort. Compose defaults to `./repo`, so running from
`/apps/project0/dashboard` requires no home-directory path or `/data/code`
mirror.

## BDD

1. Given `/apps/project0/dashboard/repo` is a git clone of `origin/main`, when
   `docker compose up` runs from `/apps/project0/dashboard`, then the dashboard
   container mounts that clone read-only at `/repo`.
2. Given the dashboard is restarted, when the Reality page is requested, then it
   serves the latest merged Goal source-of-truth UI.
3. Given the Detail page is requested, then it serves the GitHub traceability
   baseline UI from the dedicated repo clone.

## TDD / validation

Focused local commands:

```bash
bash -n scripts/run_gut_validation.sh
python -m py_compile dashboard/app.py
```

Additional local checks: Docker Compose was unavailable on Windows; the compose
source was checked textually for the default volume `${DASHBOARD_REPO_SOURCE:-./repo}:/repo:ro`,
and dashboard render checks for `render_exec('working')` and `render('working')`
passed.

Host validation on okami confirmed:

- `/apps/project0/dashboard` exists and owns the compose app.
- `/apps/project0/dashboard/repo` is a git clone of `origin/main`.
- No nested `/apps/project0/dashboard/dashboard/docker-compose.yml` path exists.
- `project0-flow` mounts `/apps/project0/dashboard/repo` to `/repo` read-only.
- The systemd sync timer installed and started without a blocker.
- `GET /health` returned `{"status":"ok"}`.
- `GET /` served `Open goal child issues`.
- `GET /detail` served `Project0 Traceability` and
   `GitHub traceability baseline`.

Record sync: `bash scripts/check_record_sync.sh`, expected exit 0.

## ADR / telemetry / review

No ADR: this changes the operational placement of existing dashboard tooling,
not the product architecture or security model. The dashboard remains read-only.
Review focus is avoiding home-directory coupling, eliminating the stale mirror,
and proving the served container uses the dedicated clone.
