# Slice 180 - Nakama socket gameplay bridge

GitHub issue: #372

Status: **in-progress**

Phase: 12 (Authoritative runtime and action input)

Feature: [F-039](../FEATURE-LIST.md#f-039-nakama-v1-entry-and-realtime-foundation)

## User outcome

A Nakama-authenticated client can use the approved Nakama socket path for
bounded gameplay input, while Project0 remains the sole authority for movement,
actions, and returned state.

## Scope and non-goals

In scope: the pinned Nakama Godot v3.4.0 socket adapter, shared-world match
bootstrap, world-entry-ticket and Character binding, Slice 170 input/state
validation, forwarding into the existing authoritative Player simulation,
authoritative state return, bounded errors/backpressure, and executable
adapter tests.

Out of scope: automatic matchmaking, friends/groups/chat, world sharding,
Nakama-owned Character or Canon state, and a second gameplay authority.

## Public seam

The bridge adapter consumes `shared/nakama_gameplay_bridge_protocol.gd` and
forwards accepted input to the existing `ServerPlayerState` seam. The socket
adapter's fake-socket seam is used for deterministic unit tests; live two-client
proof remains an integration requirement.

## Falsifiable hypothesis

If a server-owned Nakama socket joins the shared match and validates every
identity-bound envelope against the consumed world-entry binding before calling
`ServerPlayerState`, then Nakama gameplay can replace direct client gameplay
transport without changing simulation authority.

## Validation

Focused adapter tests, `scripts/check_record_sync.sh`, the full GUT suite, and a
live two-client Nakama input/state exchange with invalid/unbound rejection,
reconnect, bounded backpressure/error handling, and bridge/presence telemetry.

## Safety invariants

- The client never supplies authoritative position, tick, outcome, or identity.
- Only a consumed world-entry binding can dispatch gameplay input.
- Nakama is transport only; Project0 owns simulation and Canon.
- A failed socket, invalid envelope, or full queue fails closed without mutating
  Player state.

## Ownership note

Copilot is implementing this slice under the standing authorization because the
local Claude CLI is unavailable/interactive-only on this Windows machine (see
repository memory `implementation-ownership.md`).

## Root-cause learning

The first adapter draft dispatched into `ServerPlayerState` before checking
whether the injected socket could accept the authoritative response. The
focused backpressure test exposed that a failed socket could therefore still
mutate authoritative state. The bridge now checks socket capacity before
dispatch and the fake socket exposes that same acceptance seam. GUT's
`-gtest` option did not isolate a script in this checkout; the reliable
selector is `-gdir=res://tests/unit -gselect=nakama_gameplay_bridge`.

## Validation evidence

Implemented files:

- `server/nakama_gameplay_bridge.gd`: server-owned binding, envelope
  validation, ticket consumption, duplicate rejection, bounded backpressure,
  dispatch into `ServerPlayerState`, and authoritative state/error output.
- `client/nakama_gameplay_bridge_client.gd`: opt-in Nakama shared-match
  bootstrap, match-state sender, and state/error receiver; direct ENet/RPC
  remains the default.
- `shared/network_config.gd`: explicit `PROJECT0_CLIENT_NAKAMA_GAMEPLAY=1`
  gate.
- `tests/unit/test_nakama_gameplay_bridge.gd`: five offline fake-socket tests
  covering accepted movement, identity rejection, duplicate rejection, ticket
  reuse, authoritative output, and backpressure without state mutation.
- `tests/unit/nakama_gameplay_bridge_fakes.gd`: non-production fake socket and
  Player-state collaborators used by the GUT tests.

Validation run from the repository root:

- `godot --headless --path . --check-only -s server/nakama_gameplay_bridge.gd`:
  passed.
- `godot --headless --path . --check-only -s client/nakama_gameplay_bridge_client.gd`:
  passed.
- `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gselect=nakama_gameplay_bridge -gdisable_colors -gexit`:
  passed; 1 script, 5 tests, 0 failures, 0 risky/pending.
- `bash scripts/check_record_sync.sh`: attempted; the Windows run exceeded the
  command wrapper timeout after reaching the repository's known six feature-name
  warnings, with no Slice 180-specific warning or exit code captured.

The full suite was not used as Slice 180 evidence because the unfiltered run
reported 13 unrelated failures and 123 risky/pending tests. A live two-client
Nakama proof remains outstanding: this Windows/offline validation has no live
Nakama credentials or server-side Nakama match handler, and this slice keeps
the game server's existing ENet/RPC path as the default.
