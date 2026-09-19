# Slice 171 - Default shared playtest world routing and presence

GitHub issue: #360

Status: **delivered**

Phase: 12 (Authoritative runtime and action input)

Feature: [F-039](../FEATURE-LIST.md#f-039-nakama-v1-entry-and-realtime-foundation)

## User outcome

Playtesters entering the current Project0 world are routed to one shared world
instance, see server-authored presence for the connected population, and receive
a bounded unavailable-capacity outcome instead of an unusable world entry.

## Scope and non-goals

In scope: shared-world availability/status contract, server-authored presence
snapshot and join/leave broadcasts over the existing reliable RPC seam, client
presence cache/signal, and two-peer/reconnect tests.

Out of scope: automatic matchmaking, friends/groups/chat, multi-world routing,
Nakama socket SDK wiring, world sharding, and changing authoritative movement or
Canon behavior.

## Public seam

`server/server_main.gd` admission/disconnect presence broadcasts and
`client/network_client.gd`'s presence signal/cache are the public seams. The
current shared Project0 world remains the sole v1 route.

## Falsifiable hypothesis

If shared-world admission publishes a server-authored presence snapshot after
each join/leave and the client caches it idempotently, then two playtesters can
observe the current shared population without automatic matchmaking or a second
world authority.

## BDD

1. Given capacity is available, when a peer is admitted, then it enters the
   current shared world and receives a presence snapshot containing all admitted
   peers.
2. Given two admitted peers, when either peer joins or leaves, then the other
   peer receives the updated server-authored presence snapshot.
3. Given a reconnect, when the peer is admitted again, then it receives a fresh
   snapshot and no stale departed presence remains.
4. Given capacity is unavailable, when admission is attempted, then the peer is
   refused without a Player/world representation or presence entry.

## TDD / validation

`tests/unit/test_nakama_presence.gd` covers valid shared-world snapshots,
duplicate-peer rejection, capacity bounds, and missing-identity rejection. The
live server/client seams are exercised by the full GUT suite's existing
connection and remote-player coverage.

## Safety invariants

- Presence is server-authored; clients cannot insert or rewrite population
  entries.
- The v1 route is one shared Project0 world, not automatic matchmaking.
- Disconnected peers are removed before the next presence broadcast.
- Presence never grants Character, gameplay, or Canon authority.

## Ownership note

Copilot is implementing this slice under the standing authorization because the
local Claude CLI is unavailable/interactive-only on this Windows machine (see
repository memory `implementation-ownership.md`). Implemented in an isolated
git worktree (`slice/171-nakama-shared-world-routing`) because the user's main
workspace has unrelated dirty changes.

## Root-cause learning

- **Symptom (standalone parse checks failed)**: direct `--check-only` checks for
   `client/network_client.gd` and `server/server_main.gd` reported unresolved
   existing autoload/class-cache types (`TelemetryBatchQueue` and `SqliteStore`).
- **Falsifiable hypothesis**: the failures were standalone import/cache limits
   of the Windows checkout, not syntax errors in the new presence contract or
   broadcasts.
- **Discriminating check**: `shared/nakama_presence.gd` parsed independently,
   then the full repository validation ran on okami's temp tree.
- **Confirmed root cause**: standalone checks could not resolve existing
   project-wide class dependencies; the full suite loaded the project graph and
   passed.
- **Why existing tests did not catch it earlier**: the standalone command does
   not load the same autoload/import graph as the standard validation wrapper.
- **Countermeasure**: retain pure presence-contract tests and use the standard
   full-suite project validation for the connected client/server seams.
- **Regression evidence**: okami full validation passed all tests.

## Validation evidence

Local record validation: `bash scripts/check_record_sync.sh` — exit 0, 0
errors and 6 pre-existing warnings; `git diff --check` — clean. The new pure
presence contract parse check passed. Standalone client/server parse checks were
blocked by the existing `TelemetryBatchQueue`/`SqliteStore` class-cache
diagnostics described above.

SSH-on-okami validation on a temp tree copied from this branch:
`bash scripts/check_record_sync.sh` — exit 0; `bash scripts/run_gut_validation.sh`
— exit 0, **844 tests and 2633 asserts passing**, 3 pending/risky cases.