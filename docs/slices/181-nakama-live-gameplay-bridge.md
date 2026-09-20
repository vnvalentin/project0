# Slice 181 - Live Nakama gameplay bridge

GitHub issue: #372

Status: **in-progress**

Phase: 12 (Authoritative runtime and action input)

Feature: [F-039](../FEATURE-LIST.md#f-039-nakama-v1-entry-and-realtime-foundation)

## User outcome

A Nakama-authenticated client can enter the shared Project0 world and send
bounded movement/action input through the Nakama socket, while Project0 remains
the sole authority for identity binding, simulation, and returned state.

## Scope and non-goals

In scope: create the server bridge at world entry, connect the client bridge to
the authenticated Nakama socket, route gameplay input and authoritative state,
handle disconnect/reconnect and bounded errors, and prove the path with two
live clients.

Out of scope: automatic matchmaking, world sharding, Nakama-owned Character or
Canon state, and replacing the existing direct ENet/RPC compatibility path.

## Public seam

The existing world-entry/ticket binding creates the bridge binding for the
peer's server-owned `ServerPlayerState`. The client gameplay input seam selects
the opt-in Nakama adapter; the existing ENet/RPC path remains the default.

## Falsifiable hypothesis

If world entry creates exactly one identity-bound bridge binding and the client
routes only validated input envelopes through it, then two Nakama clients can
exchange authoritative movement/action state without granting Nakama or the
client simulation authority.

## Validation

Focused bridge tests and parse checks, full GUT validation, record-sync, and an
executable two-client live Nakama-to-Project0 input/state proof covering invalid
identity, duplicate sequence, disconnect/reconnect, and backpressure/error
handling.

## Safety invariants

- Client and Nakama never supply authoritative identity, position, tick, or
  outcomes.
- Only the consumed world-entry binding can dispatch input.
- Failed or disconnected transport fails closed without mutating Player state.
- Direct ENet/RPC remains available as the rollback path.

## Root-cause learning

The missing vertical path was confirmed to be wiring, not a second simulation
authority: the existing bridge and ticket contract had no server socket relay,
no world-entry binding call, and no client transport selection. The focused
fake relay/bridge tests now exercise those seams without credentials. A second
review exposed a reconnect defect where a disconnected Nakama identity could
remain bound; the server now unbinds the relay before clearing the Project0
session, and the regression test covers rebind eligibility. Direct
`--check-only -s client/network_client.gd` still exits 1 without a diagnostic;
the headless editor load emits no NetworkClient or Nakama parser diagnostic, so
this remains an environment/tooling validation limitation rather than claimed
runtime proof.

## Validation evidence

Implemented files:

- `server/nakama_gameplay_relay.gd`: environment-token Nakama socket setup,
  shared-match join/create, match-state forwarding, and authoritative output.
- `server/nakama_gameplay_bridge.gd`: one-binding guard and input-sequence
  acknowledgement in authoritative state.
- `server/server_main.gd` and `client/network_client.gd`: ticket
  issue/consume, one bridge binding at world entry, server-owned match ID
  handoff, opt-in Nakama input/state routing, and legacy RPC fallback.
- `server/login_runtime.gd`, `shared/network_config.gd`, and
  `client/nakama_gameplay_bridge_client.gd`: injected assertion seams, match
  configuration, official SDK socket client wiring, and shared sequence use.
- `tests/unit/test_nakama_gameplay_relay.gd`: credential-free relay forwarding
  and URL configuration tests.

Validation run from the repository root:

- `godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gselect=nakama_gameplay -gdisable_colors -gexit`:
  passed; 8 tests, 8 passing, 22 assertions. The run reported 3 orphaned test
  objects.
- Direct parse checks passed for the relay, bridge, login runtime, server main,
  client bridge, network config, and relay test. The direct check for
  `client/network_client.gd` exited 1 without diagnostics; a headless editor
  load produced no NetworkClient/Nakama parser diagnostics.
- Live two-client Nakama proof was not run: no configured live relay token or
  credentialed match runtime is available in this environment.

Slice status remains **in-progress**. Feature and tracker status were not
advanced because the public seam is not live-validated.