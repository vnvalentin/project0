# Slice 084 — Login-split cutover: split on by default
GitHub issue: #95

Status: **delivered**

Phase: 10 (Authoritative runtime and action input), advancing
[P-014](../FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)
and completing the [login-boundary decision](../../.scratch/container-platform/issues/02-account-login-service-boundary.md).
The split is proven end-to-end and has a one-command launcher
([083](083-split-launcher-shared-secret.md)); nothing is deployed and there are
no live clients, so the cutover is safe to make. This slice flips the two code
defaults so the login split is the canonical topology.

## User outcome

By default the client authenticates on the login process and hands off to the
game process, and the game server runs assertion-only (accounts live only on the
login server). The legacy single-connection / in-process-login mode is still
reachable for combined single-process development via explicit opt-outs.

## Scope and non-goals

In scope:
- `shared/network_config.gd`: `client_login_split_enabled()` defaults **on**;
  `PROJECT0_CLIENT_LOGIN_SPLIT=0` selects the legacy single-connection flow.
- `server/server_main.gd`: the game server runs **assertion-only by default**;
  `PROJECT0_GAME_ASSERTION_ONLY=0` re-enables the in-process login for a combined
  single-process run.
- `tests/unit/test_network_config_client_split.gd`: updated for the new default.

Out of scope: removing the game server's in-process login code (still reachable
via the opt-out); changing the ENet/port contracts; new deployment artifacts
(the split overlay, profile, and `run-split.sh` already exist).

## Public seam

- `shared/network_config.gd` (`client_login_split_enabled` default).
- `server/server_main.gd` (`PROJECT0_GAME_ASSERTION_ONLY` default).

## Safety invariant

Both flags keep an explicit `=0` escape hatch, so a combined single-process run
is still possible (`PROJECT0_CLIENT_LOGIN_SPLIT=0` + `PROJECT0_GAME_ASSERTION_ONLY=0`).
The change is pure default-selection; the already-proven split code paths are
unchanged. Safe now because nothing is deployed and no client is configured.

## ADR rationale

No new ADR. This is the final default-selection step of the already-approved
login-boundary decision; the mechanisms were delivered and validated in slices
074–083.

## BDD / TDD

`tests/unit/test_network_config_client_split.gd`: `client_login_split_enabled`
is true when unset and for non-`0` values, and false only for
`PROJECT0_CLIENT_LOGIN_SPLIT=0`.

## Validation

- `scripts/run_gut_validation.sh` on the Linux host — **passed, 58/58 scripts,
  exit 0** (the updated `test_network_config_client_split.gd` encodes the new
  default; suite stayed green).
- Runtime on Linux: a headless boot of `server/server_main.gd` with no env logged
  `assertion-only mode: true`; with `PROJECT0_GAME_ASSERTION_ONLY=0` it logged
  `assertion-only mode: false`. The login→game handoff e2e
  (`scripts/test_login_handoff_e2e.gd`) printed **ALL PASS** with the game server
  now assertion-only by default — including `world_entry` ok and the bound Player
  named `Handoff Hero`.
- `scripts/check_record_sync.sh` exit 0.

## Root-cause learning

None. No unexpected failure surfaced during delivery.
