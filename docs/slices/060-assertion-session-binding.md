# Slice 060 — Assertion-backed session establishment in the login gateway

Status: **in progress**

Phase: 10 (Authoritative runtime and action input), advancing
[P-014](../FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)
and the [login-boundary decision](../../.scratch/container-platform/issues/02-account-login-service-boundary.md).
Sixth delivery of the
[container-platform map](../../.scratch/container-platform/map.md); it makes the
[Slice 059](059-session-assertions.md) issuer/validator the login gateway's
session-assertion mechanism, in-process, so the later out-of-process split
(private HTTPS login service) only has to move issuance across the wire.

## User outcome

The login gateway can mint an account-only (then selected-Character) session
assertion for a bound session, and can establish a game-server session purely
from a validated assertion — the exact mechanism the game server will use to
trust a separate login service without sharing a database. No current RPC,
client, or gameplay behavior changes.

## Scope and non-goals

In scope: give `server/login_gateway.gd` optional assertion seams
(`set_assertion_seams(issuer, validator)`); add `issue_account_assertion`,
`issue_character_assertion`, and `establish_session_from_assertion` (validate a
token, then bind the peer's `SessionRegistry` session — account, plus selected
Character when the claim carries one); construct one `AssertionIssuer` +
`AssertionValidator` in `server_main.gd` from a configured secret
(`PROJECT0_ASSERTION_SECRET`, or an ephemeral per-boot dev key) and wire them
into the gateway; a focused delegation/round-trip test.

Out of scope (later slices): changing the auth/character RPC wire shape to carry
the token to the client, having the client store and present it on
reconnect/world-entry, and making assertion establishment the *sole* session
path (that is the out-of-process login-service slice); key rotation and
revocation lists; asymmetric keys. The existing register/login/character/
world-entry flow is byte-for-byte unchanged; the new gateway methods are not
yet called by the RPC receivers, so the GUT suite (including the real-server
e2e harnesses) is unaffected.

## Public seam

`server/login_gateway.gd`:

- `set_assertion_seams(issuer, validator)` — inject the Slice 059 seams.
- `issue_account_assertion(peer_id, now_unix, ttl_seconds)` /
  `issue_character_assertion(...)` — mint a token for the peer's bound session
  (fail-closed `no_session` / `no_character` / `unavailable`).
- `establish_session_from_assertion(peer_id, token, now_unix)` — validate and
  bind the session from the token's claims, or return the validator's bounded
  rejection with no session bound.

`server_main.gd` constructs the issuer/validator from
`PROJECT0_ASSERTION_SECRET` (hex; ephemeral per-boot key with a logged warning
when unset) and calls `set_assertion_seams`.

## Safety invariant

Fail-closed. Establishment binds a session only after
`AssertionValidator.validate` returns OK; a tampered, expired, wrong-audience,
or malformed token binds nothing. Issuance requires an authenticated session.
The secret key lives only in the server-side issuer/validator, never in
`shared/`/`client/` or on the wire. In-process, issuer and validator share one
secret; the split keeps the same configured secret on both sides.

## ADR rationale

No new ADR. This implements the accepted login-boundary decision's
assertion mechanism; the HMAC shared-secret choice is already recorded by
Slice 059.

## BDD / TDD

`tests/integration/test_login_gateway_assertions.gd` (written first): after
`register`, `issue_account_assertion` mints a token that validates
independently (claims carry the account, empty character);
`establish_session_from_assertion` on a second peer binds a session with the
same account; `issue_character_assertion` requires a selection and then carries
the Character; establishing from a selected-Character assertion binds the
selection; an expired or tampered token is rejected and binds no session; and
issuing without a session is rejected. Existing `test_login_gateway.gd`,
`test_account_auth_session.gd`, and `test_character_crud_rpc.gd` stay green.

## Validation

- Focused: `tests/integration/test_login_gateway_assertions.gd`.
- Full GUT gate on the Linux host: `scripts/run_gut_validation.sh` (exit 0,
  including the e2e harnesses); `scripts/check_record_sync.sh` (exit 0).
  Recorded on completion.

## Root-cause learning

None yet.
