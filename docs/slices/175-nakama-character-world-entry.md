# Slice 175 - Nakama Character and world-entry client path

GitHub issue: #371

Status: **delivered**

Phase: 12 (Authoritative runtime and action input)

Feature: [F-039](../FEATURE-LIST.md#f-039-nakama-v1-entry-and-realtime-foundation)

## User outcome

A Nakama-authenticated client connects to Project0, presents its bearer session
for server-side validation, uses the existing server-owned Character CRUD path,
and enters the world through the existing signed world-entry flow.

## Scope and non-goals

In scope: server startup wiring for `NakamaSessionValidator`, a reliable client
token-presentation RPC, server validation/bind result, Nakama-mode Character
gate connection/list/create/select/delete behavior, and world-entry handoff.

Out of scope: Nakama socket gameplay transport, automatic matchmaking, social
features, Nakama storage, and client-side identity authority.

## Public seam

Existing `NetworkClient` RPCs/signals plus the Nakama-mode branch in
`client/character_gate.gd`; no new transport abstraction is introduced.

## Falsifiable hypothesis

If Nakama mode presents its bearer token once to the Project0 game server and
then reuses the existing session-derived Character/world-entry RPCs, the client
flow can work without passing Nakama user IDs or Character ownership claims from
the client.

## BDD

1. Given Nakama login succeeded, when Character gate starts, then it connects to
   the game server and presents the bearer token.
2. Given server-side Nakama validation succeeds, then Character list/create/
   select/delete use the existing server-owned RPC path.
3. Given validation fails or times out, then no Character operation or world
   entry proceeds and the UI reports a bounded failure.
4. Given a selected Character, then existing world-entry/handoff enters gameplay;
   reconnect presents the token again and does not reuse stale authority.

## TDD / validation

The Nakama-mode path reuses the existing Character/world-entry RPC seams after
server-side token presentation. The full project suite exercises the touched
autoload/server graph and preserves existing Character/world-entry coverage.

## Safety invariants

- The server validates the bearer token; the client never supplies authority
  identity fields.
- Character CRUD remains session-derived and server-owned.
- Failed presentation leaves no authenticated Project0 session.

## Ownership note

Copilot is implementing this slice under the standing authorization because the
local Claude CLI is unavailable/interactive-only on this Windows machine (see
repository memory `implementation-ownership.md`). Implemented in an isolated
git worktree (`slice/175-nakama-character-world-entry`).

## Root-cause learning

- **Symptom (standalone parse checks)**: direct Windows `--check-only` checks
   reported unresolved existing autoload/project types (`NetworkClient`,
   `TelemetryBatchQueue`, and `SqliteStore`).
- **Falsifiable hypothesis**: these were the repository's existing standalone
   class-cache limitations, not failures in the Nakama-mode path.
- **Discriminating check**: ran the complete project validation on okami using
   the same source tree.
- **Confirmed root cause**: standalone checks do not load the complete project
   autoload/type graph; the full suite loaded and passed the changed graph.
- **Why existing tests did not catch it earlier**: the issue is specific to the
   direct parse command, before test execution.
- **Countermeasure**: use the full project validation wrapper for this graph;
   retain the standalone result as an environment limitation.
- **Regression evidence**: okami full validation passed with no failures.

## Validation evidence

Local record validation: `bash scripts/check_record_sync.sh` — exit 0, 0
errors and 6 pre-existing warnings; `git diff --check` — clean. Standalone
client/server parse checks were limited by the existing class-cache behavior
described above.

SSH-on-okami validation on a temp tree copied from this branch:
`bash scripts/check_record_sync.sh` — exit 0; `bash scripts/run_gut_validation.sh`
— exit 0, **117 scripts, 849 tests, 2645 asserts**, 3 risky/pending tests and
no failures.