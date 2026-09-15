# Slice 082 — Containerized login-split e2e (compose split overlay + two-container handoff)

Status: **delivered**

Phase: 10 (Authoritative runtime and action input), advancing
[P-014](../FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)
and the [login-boundary decision](../../.scratch/container-platform/issues/02-account-login-service-boundary.md).
The login split is proven at the process level ([075](075-cross-db-world-entry.md),
[077](077-client-login-handoff-seam.md)) and the login server is now
compose-deployable ([081](081-deploy-login-server-compose.md)). This slice
proves the **whole split works in containers**: a client registers/selects on the
login container and enters the world on the game container (assertion-only), over
real ENet, using a shared assertion secret.

## User outcome

An operator can run the split topology with a single documented command —
`PROJECT0_ASSERTION_SECRET=<hex> docker compose -f docker-compose.yml -f
docker-compose.split.yml --profile login-split up` — getting a login container
(accounts authority) and a game container running assertion-only (accounts
disabled), and a real client can log in on the login container and enter the
world on the game container. The default `docker compose up` is unchanged.

## Scope and non-goals

In scope:
- `deploy/game-server/docker-compose.split.yml`: a small overlay that sets
  `PROJECT0_GAME_ASSERTION_ONLY=1` on the game server so the split topology runs
  the game process as accounts-disabled; both services already share
  `PROJECT0_ASSERTION_SECRET` from the base file.
- A containerized end-to-end validation using the existing
  `scripts/login_handoff_client_harness.gd` against the two published ports.

Out of scope: changing any behavior default (the overlay and the login-split
profile are opt-in; `PROJECT0_GAME_ASSERTION_ONLY` stays off in the base file);
flipping the client's `PROJECT0_CLIENT_LOGIN_SPLIT`; new production code (this is
a deployment overlay plus a runtime proof).

## Public seam

- `deploy/game-server/docker-compose.split.yml` (split-topology overlay).
- The containerized handoff (login container → game container) exercised through
  `NetworkClient.perform_login_to_game_handoff` from the client harness.

## Safety invariant

The overlay is a separate file applied only when explicitly passed with `-f`, and
`PROJECT0_GAME_ASSERTION_ONLY` stays unset in the base file, so `docker compose
up` behavior is unchanged. The game server, when assertion-only, refuses account
RPCs and never reads accounts — accounts authority lives only on the login
container. Validation runs in temp data dirs on isolated host ports and is torn
down.

## ADR rationale

No new ADR. This is the container-runtime realization of the login-boundary
decision, proving the already-approved split in the target runtime.

## Validation

- `docker compose -f docker-compose.yml -f docker-compose.split.yml --profile
  login-split config` on the Linux host renders game-server with
  `PROJECT0_GAME_ASSERTION_ONLY: "1"`, both services carrying the shared
  `PROJECT0_ASSERTION_SECRET`, and the login-server present.
- Container e2e on the Linux host: brought up both containers with a shared
  `openssl rand -hex 32` secret (game logged `assertion-only mode: true`,
  `Server listening on 0.0.0.0:9999`; both reached Docker health `healthy` in
  ~10 s), then ran `scripts/login_handoff_client_harness.gd` from the host
  against the published ports (login 19998, game 19999). The written state
  reported `login_connected/registered/character_selected/assertion_received/
  game_connected` true, `session_established: ok`, and **`world_entry: ok`** with
  `world_character_name: "Handoff Hero"` — the client registered/selected on the
  login container and entered the world on the assertion-only game container.
  Containers and temp data dirs torn down.
- `scripts/run_gut_validation.sh` on Linux — passed, 58/58 scripts, exit 0
  (unaffected; no GDScript changed).
- `scripts/check_record_sync.sh` exit 0.

## Root-cause learning

None. The one surprise — the harness process exiting via `timeout` (code 124)
rather than self-quitting — is expected: this harness idles after reaching
`phase: done` and is normally reaped by its orchestrator; the written state file
(`world_entry: ok`) is the authoritative success signal.
