# Slice 167 - Nakama Godot auth and session entry

GitHub issue: #356

Status: **delivered**

Phase: 12 (Authoritative runtime and action input)

Feature: [F-039](../FEATURE-LIST.md#f-039-nakama-v1-entry-and-realtime-foundation)

## User outcome

The Godot client can authenticate through Nakama and hold Nakama user/session
identity as the Account root for the new Nakama path, without using Project0's
legacy login assertion or resume-token flow.

## Scope and non-goals

In scope: a bounded Nakama HTTP auth/session client, Nakama endpoint/server-key
configuration, account login/register/session-refresh/logout result handling,
PlayerIdentity storage for Nakama user/session data, and account-gate wiring
behind an explicit Nakama-login flag.

Out of scope: Character create/list/select keyed by Nakama user ID, world-entry
ticket issuance, Nakama socket gameplay bridge, shared-world routing, friends,
groups, chat, automatic matchmaking, and legacy Project0 account migration.

## Public seam

`client/nakama_http_client.gd` and the account-gate Nakama login/register path
are the public seam. The seam is client-only and stores in-memory Nakama session
state in `PlayerIdentity`; it does not grant Character or Canon authority.

## Falsifiable hypothesis

If Nakama login is feature-flagged and represented by a bounded client-only
HTTP seam with explicit result dictionaries, then the Godot login screen can
enter the Nakama identity path without depending on ENet login assertions,
Project0 resume tokens, or the future Character service.

## BDD

1. Given Nakama login is enabled, when a login succeeds, then PlayerIdentity
   stores the Nakama user id, username, auth token, and refresh token and the
   account gate transitions to Character selection.
2. Given Nakama login is enabled, when registration succeeds, then the account
   gate stores the same Nakama session fields and transitions without calling
   Project0's legacy register/login RPCs.
3. Given Nakama returns a malformed body or non-2xx response, when the client
   parses it, then no Nakama session state is stored and the UI reports a
   bounded failure reason.
4. Given Nakama session state exists, when logout/clear-session runs, then all
   Nakama auth and refresh tokens are cleared from memory.

## TDD / validation

`tests/unit/test_nakama_http_client.gd` covers the public-seam behavior that
does not require a live Nakama server: Nakama flag/config defaulting, Basic auth
header encoding, HTTP error bounding, auth-token parsing into Nakama user id and
username, malformed-token rejection, and `PlayerIdentity.clear_session()`
clearing in-memory Nakama tokens.

## Safety invariants

- Nakama tokens are stored only in memory for this slice and are cleared by
  `PlayerIdentity.clear_session()`.
- A malformed or failed Nakama response never partially authenticates a client.
- The Nakama path never mints or consumes Project0 login assertions or resume
  tokens.
- The Nakama server key is configuration, not a gameplay or Canon authority.

## Ownership note

Copilot is implementing this slice under the standing authorization because the
local Claude CLI is unavailable/interactive-only on this Windows machine (see
repository memory `implementation-ownership.md`). Implemented in an isolated
git worktree (`slice/167-nakama-auth-session-entry`) because the user's main
workspace has unrelated dirty changes.

## Root-cause learning

- **Symptom (local focused runner did not start)**: direct local GUT invocation
   for `test_nakama_http_client` exited before running tests because the Windows
   checkout could not import existing GUT/autoload class names and failed on an
   existing `TelemetryBatchQueue` parse dependency in `NetworkClient`.
- **Falsifiable hypothesis**: the failure was a local import/cache/native setup
   problem, not a Slice 167 behavior failure.
- **Discriminating check**: ran the repository validation script on a Linux temp
   tree with the host's built native addon artifacts overlaid, the same pattern
   used by recent slices when Windows lacks the runtime dependency shape.
- **Confirmed root cause**: a fresh temp copy without native addons reproduced
   missing-GDExtension failures; copying the host's `godot-sqlite` artifacts into
   the temp tree let the full suite pass.
- **Why existing tests did not catch it earlier**: the new Nakama tests are pure
   client/static tests, while the failure was in full project startup/import
   state before the selected test could run.
- **Countermeasure**: use full-suite Linux validation with the native addon
   overlay as the delivery gate; keep the new tests pure and independent of live
   Nakama.
- **Regression evidence**: SSH-on-okami Linux validation with native artifacts
   passed record sync and the full GUT suite.

## Validation evidence

Local record validation: `bash scripts/check_record_sync.sh` — exit 0, 0
errors and 6 pre-existing warnings. `git diff --check` — clean.

SSH-on-okami validation on a temp tree copied from this branch with the host's
built `godot-sqlite` artifacts overlaid: `bash scripts/check_record_sync.sh` —
exit 0, 0 errors and 6 pre-existing warnings; `bash scripts/run_gut_validation.sh`
— exit 0, **826/826 tests passing, 2558 asserts**.