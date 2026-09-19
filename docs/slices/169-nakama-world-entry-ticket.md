# Slice 169 - Project0 world-entry ticket contract for Nakama sessions

GitHub issue: #358

Status: **delivered**

Phase: 12 (Authoritative runtime and action input)

Feature: [F-039](../FEATURE-LIST.md#f-039-nakama-v1-entry-and-realtime-foundation)

## User outcome

A Nakama-authenticated player can receive a short-lived Project0 world-entry
ticket only after Project0 has validated their server-bound Nakama Account and
selected Character ownership; the game-server side can consume that ticket once
to bind world-entry session state.

## Scope and non-goals

In scope: a server-only world-entry ticket service wrapping the existing signed
session assertion contract, selected-Character requirement, bounded TTL,
single-use replay rejection, explicit invalidation hook, and tests proving
valid/expired/replayed/wrong-audience/unowned-or-unselected Character behavior.

Out of scope: public HTTP/Nakama runtime endpoint wiring, Godot Character UI
rewiring, Nakama socket gameplay bridge, shared-world routing, legacy account
migration, and changing the existing login assertion handoff behavior.

## Public seam

`server/world_entry_ticket_service.gd` is the public seam. It issues tickets
from a Project0-bound session and consumes validated tickets into game-server
session state using the existing `SessionAssertion` issuer/validator format.

## Falsifiable hypothesis

If world-entry tickets are a narrow wrapper over the existing signed assertion
format with selected-Character and one-time-consumption rules, then Project0 can
add Nakama world entry without weakening the existing assertion handoff or
moving Character/Canon authority to the client.

## BDD

1. Given a Nakama-bound session with a selected Character, when a ticket is
   issued, then the signed ticket carries account id, character id, display
   name, cosmetic snapshot, audience, and a bounded expiry.
2. Given a valid ticket, when the game-server side consumes it once, then it
   binds a session and selected Character snapshot for the target peer.
3. Given the same ticket is consumed twice, when the second consume happens,
   then it is rejected as replayed and binds no new session.
4. Given an expired or wrong-audience ticket, when consume runs, then it is
   rejected and no session is bound.
5. Given no Character is selected, when issue runs, then no ticket is minted.

## TDD / validation

`tests/integration/test_world_entry_ticket_service.gd` covers ticket issuance,
consume, replay rejection, expiry rejection, wrong-audience rejection, missing
selection, and explicit invalidation. The service is exercised through real
`SessionRegistry`, `CharacterService`, `AssertionIssuer`, and
`AssertionValidator` collaborators over the same SQLite-backed Character store
used by the existing login/Character tests.

## Safety invariants

- A ticket is issued only from server-bound session state, never from a
  client-supplied account id.
- A consumed ticket is single-use in the service instance.
- Failed consume attempts do not bind a session.
- This slice does not move gameplay simulation, Canon, or Character storage into
  Nakama.

## Ownership note

Copilot is implementing this slice under the standing authorization because the
local Claude CLI is unavailable/interactive-only on this Windows machine (see
repository memory `implementation-ownership.md`). Implemented in an isolated
git worktree (`slice/169-nakama-world-entry-ticket`) because the user's main
workspace has unrelated dirty changes.

## Root-cause learning

None. The only validation diagnostics were expected negative-test messages
already present in the suite: SQLite not-open probes, malformed JSON probes,
headless null-parameter noise, and UNIQUE-constraint probes.

## Validation evidence

Local record validation: `bash scripts/check_record_sync.sh` — exit 0, 0
errors and 6 pre-existing warnings. `git diff --check` — clean.

SSH-on-okami validation on a temp tree copied from this branch: `bash
scripts/check_record_sync.sh` — exit 0, 0 errors and 6 pre-existing warnings;
`bash scripts/run_gut_validation.sh` — exit 0, **114 scripts, 836/836 tests,
2617 asserts passing**.