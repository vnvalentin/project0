# Nakama self-hosting operations for Project0

Research ticket: [#338](https://github.com/vnvalentin/project0/issues/338)  
Date: 2026-09-19  
Scope: research only; no implementation recommendation is assumed approved.

## Sources

Primary sources used:

- Heroic Labs, Nakama Docker Compose install: https://heroiclabs.com/docs/nakama/getting-started/install/docker/
- Heroic Labs, Nakama Docker configuration: https://heroiclabs.com/docs/nakama/getting-started/configuration/docker-configuration/
- Heroic Labs, Nakama server configuration: https://heroiclabs.com/docs/nakama/getting-started/configuration/
- Heroic Labs, Nakama commands and migrations: https://heroiclabs.com/docs/nakama/getting-started/commands/
- Heroic Labs, Nakama Console: https://heroiclabs.com/docs/nakama/getting-started/console/
- Heroic Labs official Compose file referenced by the docs: https://raw.githubusercontent.com/heroiclabs/nakama/master/docker-compose-postgres.yml
- Docker Compose secrets: https://docs.docker.com/compose/how-tos/use-secrets/
- Docker Compose startup order and health dependencies: https://docs.docker.com/compose/how-tos/startup-order/
- Docker volumes, lifecycle, backup/restore: https://docs.docker.com/engine/storage/volumes/
- PostgreSQL backup overview: https://www.postgresql.org/docs/current/backup.html
- PostgreSQL `pg_dump`: https://www.postgresql.org/docs/current/app-pgdump.html
- Local Project0 deployment evidence: `deploy/compose.yml`, `scripts/deploy_containers.sh`, `dashboard/docker-compose.yml`.

## Executive summary

Self-hosting Nakama for Project0 is operationally feasible as a Docker Compose addition, but it is not just another stateless service. It introduces a durable SQL database, database migrations on every Nakama version change, a sensitive YAML configuration surface, an admin console, and a new public realtime/API port surface. The smallest viable Project0 topology is one Nakama container plus one PostgreSQL container or external PostgreSQL service, with Nakama data/config mounted into the container and Postgres data backed by a durable volume.

The main adoption constraint is scaling posture. Heroic Labs documents clustering options as Nakama Enterprise-only, and says production HA clustering uses Enterprise or Heroic Cloud. For open-source self-hosting, assume a single Nakama node until Project0 explicitly chooses Enterprise/Heroic Cloud or receives a newer official source that says otherwise. Source: https://heroiclabs.com/docs/nakama/getting-started/configuration/

## Required services and databases

Official Docker Compose setup uses two services:

- `postgres`, image `postgres:16.8-alpine`, database `nakama`, password `localdb`, data volume at `/var/lib/postgresql/data`.
- `nakama`, image `registry.heroiclabs.com/heroiclabs/nakama:3.37.0`, starting with `nakama migrate up` and then running the server.

Source: https://raw.githubusercontent.com/heroiclabs/nakama/master/docker-compose-postgres.yml

Nakama exposes four server ports by default:

- `7350`: client HTTP API and realtime socket endpoint.
- `7351`: embedded developer/admin console HTTP server.
- `7349`: gRPC API server.
- `7348`: gRPC console API server, chosen relative to the console/API port.

Source: https://heroiclabs.com/docs/nakama/getting-started/configuration/

Database source ambiguity: the current official Docker install page says Docker makes it easy to run PostgreSQL for Nakama and references `docker-compose-postgres.yml`. The server configuration page also contains a statement that Nakama requires CockroachDB, while the Docker configuration page provides both PostgreSQL and CockroachDB examples. Treat PostgreSQL as the documented Docker path for this research, and verify with Heroic Labs before committing Project0 production architecture to PostgreSQL vs CockroachDB. Sources: https://heroiclabs.com/docs/nakama/getting-started/install/docker/, https://heroiclabs.com/docs/nakama/getting-started/configuration/, https://heroiclabs.com/docs/nakama/getting-started/configuration/docker-configuration/

## Docker/self-hosting topology

Minimal Project0-compatible Compose shape:

- Add `nakama-db` or externalize PostgreSQL.
- Add `nakama` with a pinned image tag, not `latest`, matching Project0's current immutable image-tag deployment posture in `deploy/compose.yml` and `scripts/deploy_containers.sh`.
- Mount persistent database storage using a named Docker volume or Project0-style host path under `/var/lib/project0/nakama-db`.
- Mount Nakama config/data into `/nakama/data`; Heroic Labs Docker configuration docs show mounting a host directory and passing `--config /nakama/data/my-config.yml`.
- Gate Nakama startup on DB health. Heroic Labs' official Compose file uses `depends_on: postgres: condition: service_healthy`; Docker documents that `service_healthy` waits for a dependency healthcheck before creating the dependent service.

Sources: https://heroiclabs.com/docs/nakama/getting-started/configuration/docker-configuration/, https://raw.githubusercontent.com/heroiclabs/nakama/master/docker-compose-postgres.yml, https://docs.docker.com/compose/how-tos/startup-order/

Interaction with current Project0 stack:

- Current `deploy/compose.yml` already runs `game-server`, `login-server`, `enrollment`, optional `operator`, and optional `dashboard` under one Compose project named `project0`.
- Current Project0 services bind UDP `9999`, UDP `9998`, enrollment HTTP `8095`, operator `8099` loopback, and dashboard `8080` loopback by default.
- Nakama's default ports `7349`, `7350`, and `7351` do not collide with current Project0 defaults.
- Console `7351` should not be public by default. Bind it to `127.0.0.1` or put it behind the existing operator/admin access model. The Nakama Console can reset all player data, and that action is irreversible. Source: https://heroiclabs.com/docs/nakama/getting-started/console/
- If Project0 keeps its Godot authoritative game server, Nakama is an adjacent identity/session/social/matchmaking service, not a drop-in replacement for UDP `9999` simulation without a separate design decision.

## Configuration and secrets

Nakama reads YAML config via `--config`, and command-line flags override config-file values. Source: https://heroiclabs.com/docs/nakama/getting-started/commands/

Heroic Labs says these defaults must be changed before live production use:

- `socket.server_key` defaults to `defaultkey`.
- `session.encryption_key` defaults to `defaultencryptionkey`.
- `runtime.http_key` defaults to `defaulthttpkey`.
- Console username/password default to `admin`/`password`.

Sources: https://heroiclabs.com/docs/nakama/getting-started/configuration/, https://heroiclabs.com/docs/nakama/getting-started/install/docker/

For Project0, keep the current secret boundary: `/etc/project0/*.env` lives outside the repo and images, per `deploy/compose.yml` and `scripts/deploy_containers.sh`. Docker Compose secrets are also viable for file-mounted values; Docker documents that Compose secrets are mounted at `/run/secrets/<secret_name>` and granted per service, avoiding plain environment variables for passwords/API keys. Source: https://docs.docker.com/compose/how-tos/use-secrets/

Caution: Nakama's `runtime.env` is only for custom server modules. Heroic Labs explicitly says Nakama subsystems such as IAP, social sign-in, and Google Auth read their own configuration sections, not `runtime.env`; putting those credentials in `runtime.env` leaves the subsystem unconfigured. Source: https://heroiclabs.com/docs/nakama/getting-started/configuration/

## Backups and restore posture

Back up at least three things:

1. PostgreSQL database contents.
2. Nakama YAML config and any runtime modules mounted under `/nakama/data`.
3. Secrets and operational env files outside the repo, currently `/etc/project0/*.env` for Project0-style deployment.

PostgreSQL documents three backup approaches: SQL dump, file-system-level backup, and continuous archiving/PITR. Source: https://www.postgresql.org/docs/current/backup.html

For small playtest operations, `pg_dump -Fc nakama > nakama.dump` is the lazy baseline because PostgreSQL documents `pg_dump` as producing consistent exports while the database is in use, without blocking readers or writers. PostgreSQL also warns that `pg_dump` is generally not the right choice for regular production backups except in simple cases, so PITR/continuous archiving becomes the upgrade path when playtester data loss tolerance shrinks. Source: https://www.postgresql.org/docs/current/app-pgdump.html

Docker volumes persist after container removal and can be backed up by mounting the volume into a temporary container and writing a tar archive to a host backup directory. Source: https://docs.docker.com/engine/storage/volumes/

Project0 already mounts `/var/backups/project0` into `game-server` and persists service data under `/var/lib/project0/...`; Nakama should follow that convention rather than invent a second backup root.

## Observability

Nakama logging:

- Nakama produces JSON logs by default to stdout.
- It can write rotated files with `logger.file`, `logger.rotation`, `logger.max_size`, `logger.max_age`, and `logger.max_backups`.

Source: https://heroiclabs.com/docs/nakama/getting-started/configuration/

Nakama metrics:

- Nakama can export Prometheus metrics by setting `metrics.prometheus_port`; default `0` disables Prometheus export.
- Heroic Labs says metrics exports should be protected because they contain sensitive server information.

Source: https://heroiclabs.com/docs/nakama/getting-started/configuration/

Nakama health:

- The official Compose file uses `/nakama/nakama healthcheck` as the container healthcheck.
- Project0's deploy script already treats declared Docker healthchecks as the deploy proof and rolls back on failure, so a Nakama service with a healthcheck fits the existing deployment safety model.

Sources: https://raw.githubusercontent.com/heroiclabs/nakama/master/docker-compose-postgres.yml, local `scripts/deploy_containers.sh`.

Nakama Console observability:

- Console dashboard shows real-time per-node latency, RPC rate, inbound bandwidth, and outbound bandwidth.
- Console can inspect players, groups, storage, leaderboards, chat messages, matches, payments, notifications, runtime modules, and configuration.

Source: https://heroiclabs.com/docs/nakama/getting-started/console/

## Admin console use

The Console is useful for operations and support, but it is also a high-risk admin surface:

- It defaults to port `7351` and default credentials `admin`/`password` unless changed.
- It can manage player accounts and storage, ban/delete/export users, moderate chat, inspect active matches, run API Explorer calls/custom RPCs, manage console users/roles, export configuration, upload storage data, and reset Nakama player data.
- The data reset action permanently removes players, groups, chat, storage, payments, notifications, and leaderboards and is irreversible.

Source: https://heroiclabs.com/docs/nakama/getting-started/console/

Project0 posture: bind Console to loopback or an admin-only network first. Do not expose `7351` publicly during playtests. If remote admin is needed, prefer the existing operator/admin access pattern or a reverse proxy protected by Project0's chosen admin auth.

## Scaling limits

Open-source self-hosting should be planned as a single Nakama node unless Project0 buys/adopts an Enterprise/Heroic Cloud topology. Heroic Labs marks cluster and multi-node tracker configuration as Nakama Enterprise-only and says production HA clustering uses Nakama Enterprise or Heroic Cloud. Source: https://heroiclabs.com/docs/nakama/getting-started/configuration/

Single-node tuning knobs exist for queues/workers and runtime counts, including match, leaderboard, tracker, matchmaker, and runtime settings. These are capacity knobs, not HA clustering. Source: https://heroiclabs.com/docs/nakama/getting-started/configuration/

Database scale is a separate concern. The configuration supports multiple `database.address` entries and DB connection pool settings such as max idle/open connections, but that does not by itself make the open-source Nakama app tier clustered. Source: https://heroiclabs.com/docs/nakama/getting-started/configuration/

## Upgrades and migrations

Nakama upgrades are schema-bearing:

- `nakama migrate up` creates or updates the database schema to the latest version required by the Nakama binary.
- New Nakama releases may require running migrations.
- `migrate status` reports applied/unapplied schemas.
- `migrate down` can downgrade schema changes, one by one by default, or to a requested limit.

Source: https://heroiclabs.com/docs/nakama/getting-started/commands/

Project0 deployment implication:

- Do not let the deployment script run `migrate up` without a pre-migration database backup and a tested restore path.
- Current Project0 rollback redeploys the previous image tag after health failure. That is sufficient for stateless containers, but not sufficient for Nakama if the failed new image already changed the DB schema.
- A Nakama rollback runbook must define whether rollback is image-only, DB-restore, `migrate down`, or restore-to-new-DB-and-switch. For playtests, the simplest defensible rule is: backup first, migrate second, health/smoke third, and restore DB if reverting across a schema boundary.

## Rollback posture

Current Project0 deploy safety model from `scripts/deploy_containers.sh`:

- Pull immutable images before stopping current service.
- `docker compose up -d --remove-orphans`.
- Wait for all healthchecks.
- Run smoke checks.
- Record deployed tag only after health and smoke pass.
- Roll back to the previous tag on failed health/smoke.

Nakama can reuse most of that, but database migrations weaken image-only rollback. Treat the Nakama database backup as part of the deployment artifact set for any release that changes Nakama version, server modules, auth model, wallet/ledger/storage schema expectations, or runtime code.

## Fit with Project0 Docker/server deployment

Best fit:

- Add Nakama behind the existing Compose deployment rather than replacing `game-server` immediately.
- Keep Project0's current data convention: `/var/lib/project0/nakama` and `/var/lib/project0/nakama-postgres` or Docker named volumes with documented backup paths.
- Keep Project0's current secret convention: `/etc/project0/nakama.env` or Compose secrets, never repo-tracked credentials.
- Bind public client API `7350` only if the Godot client will call Nakama directly. Otherwise keep Nakama internal and route through enrollment/login/backend code.
- Bind Console `7351` to loopback/admin-only access.
- Add a Nakama-specific smoke check that hits a non-destructive API/health path and, if Console is enabled, does not exercise destructive console APIs.

Likely conflicts and decisions:

- Project0 currently has bespoke login/session assertions and UDP game server authority. Nakama has its own sessions and socket model. A separate product decision is required before consolidating identity or realtime traffic.
- Project0 currently uses SQLite for account/canon state in service volumes. Nakama adds PostgreSQL, so backups and restore drills become multi-store.
- Project0's image rollback is not enough for Nakama schema migrations. DB rollback needs a separate runbook.
- Admin console access overlaps with the existing operator/dashboard idea but has broader destructive powers.

## Blocked or uncertain facts

- Official Nakama docs inspected here disagree on the database statement: Docker install/config examples use PostgreSQL, while the server configuration page says CockroachDB is required. This must be confirmed with Heroic Labs docs/support before production commitment.
- The inspected official docs establish Enterprise-only clustering controls but do not provide an open-source multi-node HA recipe. Assume no OSS app-tier clustering unless a newer official source says otherwise.
- No Project0 decision exists in this ticket about whether Nakama replaces login/session, supplements it, or only supports future social/matchmaking/live-ops features. This report only covers operations.
- No runtime load target was provided. Capacity and instance sizing cannot be computed from the official docs alone; it needs Project0 playtester concurrency and feature usage assumptions.
