# Slice 068 — Login runtime extraction + standalone login-server process
GitHub issue: #95

Status: **delivered**

Phase: 10 (Authoritative runtime and action input), advancing
[P-014](../FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)
and the [login-boundary decision](../../.scratch/container-platform/issues/02-account-login-service-boundary.md)
("login service = durable Account/Character authority … signed assertions").
Fourteenth delivery of the [container-platform map](../../.scratch/container-platform/map.md);
it is the **first sub-slice of the out-of-process login split** — it makes the
login authority a reusable, independently-bootable unit and stands up a separate
login-server process, without yet cutting the client over or removing login from
the game server.

## User outcome

The login authority (account register/login, Character CRUD, signed session
assertions) can run as its **own OS process** against its own accounts database,
distinct from the game server — the foundation for a separate login service and
future microservices.

## Scope and non-goals

In scope:
- `server/login_runtime.gd` (`LoginRuntime`): a server-only builder that wires
  `AuthService` + `CharacterService` + `LoginGateway` (with the Slice 059/060
  assertion issuer/validator) from an account repository, and resolves the
  shared assertion secret + issuer/audience identically for every entrypoint.
- Refactor `server/server_main.gd` to build its login subsystem via
  `LoginRuntime` (behavior-preserving; the game server is unchanged
  functionally).
- `server/login_server_main.gd`: a headless entrypoint that opens its own
  accounts DB, builds the `LoginRuntime`, hosts the register/login/Character RPC
  surface on a dedicated login port, and publishes a health file — **no**
  town/monsters/Canon/gameplay.

Out of scope (later sub-slices): cutting the client over to reach login through
the separate process; the game server accepting only assertions and dropping the
in-process login; splitting `accounts.sqlite3` from `canon.sqlite3` on disk; the
private transport hardening. This slice keeps the game server's in-process login
working (the preserved in-process adapter the decision calls for).

## Public seam

- `server/login_runtime.gd` (`LoginRuntime.build_services(account_repository,
  parent, secret, issuer, audience)`, `LoginRuntime.resolve_assertion_secret()`,
  `ASSERTION_ISSUER_ID`, `ASSERTION_AUDIENCE`).
- `server/login_server_main.gd` (standalone headless login process).

## Safety invariant

The login authority remains server-only: `LoginRuntime` and the login process
never live in `shared/` or `client/`. The assertion secret is resolved
identically on both entrypoints (env `PROJECT0_ASSERTION_SECRET`, else an
ephemeral per-boot key with a warning), so issuer and validator share one secret.
Character CRUD stays session-gated (the client never supplies an account id). The
login process refuses to start on a DB-open/schema failure (fail-closed), and
clears a peer's session on disconnect.

## ADR rationale

No new ADR. The login-boundary decision already mandates a durable
Account/Character authority behind a stable seam; this extracts the existing
wiring and boots it as its own process, reusing the Slice 058–060 gateway and
assertion contract rather than inventing a new one.

## BDD / TDD

`tests/integration/test_login_runtime.gd`: a `LoginRuntime` built standalone (its
own temp store, no game server) proves the full authority + trust flow —
register → login → create/select Character → issue a selected-Character
assertion → validate it with the matching validator → `establish_session_from_
assertion` binds a fresh peer with that Character; a validator with a different
secret rejects the token (the cross-process trust boundary). The unchanged
game-server suite proves the `server_main` refactor is behavior-preserving.

## Validation

- Focused + full suite: `scripts/run_gut_validation.sh` on the Linux host —
  **passed, 51/51 scripts, exit 0** (+1 new `tests/integration/test_login_runtime.gd`;
  the unchanged suite proves the `server_main` refactor is behavior-preserving).
- Runtime on Linux: `login_server_main.gd` boots on a dedicated port with its own
  temp accounts DB — `Login accounts database ready ... (schema ensured)`,
  `Login server listening on 127.0.0.1:19998`, and a `healthy` health file
  (`HC_OK`).
- `scripts/check_record_sync.sh` exit 0 (6 pre-existing WARN).

## Root-cause learning

None yet.
