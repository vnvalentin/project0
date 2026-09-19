# Slice 173 - Server-side Nakama session validation seam

GitHub issue: #381

Status: **delivered**

Phase: 12 (Authoritative runtime and action input)

Feature: [F-039](../FEATURE-LIST.md#f-039-nakama-v1-entry-and-realtime-foundation)

## User outcome

Project0 can validate a Nakama session server-side and bind the verified Nakama
user ID into the existing Project0 Character/session authority without trusting
client-supplied identity fields.

## Scope and non-goals

In scope: bounded server-side Nakama account validation over HTTP, endpoint and
timeout configuration, CharacterService binding from validated results, and
tests for valid, malformed, expired/wrong-audience, and unavailable outcomes.

Out of scope: client UI wiring, world-entry ticket issuance, gameplay bridge,
automatic matchmaking, Nakama storage, and exposing Nakama credentials to the
client or repository.

## Public seam

`server/nakama_session_validator.gd` and
`CharacterService.bind_validated_nakama_session()` are the public seams. The
validator owns the server-to-server request and returns only a bounded
presentation-safe identity result.

## Falsifiable hypothesis

If Project0 asks Nakama to validate the bearer session through a bounded
server-side HTTP request, then it can bind the returned user ID without decoding
or trusting a client JWT and without adding a new dependency.

## BDD

1. Given a valid Nakama bearer session, when validation succeeds, then the
   returned user ID and username can bind a Project0 session.
2. Given malformed JSON, missing user ID, non-2xx, timeout, or unavailable
   Nakama, when validation runs, then no Project0 session is bound.
3. Given an already-authenticated peer, when bind runs, then it rejects without
   replacing the existing session.
4. Given a client-supplied user ID that differs from Nakama's response, when
   binding runs, then only Nakama's server response is used.

## TDD / validation

`tests/unit/test_nakama_session_validator.gd` covers successful account parsing,
missing identity, non-2xx, timeout, and transport outcomes. CharacterService
integration coverage proves only validated result Dictionaries bind sessions and
failed validation results bind nothing.

## Safety invariants

- The client never supplies Nakama user identity as authority.
- Nakama server keys and bearer tokens remain server-side at this seam.
- Failed validation binds no session and leaks no response body or credential.
- Existing Character ownership rules remain session-derived.

## Ownership note

Copilot is implementing this slice under the standing authorization because the
local Claude CLI is unavailable/interactive-only on this Windows machine (see
repository memory `implementation-ownership.md`). Implemented in an isolated
git worktree (`slice/173-nakama-session-validation`) because the user's main
workspace has unrelated dirty changes.

## Root-cause learning

- **Symptom (standalone CharacterService parse check)**: Windows
   `--check-only` returned exit 1 without a diagnostic after the new validator
   parsed successfully.
- **Falsifiable hypothesis**: the failure was the existing project-wide class
   cache/autoload resolution limitation, not a Slice 173 behavior failure.
- **Discriminating check**: ran the full project validation on an okami temp tree
   containing the same source changes.
- **Confirmed root cause**: standalone checks do not resolve all existing typed
   class dependencies in this checkout; the full suite loaded and exercised the
   new seams successfully.
- **Why existing tests did not catch it earlier**: the standalone command does
   not use the same imported project graph as the repository validation wrapper.
- **Countermeasure**: retain pure validator parsing tests and use the full
   project suite for CharacterService integration evidence.
- **Regression evidence**: okami full validation passed with no failures.

## Validation evidence

Local record validation: `bash scripts/check_record_sync.sh` — exit 0, 0
errors and 6 pre-existing warnings; `git diff --check` — clean. The new
validator script parsed successfully; standalone CharacterService parsing was
limited by the existing class-cache behavior above.

SSH-on-okami validation on a temp tree copied from this branch:
`bash scripts/check_record_sync.sh` — exit 0; `bash scripts/run_gut_validation.sh`
— exit 0, **117 scripts, 849 tests, 2645 asserts**, 3 risky/pending tests and
no failures.