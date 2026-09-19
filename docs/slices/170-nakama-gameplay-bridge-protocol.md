# Slice 170 - Nakama socket gameplay bridge protocol contract

GitHub issue: #359

Status: **delivered**

Phase: 12 (Authoritative runtime and action input)

Feature: [F-039](../FEATURE-LIST.md#f-039-nakama-v1-entry-and-realtime-foundation)

## User outcome

Project0 has a bounded protocol contract for carrying gameplay input and
authoritative state through a future Nakama socket bridge without moving
simulation authority out of the Project0 game server.

## Scope and non-goals

In scope: shared protocol envelopes for client input, authoritative state,
presence, and bounded bridge errors; identity/Account/Character binding fields;
payload and sequence validation; and pure tests for accepted/rejected messages.

Out of scope: installing or selecting a Nakama Godot socket SDK, replacing the
current ENet transport, live Nakama socket connection wiring, shared-world
routing, automatic matchmaking, and moving gameplay simulation or Canon into
Nakama.

## Public seam

`shared/nakama_gameplay_bridge_protocol.gd` is the public seam. It builds and
validates transport-neutral Dictionaries that a later Nakama socket adapter can
serialize without changing the Project0 authoritative simulation contract.

## Falsifiable hypothesis

If bridge messages carry explicit version, kind, request sequence, Nakama user
identity, Project0 Character identity, and bounded payloads, then a future
Nakama socket adapter can forward input and authoritative state without trusting
client-supplied authority fields or coupling simulation code to Nakama APIs.

## BDD

1. Given a valid bound identity and input payload, when an input envelope is
   built and validated, then it is accepted with its sequence and payload intact.
2. Given a missing/invalid identity, unsupported kind/version, duplicate or
   non-positive sequence, or oversized payload, when validation runs, then the
   envelope is rejected without partial interpretation.
3. Given authoritative state, when a state envelope is built, then it carries
   server-authoritative position/tick data and the bound Character identity.
4. Given a bridge error or presence update, when built, then it uses bounded
   error/status fields and no client-supplied authority result.

## TDD / validation

`tests/unit/test_nakama_gameplay_bridge_protocol.gd` covers input round trips,
authority-field rejection, sequence/identity/version/kind/payload bounds, and
state/presence/error envelope acceptance through the pure protocol seam.

## Safety invariants

- Client input never supplies authoritative position, tick, or outcome fields.
- Every gameplay envelope is bound to Nakama user ID and Project0 Character ID.
- Invalid or oversized messages fail closed before simulation dispatch.
- This contract does not itself establish a session or mutate Canon.

## Ownership note

Copilot is implementing this slice under the standing authorization because the
local Claude CLI is unavailable/interactive-only on this Windows machine (see
repository memory `implementation-ownership.md`). Implemented in an isolated
git worktree (`slice/170-nakama-gameplay-bridge`) because the user's main
workspace has unrelated dirty changes.

## Root-cause learning

None. The protocol contract and full validation completed without an unexpected
runtime failure or integration surprise.

## Validation evidence

Local record validation: `bash scripts/check_record_sync.sh` — exit 0, 0
errors and 6 pre-existing warnings; `git diff --check` — clean.

SSH-on-okami validation on a temp tree copied from this branch:
`bash scripts/check_record_sync.sh` — exit 0; `bash scripts/run_gut_validation.sh`
— exit 0, **115 scripts, 841/841 tests, 2633 asserts**, 4 warnings.