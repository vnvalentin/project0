# Slice 076 — Game server assertion-only mode: refuse account-authority RPCs

Status: **delivered**

Phase: 10 (Authoritative runtime and action input), advancing
[P-014](../FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)
and the [login-boundary decision](../../.scratch/container-platform/issues/02-account-login-service-boundary.md).
Twenty-second delivery of the [container-platform map](../../.scratch/container-platform/map.md);
it lets the game server **refuse to be an accounts authority** — accepting only
the assertion-established session + world entry — so a split deployment enforces
that accounts live only on the login process.

## User outcome

An operator can run the game server in assertion-only mode, where it rejects
register/login/Character-CRUD over the wire (those belong to the login process)
and accepts only a signed assertion to establish a session and enter the world.
The mode is opt-in (`PROJECT0_GAME_ASSERTION_ONLY=1`) so the current
single-connection client — whose login screen still authenticates on the game
server until the UI is rewired — keeps working by default.

## Scope and non-goals

In scope:
- `server/login_gateway.gd`: an `account_authority_enabled` flag (default true);
  when disabled, `register`/`login`/`list_characters`/`create_character`/
  `select_character`/`delete_character` return a bounded
  `REASON_ACCOUNT_AUTHORITY_DISABLED`. The assertion path
  (`establish_session_from_assertion`, `get_selected_character` via the snapshot,
  `is_authenticated`, `clear_session`) is unaffected.
- `server/login_runtime.gd`: `build_services(..., account_authority := true)`
  flows the flag to the gateway.
- `server/server_main.gd`: resolves `PROJECT0_GAME_ASSERTION_ONLY` and builds its
  gateway account-authority-disabled when set; the login process keeps it enabled.

Out of scope (later slices): rewiring the client login screen to authenticate on
the login process (which then lets this mode default on); removing the game
server's accounts repository/wiring entirely; the `accounts.sqlite3` /
`canon.sqlite3` split on disk; durable world-state persistence. This slice adds
the enforceable boundary switch; flipping the default and dropping the wiring
follow once the client UI uses the login process.

## Public seam

- `server/login_gateway.gd` (`set_account_authority_enabled`,
  `REASON_ACCOUNT_AUTHORITY_DISABLED`).
- `server/login_runtime.gd` (`build_services(..., account_authority)`).
- `server/server_main.gd` (`PROJECT0_GAME_ASSERTION_ONLY`).

## Safety invariant

With account authority disabled, no register/login/CRUD reaches the accounts
repository — a client cannot create or mutate accounts on the game server; those
operations fail closed with a bounded reason. The assertion path is unchanged:
the game still validates a signed assertion and binds a Player from the snapshot,
so world entry works. Default-enabled preserves every existing flow and test.

## ADR rationale

No new ADR. The login-boundary decision already makes accounts a login-service
authority; this adds the switch that enforces it on the game server without
breaking the pre-cutover client.

## BDD / TDD

`tests/integration/test_login_gateway_assertion_only.gd`: a gateway with account
authority disabled rejects `register`/`login`/`list`/`create`/`select`/`delete`
with `REASON_ACCOUNT_AUTHORITY_DISABLED` and binds nothing, yet still establishes
a session from a valid assertion and resolves `get_selected_character` from the
signed snapshot (world entry still works). The default-enabled gateway suite
proves existing behavior is unchanged.

## Validation

- Focused + full suite: `scripts/run_gut_validation.sh` on the Linux host —
  **passed, 56/56 scripts, exit 0** (+1 new
  `tests/integration/test_login_gateway_assertion_only.gd`: register/login/CRUD
  refused with `REASON_ACCOUNT_AUTHORITY_DISABLED`, assertion establish + snapshot
  world entry still succeed; the default-enabled gateway suite is unchanged).
- `scripts/check_record_sync.sh` exit 0 (6 pre-existing WARN).

## Root-cause learning

None yet.
