# Slice 181 - Live Nakama gameplay bridge proof

GitHub issue: #372

Status: **delivered**

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
writes only credential-free stage/outcome state. It exits zero only after a
valid authoritative bridge state is received.

## Validation

Parse command:

```text
godot --headless --path . --check-only -s scripts/nakama_live_bridge_proof.gd
```

The parse command passed with no diagnostics. The deployed two-client proof ran
against the healthy Nakama/game stack with fresh temporary accounts. Both roles
exited 0 and both redacted state files reported `match_id_present=true`,
`state_received=true`, `stage=authoritative_state_received`, and the expected
session, Character, world-entry, and authoritative-state outcomes.

### Assertion-only Character CRUD evidence

Root cause: the live bridge reached `character_list_account_authority_disabled` after Nakama session validation succeeded, because assertion-only account-authority gating did not recognize the validated peer. The local fix tracks peers after successful `bind_validated_nakama_session`, permits Character CRUD only for those peers, and erases authorization on `clear_session`. Validation: login_gateway parse 0, Nakama focused GUT 11/11, diff-check 0.

### Live two-client runtime evidence

The proof ran on okami against the deployed proof-capable game image with a
relay token validated through Nakama `/v2/account` (HTTP 200). Two fresh client
accounts authenticated with HTTP 200. Both clients completed world entry,
received a shared match id, submitted movement through the Nakama socket bridge,
and received Project0-authoritative state. Both processes exited 0; temporary
accounts and proof artifacts were removed after capture.

Earlier attempts exposed stale-image, relay-credential, container-endpoint, and
proof-harness assertion defects. Those were corrected before the passing run.
