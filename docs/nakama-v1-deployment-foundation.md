# Nakama v1 Deployment Foundation

This runbook is the Slice 166 deployment foundation for the Nakama v1 plan
([Goal #354](https://github.com/vnvalentin/project0/issues/354),
[issue #355](https://github.com/vnvalentin/project0/issues/355)). It defines
the operational contract before any auth, Character, world-entry, or gameplay
bridge code depends on Nakama.

## Topology

Run Nakama as an opt-in Docker Compose profile beside the existing Project0
stack:

- `nakama-db`: PostgreSQL `16.8-alpine`, durable data under
  `/var/lib/project0/nakama-postgres` by default.
- `nakama`: Heroic Labs Nakama pinned by `NAKAMA_IMAGE_TAG` with default
  `3.37.0`, configured by a host-mounted YAML file under
  `/etc/project0/nakama` by default.

The v1 posture is single-node self-hosted Nakama. It is not a high-availability
or clustered topology.

## Pre-implementation database verification

The Wayfinder operations research found inconsistent official documentation:
current Docker examples use PostgreSQL, while another configuration page still
mentions CockroachDB. Before any production or playtest deployment, verify the
selected Nakama release's current database support against the official Heroic
Labs documentation or support channel. This foundation uses PostgreSQL because
that is the current official Docker Compose path researched for the map.

## Public and private surfaces

Only Nakama's client API/realtime socket surface is public in v1:

- `7350`: bind with `NAKAMA_BIND`; this is the client HTTP/socket endpoint.
- `7351`: Nakama Console, bound to `127.0.0.1` by default through
  `NAKAMA_CONSOLE_BIND`; keep it loopback or admin-network only.

Do not publish gRPC, console gRPC, metrics, or destructive admin/operator
surfaces to the public internet. If remote administration is needed later, put
it behind the existing Project0 admin access model rather than widening this
compose file's public ports.

## Secrets and config

Secrets stay on the host, outside the repository and images:

- `/etc/project0/nakama-db.env`: PostgreSQL credentials such as
  `POSTGRES_USER`, `POSTGRES_PASSWORD`, and `POSTGRES_DB`.
- `/etc/project0/nakama/nakama.yml`: Nakama configuration, including the
  database address, `socket.server_key`, `session.encryption_key`,
  `runtime.http_key`, and Console credentials.
- `/etc/project0/nakama-relay.env`: optional `PROJECT0_NAKAMA_RELAY_TOKEN`
  containing a dedicated Nakama user session token for the Project0 server's
  shared-match relay. This token is never committed or passed to clients; omit
  the file to keep the legacy ENet/RPC path active.

The game container reaches the client API/socket through
`PROJECT0_NAKAMA_URL`, defaulting to `http://192.168.1.254:7350` in the
deployment compose. Override it when Nakama is hosted elsewhere.

Rotate every Nakama default key/password before any playtest. The deployment is
not playtest-ready if it uses `defaultkey`, `defaultencryptionkey`,
`defaulthttpkey`, or Console `admin`/`password` defaults.

## Backup-before-migration gate

Nakama migrations are schema-bearing. Before changing Nakama version, runtime
modules, auth model, storage schema expectations, or database configuration:

1. Back up the PostgreSQL database, preferably with a custom-format `pg_dump`
   for small playtests.
2. Back up `/etc/project0/nakama-db.env` and `/etc/project0/nakama/nakama.yml`
   into the operator's secured backup path.
3. Record the current `NAKAMA_IMAGE_TAG` and Project0 image tag.
4. Run the migration and health/smoke checks.
5. If rollback crosses a schema boundary, choose and document one of:
   restore database backup, run a verified `migrate down`, or switch to a
   known-good restored database. Image-only rollback is not sufficient.

## Validation

Run the static foundation check from the repository root:

```bash
python scripts/check_nakama_deployment_foundation.py
```

This check proves the committed deployment contract stays aligned with the v1
Wayfinder decisions. Live deployment, auth/session smoke, Character smoke,
world-entry smoke, and bridge/presence smoke are later implementation issues
under Goal #354.

## V1 smoke and operations gate

The manifest-backed Slice 172 gate validates the full required stage list while
keeping unimplemented player-flow stages explicitly named rather than silently
passing them:

```bash
python scripts/check_nakama_v1_smoke.py
```

Static mode runs the deployment foundation check and does not need Docker,
credentials, or a live service. An operator may explicitly probe a live Nakama
health endpoint with:

```bash
PROJECT0_NAKAMA_SMOKE_URL=https://nakama.example.test \
  python scripts/check_nakama_v1_smoke.py --live
```

The live mode performs one bounded unauthenticated GET, prints only the HTTP
status/result class, and never prints response bodies or secrets. A static pass
does not claim that login, Character CRUD, world-entry, or bridge/presence
player flows are already implemented; those remain the named stages for the
later Goal #354 slices.