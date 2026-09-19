# Slice 085 — Remove in-process login from the game server
GitHub issue: #95

Status: **delivered**

Phase: 10 (Authoritative runtime and action input), advancing
[P-014](../FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)
and completing the [login-boundary decision](../../.scratch/container-platform/issues/02-account-login-service-boundary.md).
After the [084 cutover](084-login-split-cutover.md) the game server ran
assertion-only but still constructed the full account-authority graph
(`AuthService` with register/login/PBKDF2) behind a runtime opt-out. This slice
removes that: the game process builds an **assertion-only login graph with no
`AuthService`**, permanently committing to the split.

## User outcome

The game server holds no register/login/PBKDF2 code path and can never act as an
accounts authority — accounts live solely on the standalone login process. A
client still enters the world by presenting a signed assertion. The combined
single-process opt-out (`PROJECT0_GAME_ASSERTION_ONLY=0`) is gone.

## Scope and non-goals

In scope:
- `server/login_gateway.gd`: depend on a `SessionRegistry` directly for all
  session operations; `AuthService` becomes an optional collaborator (accounts
  authority) — a backward-compatible added third constructor arg so the login
  process and existing tests are unchanged.
- `server/login_runtime.gd`: `build_assertion_only_services()` builds the game
  graph (SessionRegistry + CharacterService + LoginGateway, no AuthService).
- `server/server_main.gd`: use the assertion-only builder; drop the
  `PROJECT0_GAME_ASSERTION_ONLY` opt-out and the `AuthService` handle; route
  disconnect session-clear through the gateway.

Out of scope: the login process keeps `build_services` (full authority with
`AuthService`) unchanged; the client split flag (`PROJECT0_CLIENT_LOGIN_SPLIT=0`
still selects the legacy client flow); deployment artifacts (the now-redundant
`PROJECT0_GAME_ASSERTION_ONLY=1` in the split overlay is harmless and left as-is).

## Public seam

- `server/login_runtime.gd` (`build_assertion_only_services`).
- `server/login_gateway.gd` (SessionRegistry-backed sessions; optional AuthService).

## Safety invariant

The login process's full authority path (`build_services` + `AuthService`) is
unchanged, and the `LoginGateway` constructor change is additive (third optional
arg), so every existing gateway/auth test constructs and behaves identically. The
assertion establish/issue path binds into the same `SessionRegistry` the
`CharacterService` reads, preserving cross-DB world entry. Nothing is deployed and
there are no clients, so removing the combined opt-out is safe.

## BDD / TDD

`tests/integration/test_login_runtime.gd` gains a case: the assertion-only graph
builds no `AuthService`, refuses register/Character-CRUD
(`account_authority_disabled`), yet establishes a session from a token minted by
the full login authority and carries the asserted Character.
`tests/integration/test_login_assertion_handoff.gd` now wires its game side via
`build_assertion_only_services`, so the cross-DB handoff test exercises the real
game-server graph.

## Validation

- `scripts/run_gut_validation.sh` on the Linux host — **passed, 58/58 scripts,
  exit 0**. The additive `LoginGateway` constructor kept every existing
  gateway/auth test passing; the new `test_login_runtime.gd` assertion-only case
  and the `build_assertion_only_services`-wired handoff test pass.
- Runtime on Linux: a headless boot of `server/server_main.gd` logged `assertion-only
  game server (accounts live on the login process)` and `Server listening`;
  `scripts/test_login_handoff_e2e.gd` printed **ALL PASS** — the game process,
  now building no `AuthService`, establishes the session from the login assertion
  (no shared DB) and enters the world as `Handoff Hero`.
- `scripts/check_record_sync.sh` exit 0.

## Root-cause learning

None. No unexpected failure surfaced during delivery.
