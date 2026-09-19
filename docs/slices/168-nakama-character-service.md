# Slice 168 - Project0 Character service keyed by Nakama user ID

GitHub issue: #357

Status: **delivered**

Phase: 12 (Authoritative runtime and action input)

Feature: [F-039](../FEATURE-LIST.md#f-039-nakama-v1-entry-and-realtime-foundation)

## User outcome

Project0 can create, list, select, and delete Characters for a Nakama-authenticated
player using the Nakama user ID as the Account key, while Project0 keeps all
Character rules and ownership checks server-owned.

## Scope and non-goals

In scope: an idempotent repository seam that materializes a Project0 Account
placeholder keyed by Nakama user ID without storing usable Project0 password
credentials, a CharacterService seam that binds a Nakama-authenticated peer to
that Account key, and tests proving existing Character rules still apply.

Out of scope: public HTTP/Nakama runtime endpoints, Godot Character UI rewiring,
world-entry tickets, gameplay socket bridge, legacy account migration, and any
change to Character slot/name/soft-delete rules.

## Public seam

`AccountCharacterRepository.ensure_nakama_account()` and
`CharacterService.bind_nakama_account_session()` are the public seams. Existing
Character CRUD methods remain the authority for Character rules after the
session is bound.

## Falsifiable hypothesis

If a Nakama user ID is materialized as the Project0 Account key with credential
sentinel values that cannot satisfy Project0 password authentication, then the
existing session-derived Character service can preserve slot limits, name
uniqueness, soft deletion, and cross-account isolation without accepting a
client-supplied account id.

## BDD

1. Given a Nakama user ID and username, when the server binds the Nakama session,
   then a Project0 Account row exists with `account_id == nakama_user_id`.
2. Given the same Nakama user binds again, when the seam is called, then it is
   idempotent and does not create duplicate Account rows.
3. Given a Nakama-bound session, when Character CRUD runs, then existing cap,
   name uniqueness, soft-delete, and selected-Character behavior are preserved.
4. Given two Nakama users, when one knows the other's Character id, then
   select/delete still rejects cross-account access.
5. Given a malformed Nakama user ID, when the seam is called, then no Account row
   or session is created.

## TDD / validation

Repository and CharacterService integration tests cover the Nakama account
materialization/bind seam and existing Character rules through Nakama user IDs:
idempotent account materialization, malformed user rejection, Character CRUD
under `account_id == nakama_user_id`, and cross-account isolation.

## Safety invariants

- Clients never supply `account_id` to Character CRUD; the service derives it
  from server-bound session state.
- Nakama placeholder Account rows do not contain usable Project0 password
  credentials.
- Canon, gameplay, and world-entry authority are unchanged by this slice.

## Ownership note

Copilot is implementing this slice under the standing authorization because the
local Claude CLI is unavailable/interactive-only on this Windows machine (see
repository memory `implementation-ownership.md`). Implemented in an isolated
git worktree (`slice/168-nakama-character-service`) because the user's main
workspace has unrelated dirty changes.

## Root-cause learning

- **Symptom (focused selector did not provide useful evidence)**: direct GUT
   selector invocation on the copied temp tree exited 0 while still reporting
   missing GUT class imports and an existing autoload parse failure before the
   selected suites produced useful output.
- **Falsifiable hypothesis**: the selector invocation was not the reliable
   validation seam for this repository state; the standard validation wrapper on
   okami would import the project consistently and run the new tests as part of
   the full suite.
- **Discriminating check**: copied the full working tree to okami, copied the
   host's built `godot-sqlite` native library into the temp tree, and ran
   `scripts/run_gut_validation.sh` instead of the raw selector command.
- **Confirmed root cause**: raw selected-test invocation can report startup
   import/autoload diagnostics without proving the selected tests; the standard
   validation wrapper is the reliable project-level gate.
- **Why existing tests did not catch it earlier**: the issue was in the test
   invocation path, not the new Character-service behavior.
- **Countermeasure**: use the standard validation script plus native addon
   overlay for completion evidence.
- **Regression evidence**: okami full validation passed all scripts/tests.

## Validation evidence

Local record validation: `bash scripts/check_record_sync.sh` — exit 0, 0
errors and 6 pre-existing warnings. `git diff --check` — clean.

SSH-on-okami validation on a temp tree copied from this branch with the host's
built `godot-sqlite` artifacts overlaid: `bash scripts/check_record_sync.sh` —
exit 0, 0 errors and 6 pre-existing warnings; `bash scripts/run_gut_validation.sh`
— exit 0, **831 tests and 2585 asserts passing**.