# Slice 081 — Deploy the standalone login server via docker-compose (opt-in profile)
GitHub issue: #95

Status: **delivered**

Phase: 10 (Authoritative runtime and action input), advancing
[P-014](../FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)
and the [login-boundary decision](../../.scratch/container-platform/issues/02-account-login-service-boundary.md).
The standalone login process already exists ([Slice 068](068-login-runtime-and-standalone-process.md))
and has a systemd unit ([Slice 070](070-deploy-supervise-login-server.md)); this
slice makes it deployable in the **container** topology so a split deployment can
run both processes with `docker compose`, without changing the default single-
service behavior.

## User outcome

An operator can start the login authority alongside the game server with
`docker compose --profile login-split up`, giving two containers (game on its
port, login on its own) that share `PROJECT0_ASSERTION_SECRET` so the game server
validates login-minted assertions. A plain `docker compose up` is unchanged —
only the game server starts, with its ephemeral in-process key.

## Scope and non-goals

In scope:
- `deploy/game-server/docker-compose.yml`: a profile-gated `login-server`
  service that reuses the game-server image, overrides the entrypoint to run
  `server/login_server_main.gd`, and configures its own UDP port, accounts DB,
  and health file; plus a `PROJECT0_ASSERTION_SECRET` passthrough (empty default)
  on both services so they can share one secret.

Out of scope: changing any default (the login service is opt-in via the
`login-split` profile; the secret is empty by default = current behavior);
flipping `PROJECT0_CLIENT_LOGIN_SPLIT` or `PROJECT0_GAME_ASSERTION_ONLY`;
dropping the game server's in-process login; a dedicated login Dockerfile (the
shared image + entrypoint override is sufficient).

## Public seam

- `deploy/game-server/docker-compose.yml` (`login-server` service, `login-split`
  profile, shared `PROJECT0_ASSERTION_SECRET`).

## Safety invariant

The new service is gated behind a compose profile, so the default `docker compose
up` topology is byte-for-byte unchanged. `PROJECT0_ASSERTION_SECRET` defaults to
empty, preserving the game server's ephemeral per-boot key and current behavior.
No cutover: the game server keeps its in-process login unless separately run in
assertion-only mode. Stop/remove leaves the host unchanged.

## ADR rationale

No new ADR. This applies the existing runtime-boundary/container-adapter decision
to the login process, mirroring how the game server is containerized.

## Validation

- `docker compose config --services` on the Linux host: the **default** render
  lists only `game-server`; `--profile login-split` additionally lists
  `login-server`. The resolved `login-server` renders the login entrypoint
  (`server/login_server_main.gd`), port `19998→9998`, `login_accounts.db`,
  `/data/login_health.json`, and an empty-default `PROJECT0_ASSERTION_SECRET`;
  the game-server render carries the same secret key.
- Container runtime on the Linux host: built the candidate image and started the
  login container via `docker compose --profile login-split up -d login-server`
  — it reached Docker health **`healthy`** within ~10 s (`Login server listening
  on 0.0.0.0:9998`, health file `"status":"healthy"`), then torn down cleanly.
- `scripts/run_gut_validation.sh` on Linux — passed, 58/58 scripts, exit 0
  (unaffected; no GDScript changed).
- `scripts/check_record_sync.sh` exit 0.

## Root-cause learning

None. No unexpected failure surfaced during delivery.
