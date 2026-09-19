# Slice 078 — Wire login-screen gates to the login process (opt-in client flag)
GitHub issue: #95

Status: **delivered**

Phase: 10 (Authoritative runtime and action input), advancing
[P-014](../FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)
and the [login-boundary decision](../../.scratch/container-platform/issues/02-account-login-service-boundary.md).
Twenty-fourth delivery of the [container-platform map](../../.scratch/container-platform/map.md);
it makes the **real client** perform the cutover: the account/character screens
authenticate on the login process, then hand off to the game process via the
Slice 077 seam — behind an opt-in flag so the default single-connection flow is
untouched.

## User outcome

With `PROJECT0_CLIENT_LOGIN_SPLIT=1`, a player uses the actual login/character
screens to register/log in and pick a Character on the login server, then "enter
world" hands off to the game server and drops them into gameplay — the full
split flow through the real UI, not just a harness. Default (flag off) keeps the
current single-connection flow.

## Scope and non-goals

In scope:
- `shared/network_config.gd`: `client_login_split_enabled()`
  (`PROJECT0_CLIENT_LOGIN_SPLIT=1`, default off).
- `client/account_gate.gd`: connect to the login endpoint (login port) for
  register/login when the split is enabled; the game port otherwise.
- `client/character_gate.gd`: on Character select, call
  `NetworkClient.perform_login_to_game_handoff(host, game_port)` when the split
  is enabled (success flows through the existing `world_entry_received`
  transition); `submit_enter_world` otherwise.

Out of scope (later slices): flipping `PROJECT0_GAME_ASSERTION_ONLY` on by
default; removing the game server's accounts wiring; the `accounts`/`canon` DB
split on disk; durable world-state persistence. This slice only routes the UI
through the login process behind the flag.

## Public seam

- `shared/network_config.gd` (`client_login_split_enabled`).
- `client/account_gate.gd`, `client/character_gate.gd` (endpoint + handoff wiring).

## Safety invariant

The client change is behind an opt-in env flag; with it unset every existing
flow, scene, and test is unchanged. When enabled, the UI drives only the proven
public seams (`connect_to_server`, `submit_*`, `perform_login_to_game_handoff`)
and the server owns every outcome. No secret or account data is stored on the
client beyond the returned `AccountHandle` and selected Character (unchanged).

## ADR rationale

No new ADR. This is the UI application of the already-proven client handoff seam,
completing the client side of the login-boundary decision.

## BDD / TDD

`tests/unit/test_network_config_client_split.gd`: `client_login_split_enabled`
returns true only for `PROJECT0_CLIENT_LOGIN_SPLIT=1` and false when unset/other.
The client UI smoke runner (`scripts/run_client_ui_smoke.gd`) confirms the
account/character/gameplay scenes still load and expose their controls after the
wiring. The full cutover mechanism the gates call is already proven end-to-end by
`scripts/test_login_handoff_e2e.gd` (Slice 077). The GUI flow itself is validated
by structure + the proven seam; a live two-server GUI run is a manual check.

## Validation

- Full suite: `scripts/run_gut_validation.sh` on the Linux host — **passed, 57/57
  scripts, exit 0** (adds `tests/unit/test_network_config_client_split.gd`).
- UI smoke: `godot --headless --path . -s scripts/run_client_ui_smoke.gd` on
  Linux — `client-ui-summary.json` status **`passed`** (account/character/gameplay
  scenes load with all required controls; the wgnetstack GDExtension load errors
  are pre-existing worktree noise unrelated to the check).
- The cutover mechanism the gates call is already proven end-to-end by
  `scripts/test_login_handoff_e2e.gd` (Slice 077, ALL PASS on Linux).
- `scripts/check_record_sync.sh` exit 0.

## Root-cause learning

None. No unexpected failure surfaced during delivery.
