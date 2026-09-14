# Project0 Runtime Platform and Service Boundaries

## Destination

Produce a handoff-ready architecture and staged delivery route for a controlled
Project0 runtime platform: a containerized authoritative game server, a
separate Account/login service, a private operator control plane for lifecycle
operations and telemetry, and explicit extension seams for future world-builder
and mobile-object workers.

The map is complete when runtime ownership, service boundaries, contracts,
persistence, security, deployment, migration, rollback, observability, and
future worker integration are decided well enough to create implementation
slices without guessing.

## Notes

- Domain: Linux deployment, Godot headless authority, containers, service
  boundaries, Account authentication, SQLite persistence, WireGuard access,
  operator operations, telemetry, and controlled updates.
- Planning mode: this map produces decisions and handoff material. It does not
  implement containerization or service code while charting.
- Current reality: the Godot game server runs as a native systemd process;
  enrollment runs as a separate systemd Python/uvicorn process; the read-only
  flow dashboard runs in Docker. P-014 (containerized fixed-tick authoritative
  server runtime) is planned, not delivered.
- Standing constraints: preserve the current native server as rollback during
  migration; keep OPNsense and client private keys outside the game container;
  keep the public enrollment route separate from operator controls; preserve
  server authority over gameplay and world state.
- Skills: `codebase-design`, `domain-modeling`, `grilling`, `research`,
  `prototype` when a concrete operator or deployment artifact is needed.
- Delivery rule: each resulting implementation slice needs a public seam,
  SDD/BDD/TDD evidence, bounded telemetry, rollback, and synchronized records.

## Decisions so far

- [Runtime platform destination](map.md): pause Wave 5 implementation work as
  the current priority and chart the controlled platform route before starting
  P-014 or splitting additional services.
- [Runtime compatibility posture](map.md): use the host-compatible container
  runtime initially, preserve systemd as the lifecycle supervisor where useful,
  and avoid committing to Docker-versus-Podman until the real Linux host is
  inspected.
- [Service decomposition posture](map.md): separate Account/login authority
  from the authoritative game server, while designing future world-builder and
  mobile-object workers as extension seams rather than first-wave services.
- [Migration posture](map.md): run the container beside the native server or on
  a separate port/host, prove equivalence and rollback, then cut over.
- [Runtime boundary and container adapter](issues/01-runtime-boundary-and-container-adapter.md):
  use an OCI-compatible Dockerfile/Compose deployment with systemd supervising
  the host lifecycle; deploy the application under `/apps/project0`, keep
  persistent state under `/var/lib/project0`, expose UDP 9999, and preserve
  the native service as rollback.
- [Account and login service boundary](issues/02-account-login-service-boundary.md):
  preserve the existing authentication implementation as an in-process adapter,
  make the login service the durable Account/Character authority, and use
  account-only then selected-Character signed assertions across the future
  private HTTPS service seam.
- [Persistence and data ownership](issues/03-persistence-and-data-ownership.md):
  on Linux host `192.168.1.254`, keep `/apps/project0` for application
  deployment, split login and game SQLite ownership under `/var/lib/project0`,
  back up under `/var/backups/project0`, and migrate the current database once
  with the native path retained for rollback.
- [Operator control plane and telemetry](issues/04-operator-control-plane-and-telemetry.md):
  a private, operator-authenticated control service with an allowlisted
  status/telemetry/logs/invite/revoke/service/update interface, a bounded job
  and audit model, and no arbitrary shell execution or public exposure.
- [Migration, update, and rollback protocol](issues/05-migration-update-and-rollback.md):
  run the container beside the native server, gate on health and equivalence,
  deploy by pinned digest, migrate persistence with a retained rollback copy,
  and retire the native service only after rollback evidence.
- [Future worker extension contract](issues/06-worker-extension-contract.md):
  one bounded, idempotent, deadline-bounded job contract for future
  world-builder and mobile-object workers whose output stays provisional until
  server-side validation; no worker is implemented by this decision.

## Not yet specified

- None. The route to the destination is charted; every decision ticket is
  resolved. Implementation proceeds as bounded SDD/BDD/TDD slices under the
  repository workflow, sequenced by the migration/rollback decision.

## Out of scope

- Building the container image or migrating the production host while this map
  is being charted.
- Replacing OPNsense WireGuard or embedding OPNsense credentials in the game
  server container.
- Public internet exposure of operator controls.
- Designing gameplay mechanics, world-generation schema details, or mobile
  object behavior before their worker contract is decided.
- Cloud-hosted identity, managed Kubernetes, or a cloud control plane.
