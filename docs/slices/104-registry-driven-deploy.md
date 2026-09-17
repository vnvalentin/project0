# Slice 104 - Registry-driven all-server deployment
GitHub issue: #95

Status: **delivered (pipeline unexercised against production)**

Phase: 10 (Authoritative runtime and action input), advancing P-014.

## User outcome

Tagging a release deploys every Project0 service from that exact commit, in one
auditable operation, with a backup taken first and an automatic rollback if any
service fails its health check. Adding a future service to CD is a single entry
in `deploy/services.json` — no pipeline change — which is the stated
requirement that this remain true "for any new server or service we generate
going forward".

## Scope and non-goals

In scope: `deploy/services.json`, `scripts/deploy_all.sh`, and the
`deploy-servers` job in `.github/workflows/release.yml`.

Out of scope: installing the self-hosted runner, installing the absent
`project0-operator` unit, database migrations, secret generation or rotation,
Docker production cutover, and retiring `scripts/deploy_server.ps1`, which
remains the operator-driven remote path.

## Public seam

`scripts/deploy_all.sh --commit <sha> [--only a,b] [--dry-run] [--no-rollback]`,
executed on the deployment host. The `deploy-servers` job runs the same script.

## Design notes

- The registry is JSON, not YAML, so it parses with the Python standard library
  and adds no dependency to the deployment host.
- Each entry declares its own health contract, because a restart that returns
  cleanly is not evidence that a service works. Four kinds are supported:
  `systemd-active`, `health-file` (with a freshness bound), `http` (with an
  expected status), and `compose-running`.
- `required: false` lets a service be registered before it is installed. The
  operator service is in the repository but its unit is not on the host, so it
  is reported as skipped instead of failing the run.
- Deployment runs on a self-hosted runner on the host itself, so there is no
  inbound SSH exposure and no deployment credential stored in GitHub.
- The Python services share a venv that lives *inside* the deploy root, so it is
  destroyed when the tree is replaced and is rebuilt before units restart.
- A manual `workflow_dispatch` builds the client but never deploys; only a tag
  reaches `deploy-servers`.

## Safety invariants

- The deployed tree always comes from `git archive <commit>`, never a worktree.
- The previous tree is moved to a timestamped backup before replacement, and the
  staged tree is validated for each service's `source_check` before any
  destructive step.
- Persistent data (`/var/lib/project0`, `/var/backups/project0`) and secrets
  (`/etc/project0/*.env`) live outside the deploy root and are never touched.
- Any unhealthy service after restart restores the backup and restarts units,
  unless `--no-rollback` is explicitly given.
- `--dry-run` resolves the registry and reports current health without changing
  anything.

## Acceptance scenarios

1. Given a tag push, when the pipeline runs, then the client package builds and
   every registered, installed service is deployed from that commit and
   verified healthy.
2. Given a service whose unit is not installed and `required: false`, when
   deployment runs, then it is skipped and the run continues.
3. Given a required unit that is not installed, when deployment runs, then it
   fails in preflight before any destructive step.
4. Given a service that is unhealthy after restart, then the backup is restored
   and the run fails with the backup path.
5. Given `--dry-run`, then nothing is modified.

## Validation

Focused validation: registry resolution and live health evaluation on the host
via `--dry-run`; workflow YAML parsed.

## Validation evidence

- `scripts/deploy_all.sh --dry-run` on okami, exit 0, resolved all five
  registered services and evaluated live health:
  - `game-server` — unit `enabled`, health `healthy`
  - `login-server` — unit `enabled`, health `healthy` (fresh health file)
  - `enrollment` — unit `enabled`, health `healthy` (HTTP 200 `/healthz`)
  - `operator` — `NOT-INSTALLED`, correctly reported and not fatal
  - `dashboard` — compose, health `healthy`
- `.github/workflows/release.yml` parsed by PyYAML; `deploy-servers` has
  `needs: client-package` and `if: github.ref_type == 'tag'`.

## Known limitation — not yet proven end to end

The mutating path (backup, tree replacement, venv rebuild, restart, health
gate, rollback) has **not** been executed against the production host. Doing so
restarts the live game and login servers, so it needs an explicit operator
decision and a maintenance window. Until a tag deploy has run and been observed,
this pipeline is validated for planning and health evaluation only, and the
rollback path in particular has no runtime evidence. Two prerequisites remain
operator actions: registering the self-hosted runner with labels
`self-hosted, linux, okami`, and granting the runner user the `sudo -n
systemctl restart` rights the script relies on.

## Root-cause learning

- Symptom: `--dry-run` printed three of five services then exited 1 with no
  error message.
- Public seam: `scripts/deploy_all.sh`, dry-run reporting loop.
- Hypothesis: the registry lookup for the `operator` entry was malformed.
- Discriminating check: ran `--dry-run --only operator`, which reproduced the
  silent exit 1 on a single service whose unit is absent.
- Confirmed root cause: `set -o pipefail` combined with
  `systemctl list-unit-files <absent-unit> | awk ...` inside a command
  substitution. `systemctl` exits 1 for an unknown unit, pipefail propagated it,
  and `set -e` aborted the script — so "this service is not installed", the
  exact case the registry was designed to tolerate, killed the whole run.
- Why existing tests missed it: the script was new and had only ever been run
  against services that were all installed.
- Countermeasure: a single `unit_state`/`unit_installed` helper that absorbs the
  nonzero exit, replacing four separate copies of the fragile pipeline.
- Regression evidence: `--dry-run` now exits 0 and reports `operator` as
  `NOT-INSTALLED`.
- Remaining limitation: the mutating path is still unexercised (above).

## Record links

- Feature: [P-014](../FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)
- Phase tracker: [PROJECT-TRACKER.md](../PROJECT-TRACKER.md#phase-10--authoritative-runtime-and-action-input)
- Registry: [SLICE-REGISTRY.md](SLICE-REGISTRY.md), reservation 104
- Prior slice: [101](101-server-deployment-pipeline.md) (operator-driven remote path)
