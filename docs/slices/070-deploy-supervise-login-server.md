# Slice 070 — Deploy + supervise the standalone login server
GitHub issue: #95

Status: **delivered**

Phase: 10 (Authoritative runtime and action input), advancing
[P-014](../FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)
and both the [runtime-boundary decision](../../.scratch/container-platform/issues/01-runtime-boundary-and-container-adapter.md)
(native systemd supervision, health-file liveness) and the
[operator control-plane decision](../../.scratch/container-platform/issues/04-operator-control-plane-and-telemetry.md)
(the admin interface manages allowlisted services). Sixteenth delivery of the
[container-platform map](../../.scratch/container-platform/map.md); it makes the
standalone login process ([Slice 068](068-login-runtime-and-standalone-process.md))
an operable, supervised service.

## User outcome

The separate login server runs as a supervised systemd service that restarts on
failure, and the operator control plane can inspect, restart, start, and stop it
by name — the login process becomes a first-class deployable service alongside
the game server and enrollment.

## Scope and non-goals

In scope:
- `scripts/project0-login.service`: a systemd unit that runs
  `server/login_server_main.gd` (mirroring `scripts/project0-server.service`),
  with the login-specific environment (own accounts DB, dedicated port, health
  file) via an optional `EnvironmentFile`.
- Add `login-server` → `("systemd", "project0-login")` to the operator control
  plane's `DEFAULT_SERVICES` allowlist so status/restart/start/stop reach it.
- Operator config test coverage and README allowlist update; deploy docs note.

Out of scope (later sub-slices): a container/compose variant of the login
service (the image entrypoint currently hard-runs the game server); the client
connection-UX cutover to the login process; sharing one
`PROJECT0_ASSERTION_SECRET` across the game and login units (only needed once the
client presents login assertions to the game server — a Slice 071 concern); the
login/game DB split on disk.

## Public seam

- `scripts/project0-login.service` (systemd unit).
- `infra/operator/config.py` (`DEFAULT_SERVICES` gains `login-server`).

## Safety invariant

The operator allowlist stays closed: `login-server` maps to exactly the
`project0-login` unit, inspected/managed only through the existing
fixed-argument-vector seam (no shell). The unit runs non-root with
`NoNewPrivileges`, binds its own dedicated port, and uses its own accounts DB —
it never shares the game server's Canon store. The assertion secret note: until
the client presents login assertions to the game server (Slice 071), the login
process may run with its own ephemeral key; the shared-secret requirement is
documented as a forward dependency.

## ADR rationale

No new ADR. Native systemd supervision and operator-managed allowlisted services
are already the accepted runtime-boundary and operator decisions; this registers
the login process under both.

## BDD / TDD

`infra/operator/tests/test_config.py`: `DEFAULT_SERVICES` includes
`login-server` mapped to `("systemd", "project0-login")`, so the operator can
manage it and an off-allowlist name stays fail-closed. The existing operator
suite (status/restart/start/stop over the allowlist) then covers the new service
by construction.

## Validation

- Focused: `python -m pytest infra/operator/tests` on the Linux host — **63 passed**
  (+1 new `test_login_server_is_in_the_allowlist`); the existing
  status/restart/start/stop suite covers the new service by construction.
- `scripts/check_record_sync.sh` exit 0 (6 pre-existing WARN); GUT unaffected
  (no `.gd` change).

## Root-cause learning

None yet.
