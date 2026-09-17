# Slice 069 — Assertion handoff seams: request from login, present to game
GitHub issue: #95

Status: **delivered**

Phase: 10 (Authoritative runtime and action input), advancing
[P-014](../FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)
and the [login-boundary decision](../../.scratch/container-platform/issues/02-account-login-service-boundary.md)
("account-only then selected-Character signed assertions" carried between
processes). Fifteenth delivery of the [container-platform map](../../.scratch/container-platform/map.md);
the **second sub-slice of the out-of-process login split** — it adds the RPC
seams that let a client obtain a signed assertion from the login process and
present it to the game process, and proves the game server trusts that assertion
**without sharing the accounts database**.

## User outcome

A client can authenticate once against the login process, receive a short-lived
signed assertion, and use it to establish its game-server session — the game
server accepts the login process's assertion without ever reading the accounts
database, which is what lets login run as its own service.

## Scope and non-goals

In scope:
- Client seam `submit_request_assertion()` + server receiver
  `receive_assertion_request_on_server` (hosted by the login process) that mints
  a selected-Character assertion, falling back to an account assertion, using the
  server's authoritative clock and a bounded TTL, and replies the token to the
  requesting peer only.
- Client seam `submit_present_assertion(token)` + server receiver
  `receive_assertion_presentation_on_server` (hosted by the game process) that
  establishes the peer's session purely from a validated assertion.
- Relay signals `assertion_result_received` / `session_established_received`.
- A two-runtime handoff integration test (different DBs, same secret).

Out of scope (later sub-slices): rewiring the client's connection UX to actually
connect to the login process then the game process (the login screen flow);
dropping the game server's in-process register/login; splitting
`accounts.sqlite3` from `canon.sqlite3` on disk; transport hardening (private
TLS). This slice adds the seams and proves the trust handoff; the existing
single-connection register/login path is unchanged.

## Public seam

- `client/network_client.gd`: `submit_request_assertion()`,
  `receive_assertion_request_on_server`, `receive_assertion_result`,
  `submit_present_assertion(token)`, `receive_assertion_presentation_on_server`,
  `receive_session_established_result`, signals `assertion_result_received`,
  `session_established_received`.

## Safety invariant

The server owns the clock and TTL for every assertion (the client supplies
neither). The token is minted for and returned to the owning peer only, over
that peer's own connection. Establishing a session is fail-closed: the game
server binds a session only after its validator accepts the token; a token
signed with a different secret, tampered, or expired binds nothing. No account
id or password ever crosses between processes — only the signed assertion.

## ADR rationale

No new ADR. Signed assertions carried between the login and game processes are
exactly the mechanism the login-boundary decision specifies; this exposes the
Slice 059/060 issue/validate/establish gateway methods over the existing RPC
transport.

## BDD / TDD

`tests/integration/test_login_assertion_handoff.gd`: two `LoginRuntime`s built on
**different** accounts DBs but the **same** assertion secret. The login side
registers a user, creates+selects a Character, and issues a selected-Character
assertion; the game side (whose DB has no such account) establishes a fresh
peer's session purely from that assertion and carries the selected Character —
proving cross-process trust without a shared DB. A token issued under a
different secret is rejected by the game side and binds nothing (the trust
boundary). The unchanged suite proves the added RPC seams don't regress the
existing login path.

## Validation

- Focused + full suite: `scripts/run_gut_validation.sh` on the Linux host —
  **passed, 52/52 scripts, exit 0** (+1 new
  `tests/integration/test_login_assertion_handoff.gd`; the unchanged suite proves
  the added RPC seams don't regress the existing login path).
- `scripts/check_record_sync.sh` exit 0 (6 pre-existing WARN).

## Root-cause learning

None yet.
