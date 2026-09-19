# Slice 087 — Login-session resume (in-world Character Select without re-login)
GitHub issue: #95

Status: **delivered**

Phase: 14 (Player accounts and characters), advancing
[F-034](../FEATURE-LIST.md#f-034-client-login-and-character-selection-screens)
and extending the [P-014](../FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)
assertion mechanism. Follows the Slice 084 login-split cutover and the interim
split-logout fix (F-034 change history, 2026-09-15) found in Windows GUI
confirmation.

## User outcome

In the split topology, clicking the in-world **Character Select** button returns
the player to their Character roster **without re-typing the password**. If the
resume window has elapsed, it falls back gracefully to the login screen. Combined
mode is unchanged (it returns straight to Character selection on the one
authenticated connection).

## Problem

After the split cutover, the account session lives on the login process, which
the world handoff disconnects from to reach the assertion-only game process. So
returning to the Character screen listed Characters against the game server and
failed (`account_authority_disabled`); the interim fix routed logout to the
login screen, requiring a full re-login to switch Characters. The client caches
no credentials, so a bounded, client-held resume token is the mechanism to
re-establish a login session without re-authenticating.

## Scope and non-goals

In scope:
- `client/network_client.gd`:
  - `RESUME_ASSERTION_*` TTL constants + `resolve_resume_ttl_seconds()`
    (server-owned, `PROJECT0_RESUME_TTL_SECONDS`, default 1 h, clamped 60 s–24 h).
  - `submit_request_resume_assertion` / `receive_resume_assertion_request_on_server`
    (mints an account assertion with the resume TTL via `issue_account_assertion`)
    / `receive_resume_assertion_result` + `resume_assertion_result_received`.
  - The handoff fetches and stores the resume token (`_resume_assertion`) while
    still on the login process (best-effort).
  - `perform_return_to_character_select(login_host, login_port)` +
    `return_to_character_select_finished` — reconnects to login, re-establishes a
    session from the resume token.
- `client/gameplay_logout.gd`: split path drives the return coroutine and routes
  to the Character list on success / login screen on failure; label is
  "Character Select".

Out of scope: refresh/rotation of the resume token mid-session; persisting it to
disk (memory only); combined-mode changes; any server auth-model change (reuses
the existing `issue_account_assertion` + `establish_session_from_assertion`).

## Public seam

- `client/network_client.gd` (`perform_return_to_character_select`,
  `resolve_resume_ttl_seconds`, the resume-assertion RPCs/signals).
- `client/gameplay_logout.gd` (`_return_target_scene`).

## Safety invariant

The resume token is minted with the **server's** clock and a **server-clamped**
TTL (the client sets neither), and only for a peer already authenticated on the
login process. It is an account-only assertion (no Character snapshot); presenting
it re-establishes a login session bound to that account, so `list_characters` is
still account-scoped and fail-closed. It is held in client memory only for its
TTL; an expired or tampered token binds nothing and degrades to a re-login.

## ADR rationale

No new ADR. Reuses the accepted HMAC assertion mechanism (Slices 059/060) and its
`issue_account_assertion` / `establish_session_from_assertion` seams at the
home-hosted trust level; only the TTL and the client return coroutine are new.

## BDD / TDD

`tests/unit/test_gameplay_logout_target.gd`:
- the button reads "Character Select";
- `_return_target_scene("ok")` → Character list; any failure → login screen;
- `resolve_resume_ttl_seconds()` defaults when unset, reads a valid override, and
  clamps/defaults out-of-range or non-integer overrides.

The server round-trip (`issue_account_assertion` → `establish_session_from_assertion`
→ account-scoped `list_characters`) is already covered by the login-gateway
assertion integration tests; the forward handoff (now with the resume step) is
exercised by `scripts/test_login_handoff_e2e.gd`.

## Validation

- Full suite: `scripts/run_gut_validation.sh` on the Linux host — **passed,
  407/407 tests across 60 scripts, exit 0**.
- End-to-end: `scripts/test_login_handoff_e2e.gd` on Linux — **ALL PASS**
  (world entry ok, bound `Handoff Hero`), proving the added resume-token step
  does not disturb the forward handoff.
- Windows GUI: the in-world Character Select return path confirmed.

## Root-cause learning

No unexpected failure during this slice. It is the deliberate follow-up to the
GUI-confirmation defect recorded in F-034 (2026-09-15): the split cutover's
"return to Character Select" required a re-login because the account session
lives on the login process. Countermeasure: a bounded, server-minted resume
token the client presents on return. Remaining limitation: the return works only
within the token TTL (default 1 h); beyond it, the flow degrades to a re-login.
