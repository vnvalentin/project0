# Slice 179 - Import pinned Nakama Godot SDK and prove two-client socket path

GitHub issue: #386

Status: **delivered**

Phase: 12 (Authoritative runtime and action input)

Feature: [F-039](../FEATURE-LIST.md#f-039-nakama-v1-entry-and-realtime-foundation)

## User outcome

Project0 has a reproducible, Godot 4.3-compatible proof that the pinned official
Nakama client can connect two clients to a relayed match and carry a validated
Slice 170 envelope.

## Scope and non-goals

In scope: import official `heroiclabs/nakama-godot` v3.4.0 under
`addons/com.heroiclabs.nakama/`, retain Apache-2.0 attribution, instantiate the
addon only inside the isolated proof, and add the smallest two-client socket
proof. The main Project0 autoload graph remains unchanged until the proof is
validated.

Out of scope: `NakamaMultiplayerBridge`, replacing Project0 ENet/RPC,
production gameplay bridge wiring, automatic matchmaking, Canon changes,
client authority, and production deployment.

## Public seam

The pinned addon and isolated socket proof script are the public seam. The proof
must use `NakamaClient.restore_session()`,
`Nakama.create_socket_from(client)`, direct match APIs, and
`NakamaGameplayBridgeProtocol.validate()`.

## Falsifiable hypothesis

If the pinned official GDScript addon imports under Godot 4.3, then two clients
can connect, join a relayed match, send/receive a bounded Slice 170 envelope,
and leave without requiring native extensions or replacing Project0's current
multiplayer peer.

## BDD

1. Given the pinned addon, when Godot imports the project, then the addon parses
   without native-extension requirements and does not alter the main autoload graph.
2. Given two valid Nakama sessions and a reachable Nakama server, when the proof
   runs, then both sockets connect and join the same relayed match.
3. Given a bounded Slice 170 input envelope, when client A sends it, then client
   B receives it and validates it successfully.
4. Given the proof ends, when both clients leave and close, then no Project0
   ENet peer or gameplay authority is replaced.

## TDD / validation

Focused validation is the Godot 4.3 import/parse check plus the bounded proof
harness. Full-suite evidence is required before delivery.

## Safety invariants

- The addon version is pinned; no untracked `master` checkout is used.
- The exact upstream release commit is recorded in
   `docs/third-party/nakama-godot-v3.4.0/PROVENANCE.md`.
- Upstream Apache-2.0 license/attribution is retained.
- No secrets are committed; proof configuration comes from environment values.
- The proof does not install a second gameplay authority, global autoload, or
   mutate Project0 Canon state.

## Ownership note

Copilot is implementing this slice under the standing authorization because the
local Claude CLI is unavailable/interactive-only on this Windows machine (see
repository memory `implementation-ownership.md`). Implemented in an isolated
git worktree (`slice/179-nakama-sdk-proof`).

## Root-cause learning

- **Symptom**: the initial live proof attempts failed through wrapper issues:
   expired tokens, duplicated `:7350` host/port, shell quoting, and an incorrect
   assumption that `create_match_async()` returned a collection.
- **Falsifiable hypothesis**: the failures were proof/deployment orchestration
   defects, not Nakama socket incompatibility.
- **Discriminating check**: corrected the proof to use a host-only value, fresh
   tokens, the pinned SDK's direct Match return value, and a minimal imported
   Godot project; then reran the live proof against the healthy okami container.
- **Confirmed root cause**: the proof wrapper and one SDK return-shape assumption
   were wrong; the official addon and socket path worked after correction.
- **Why existing tests did not catch it earlier**: no live Nakama server or
   pinned addon existed in the repository test path.
- **Countermeasure**: keep the addon isolated from Project0's global autoload,
   use a protected operational proof script, and pin the SDK/API contract.
- **Regression evidence**: clean Godot 4.3 import/parse, live two-client proof,
   and Project0 full validation all passed.

## Validation evidence

Focused checks after isolating the addon: Godot 4.3 editor import exit 0;
socket proof parse exit 0; Slice 170 protocol parse exit 0; record sync exit 0
with 6 pre-existing warnings; `git diff --check` clean.

Live okami proof: both throwaway Nakama accounts returned HTTP 200; two clients
connected, created/joined a relayed match, sent/received a Slice 170 envelope,
validated it, and exited with proof status 0. Nakama/PostgreSQL remained
healthy.

Project0 full validation on okami: **117 scripts, 849 tests, 2645 asserts**,
846 passing and 3 risky/pending, no failures.