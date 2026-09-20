# Slice 181 - Live Nakama gameplay bridge proof

GitHub issue: #372

Status: **in-progress**

Phase: 12 (Authoritative runtime and action input)

Feature: [F-039](../FEATURE-LIST.md#f-039-nakama-v1-entry-and-realtime-foundation)

## User outcome

A Nakama-authenticated client can enter the shared Project0 world and prove one
movement input reaches the real Nakama gameplay bridge and returns
Project0-authoritative state.

## Scope and non-goals

In scope: a minimal headless, one-client-process harness that can be run twice
for roles `a` and `b`, drives the existing NetworkClient autoload through
Nakama session, Character, world-entry, and movement seams, and writes a
redacted outcome file.

Out of scope: a gameplay scene, visual rendering, token logging or persistence,
a new shell orchestrator, and claiming live proof without configured runtime
credentials.

## Public seam

`scripts/nakama_live_bridge_proof.gd` uses `NetworkClient.connect_to_server`,
`submit_nakama_session`, Character RPC submission methods,
`submit_enter_world`, and `submit_input_intent`. The authoritative proof signal
is `NetworkClient.authoritative_position_received`, which is emitted by the
existing Nakama bridge state path.

## Requirements and command pattern

Requires Godot 4.3, a reachable Project0 ENet server, a reachable Nakama
runtime, and these environment variables per process:

- `PROJECT0_CLIENT_NAKAMA_LOGIN=1`
- `PROJECT0_CLIENT_NAKAMA_GAMEPLAY=1`
- `PROJECT0_NAKAMA_AUTH_TOKEN_A` or `PROJECT0_NAKAMA_AUTH_TOKEN_B`
- `PROJECT0_NAKAMA_SERVER_KEY`
- `PROJECT0_NAKAMA_URL`
- `PROJECT0_GAME_HOST`
- `PROJECT0_GAME_PORT`

Tokens are read in memory, never printed, and never written to the state file.
Run the two processes separately with different state files:

```sh
PROJECT0_CLIENT_NAKAMA_LOGIN=1 PROJECT0_CLIENT_NAKAMA_GAMEPLAY=1 \
PROJECT0_NAKAMA_AUTH_TOKEN_A="$TOKEN_A" PROJECT0_NAKAMA_SERVER_KEY="$SERVER_KEY" \
PROJECT0_NAKAMA_URL="https://nakama.example:7350" PROJECT0_GAME_HOST="127.0.0.1" \
PROJECT0_GAME_PORT="9999" godot --headless --path . -s scripts/nakama_live_bridge_proof.gd \
  --role=a --state-file=build/validation/nakama-bridge-a.json

PROJECT0_CLIENT_NAKAMA_LOGIN=1 PROJECT0_CLIENT_NAKAMA_GAMEPLAY=1 \
PROJECT0_NAKAMA_AUTH_TOKEN_B="$TOKEN_B" PROJECT0_NAKAMA_SERVER_KEY="$SERVER_KEY" \
PROJECT0_NAKAMA_URL="https://nakama.example:7350" PROJECT0_GAME_HOST="127.0.0.1" \
PROJECT0_GAME_PORT="9999" godot --headless --path . -s scripts/nakama_live_bridge_proof.gd \
  --role=b --state-file=build/validation/nakama-bridge-b.json
```

The harness uses a fixed 30-second stage timeout, disconnects before exit, and
writes only `outcomes`, `connection_status`, `match_id_present`,
`state_received`, `last_sequence`, and `error_outcome`. It exits zero only
after a valid authoritative bridge state sequence is received.

## Validation

Parse command:

```text
godot --headless --path . --check-only -s scripts/nakama_live_bridge_proof.gd
```

The parse command passed with no diagnostics. A no-credential invalid-role smoke
run exited 1 and wrote only the redacted state fields. The harness parser fix is
pending deployment; the live two-process proof was not run, and this record does
not claim it passed.
