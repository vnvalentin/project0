# Slice 059 — Signed session assertion contract, issuer, and validator
GitHub issue: #95

Status: **delivered**

Phase: 10 (Authoritative runtime and action input), advancing
[P-014](../FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)
and the [login-boundary decision](../../.scratch/container-platform/issues/02-account-login-service-boundary.md)
(the account-only then selected-Character signed assertion the game server
validates). Fifth delivery of the
[container-platform map](../../.scratch/container-platform/map.md).

## User outcome

The login authority can mint a short-lived, signed session assertion (account
identity, then a refreshed one carrying the selected Character), and the
authoritative game server can validate it locally — signature, schema, issuer,
audience, and time window — accepting only genuine, unexpired assertions. This
is the crypto seam that lets a future out-of-process login service (Slice 060)
be trusted without sharing a database.

## Scope and non-goals

In scope: a pure `shared/session_assertion.gd` contract (versioned bounded
claims, canonical JSON payload, token encode/split); a server-only
`server/assertion_issuer.gd` (HMAC-SHA256 signing over the encoded payload,
bounded TTL); and a server-only `server/assertion_validator.gd` (constant-time
signature check, then schema/issuer/audience/issued-at/expiry/claim validation,
returning bounded claims or a bounded reason). Comprehensive unit tests
including a full issue→validate round trip and every rejection path.

Out of scope (later slices): wiring assertions into the `LoginGateway` /
RPC flow and binding a validated assertion to the peer's `SessionRegistry`
(Slice 060); the separate out-of-process login service over private HTTPS
(Slice 060); asymmetric keys and key rotation (HMAC shared-secret is the
home-hosted trust choice here, matching the existing PBKDF2/HMAC approach);
revocation lists. No existing `.gd` behavior changes — these are additive seams
with no consumer yet, mirroring how Slice 055 delivered `ServerHealth` and
Slice 038 delivered `SqliteStore` before their consumers.

## Public seam

- `shared/session_assertion.gd` (`class_name SessionAssertion`): `SCHEMA_VERSION`,
  claim-key and outcome constants, `build_payload(claims) -> String` (canonical
  JSON), `parse_payload(text) -> {outcome, claims|reason}` (bounded), and
  `encode_token(payload_b64, sig_b64)` / `split_token(token) ->
  {outcome, payload_b64, sig_b64}`. Pure; no `Crypto`, no secrets.
- `server/assertion_issuer.gd` (`class_name AssertionIssuer`): constructed with
  a secret key + issuer + audience; `issue(session_id, account_id,
  character_id, issued_at_unix, ttl_seconds) -> String` (a
  `<payload_b64>.<sig_b64>` token). `character_id` may be empty for an
  account-only assertion.
- `server/assertion_validator.gd` (`class_name AssertionValidator`): constructed
  with the verification key + expected issuer + audience; `validate(token,
  now_unix) -> {outcome, claims|reason}`.

## Safety invariant

Fail-closed and constant-time. The signature is verified with
`Crypto.constant_time_compare` before any claim is trusted; a tampered payload
or signature, wrong issuer/audience, unsupported version, expired or
not-yet-valid time window, or malformed token each yields a bounded reason and
no claims. The secret key lives only in the server-side issuer/validator, never
in `shared/` or `client/`, and never crosses the wire or a log line.

## ADR rationale

No new ADR. The signed-assertion boundary and its claim set are already fixed by
the accepted login-boundary decision. HMAC-SHA256 with a shared secret is an
implementation-level choice consistent with the repo's existing
`Crypto.hmac_digest` usage at this home-hosted trust level; a future asymmetric
upgrade would be its own decision.

## BDD / TDD

`tests/unit/test_session_assertion.gd` covers canonical serialization
determinism, bounded parse (valid, malformed, missing/oversized fields,
bad version), and token encode/split. `tests/unit/test_assertion_issuer_validator.gd`
covers: issue→validate round trip for an account-only and a selected-Character
assertion (claims exposed); tampered payload → `bad_signature`; tampered
signature → `bad_signature`; wrong signing key → `bad_signature`; wrong
expected issuer → `wrong_issuer`; wrong audience → `wrong_audience`; expired →
`expired`; future issued-at → `not_yet_valid`; unsupported version →
`unsupported_version`; malformed token → `malformed`.

## Validation

- Focused: `tests/unit/test_session_assertion.gd`,
  `tests/unit/test_assertion_issuer_validator.gd`.
- Full GUT gate on the Linux host: `scripts/run_gut_validation.sh` (exit 0);
  `scripts/check_record_sync.sh` (exit 0). Recorded on completion.

### Result (Linux host `192.168.1.254`, 2026-09-14)

`scripts/run_gut_validation.sh` passed **352/352 tests across 48/48 scripts**
(`scripts_expected == scripts_ran == 48`), exit 0 — up from 330/46 (the 22 new
assertion tests). `test_session_assertion` and `test_assertion_issuer_validator`
both passed, covering the issue→validate round trip (account-only and
selected-Character) and every rejection path (tampered payload/signature,
wrong key, wrong issuer/audience, expired, not-yet-valid, unsupported version,
malformed). `scripts/check_record_sync.sh` reported 0 errors, exit 0.

## Root-cause learning

None yet.
