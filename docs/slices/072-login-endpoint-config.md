# Slice 072 — Login-endpoint config: `NetworkConfig.resolve_login_port`
GitHub issue: #95

Status: **delivered**

Phase: 10 (Authoritative runtime and action input), advancing
[P-014](../FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)
and the [login-boundary decision](../../.scratch/container-platform/issues/02-account-login-service-boundary.md).
Eighteenth delivery of the [container-platform map](../../.scratch/container-platform/map.md);
it is the **config foundation for the client cutover**: one shared resolver for
the login endpoint's UDP port so the client, the login server, and future harness
all agree on where the login process listens.

## User outcome

The login server's port is resolved from one place (`NetworkConfig`) with the
same CLI/env/default precedence as the game port, so the client can be pointed at
the login process and the login server can never disagree with the client about
its default port.

## Scope and non-goals

In scope:
- `NetworkConfig.LOGIN_PORT` (default 9998) + `resolve_login_port()`
  (`--login-port=<n>` CLI, then `PROJECT0_LOGIN_PORT` env, then default),
  reusing the existing `_parse_port` bounds check.
- `server/login_server_main.gd` unifies on `NetworkConfig.resolve_login_port()`
  (dropping its local default/resolver duplicate), so client and server share one
  default.

Out of scope (later sub-slices): the multi-process login→game handoff e2e harness
(Slice 073); rewiring the login-screen scenes; dropping the game server's
in-process login; the DB split on disk. This slice only adds the shared endpoint
config the cutover depends on.

## Public seam

- `shared/network_config.gd` (`LOGIN_PORT`, `resolve_login_port()`,
  `LOGIN_PORT_CLI_ARG`, `LOGIN_PORT_ENV_VAR`).

## Safety invariant

`resolve_login_port()` reuses `_parse_port`, so a malformed CLI/env override can
never bind port 0 or an out-of-range port — it falls back to the bounded default.
The resolver lives in `shared/` (a versioned value contract both processes may
read); it carries no authority or secret.

## ADR rationale

No new ADR. This mirrors the existing `resolve_server_port` seam for a second
endpoint the login split needs.

## BDD / TDD

`tests/unit/test_network_config_login_port.gd`: `resolve_login_port` returns the
`PROJECT0_LOGIN_PORT` env value when valid, falls back to `LOGIN_PORT` when unset
or malformed, and rejects an out-of-range value. The full GUT suite proves the
login server still boots on the unified resolver.

## Validation

- Focused + full suite: `scripts/run_gut_validation.sh` on the Linux host —
  **passed, 54/54 scripts, exit 0** (+1 new
  `tests/unit/test_network_config_login_port.gd`).
- `scripts/check_record_sync.sh` exit 0 (6 pre-existing WARN).

## Root-cause learning

None yet.
