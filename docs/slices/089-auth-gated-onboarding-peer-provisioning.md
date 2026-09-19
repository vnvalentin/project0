# Slice 089 — Auth-gated onboarding B: `/redeem` accepts a signed assertion + idempotent per-account peer lifecycle and aging/deprovision
GitHub issue: #95

Status: **delivered**

Tracker context: Phase 11 — Public game access; advances
[P-024](../FEATURE-LIST.md#p-024-public-game-access-via-opnsense-native-wireguard)
per [ADR 0004](../adr/0004-auth-gated-tunnel-provisioning.md) follow-up (B). Second
of the three-slice sequence `docs/slices/SLICE-REGISTRY.md` reserves as 088–090.
No new feature id is created: matching the resolved reading in
[Slice 088](088-auth-gated-onboarding-login-delegation.md)'s "Feature id note,"
this slice adds no launcher-side code (that is Slice 090, under `F-035`) and is
tracked directly under **P-024** (Phase 13).

## User outcome

A player who already holds a signed session assertion (minted by Slice 088's
`POST /login`) can call `POST /redeem` with that assertion instead of an
invite code and receive a WireGuard `PeerConfigBundle` — no operator-minted
invite code required. Calling `/redeem` again from the same account while its
peer is still live and unexpired returns the *same* peer configuration rather
than consuming a second `/24` address, so a player who re-runs the launcher
(or resumes onboarding after a dropped connection) does not silently exhaust
the enrollment service's address pool. A peer nobody has redeemed against in a
bounded idle window is automatically reclaimed, keeping the pool available for
new players. (This slice delivers only the `/redeem`-side provisioning and
lifecycle; the launcher/client login → redeem → tunnel → game-handoff sequence
is Slice 090 — see Scope below.)

## Problem

ADR 0004 sub-decision 3 requires `/redeem` to accept a signed assertion as an
alternative to `invite_code`, keyed idempotently per account, with aging and
deprovisioning so unlimited self-service redemption cannot exhaust the pool
the way unlimited invite minting would. Today `EnrollmentService.redeem`
(`infra/enrollment/service.py`) only accepts `{invite_code, public_key}`
(`infra/enrollment/store.py`'s `invites`/`allocations` schema has no notion of
an account at all), and the enrollment service has no way to check whether an
assertion is genuine — the HMAC verification key
(`PROJECT0_ASSERTION_SECRET`) lives only on the login authority process
(`server/assertion_validator.gd`, wired by `server/login_runtime.gd`), and per
ADR 0004 sub-decision 2 and Slice 088's precedent it must stay off the
Internet-facing enrollment box. This slice closes both gaps: a loopback
delegation seam for assertion validation, and the store/service changes for
idempotent, aging-aware peer provisioning.

## Scope and non-goals

**In scope:**

- A new loopback-only delegation seam on the login authority process for
  assertion validation, reusing the `AssertionValidator` that process already
  constructs — see Public seam.
- `POST /redeem` on the enrollment service accepts a second, mutually
  exclusive request shape: `{assertion, public_key}` alongside the existing
  `{invite_code, public_key}`, both handled by the same route and response
  model.
- Store schema changes (`infra/enrollment/store.py`) to tag an allocation with
  the redeeming `account_id` and track `last_seen_at`, and the idempotent
  lookup/touch logic that keys on `account_id`.
- A bounded, operator-invoked aging/deprovision sweep that reclaims
  assertion-path peers idle past a configured threshold, reusing
  `RevocationService.revoke` (Slice 049) verbatim for the actual
  delete+release.
- Config additions needed for the above (idle threshold), reusing Slice 088's
  existing `login_authority_host`/`login_authority_port`/
  `login_authority_timeout_seconds` for the new validation call — no new host/
  port config, since it is the same login authority process Slice 088 already
  targets.

**Explicitly out of scope (non-goals of this slice):**

- Any Windows launcher or Godot client change (login screen, DPAPI storage,
  calling `/redeem` with an assertion, tunnel-then-handoff sequencing). That
  is **Slice 090** (reuses F-035 for the launcher-side pieces).
- **Rate-limiting beyond what DT-009 already tracks.** DT-009 (filed in Slice
  088) covers the public `/login` surface; this slice adds no new rate-
  limiting for `/redeem` either invite- or assertion-gated. `/redeem` already
  had no rate-limiting before this slice (invite codes are operator-minted,
  single-use, so brute-forcing one was already bounded by INVITE_NOT_FOUND
  responses); the assertion path inherits the same posture — an assertion is
  a 300-second-TTL bearer token from `/login`, and `/login` itself is the
  namable enumeration/brute-force surface DT-009 already covers. This is
  restated, not re-opened, as a liability here.
- **Peer identity rotation for an already-enrolled account.** If a
  re-`/redeem` presents a *different* `public_key` than the one on file for
  that account's live peer, this slice rejects it (`ACCOUNT_PEER_KEY_MISMATCH`,
  see Design decision 2) rather than silently re-pointing the existing
  WireGuard identity at a new keypair. Explicit re-enrollment/rotation for a
  lost or reinstalled keypair is deferred to a follow-up slice that can design
  it deliberately (e.g., requiring the old peer to be revoked first, or a
  distinct authenticated "rotate" seam) rather than folding it into idempotent
  redeem semantics. Flagged again under "Open forks for review" below.
- **Automatic/background sweep scheduling.** This slice adds the bounded
  deprovision operation and an operator CLI entry point to invoke it (mirroring
  Slice 049's CLI-only `revoke-peer`, deliberately not an HTTP admin route).
  Wiring a systemd timer/cron to call it on a schedule is deployment/ops
  evidence for a later handoff, the same split Slice 088 used between
  records-first design and live deployment evidence. Per `CLAUDE.md`, no
  in-process background runtime loop is added to the FastAPI service itself.
- Any change to the invite-code path's existing request/response contract or
  behavior (`POST /redeem {invite_code, public_key}`,
  `EnrollmentService.redeem`, `EnrollmentStore.redeem_invite`) — ADR 0004
  sub-decision 4, retained unmodified.
- Live network commands, deployment changes, or config file edits on
  `192.168.1.254` — this slice's own validation is local/headless only.

## Design decisions

### 1. Assertion validation transport at `/redeem`

**Chosen:** the enrollment service delegates assertion validation to the login
authority over a loopback-only HTTP seam, mirroring Slice 088's delegation
pattern exactly. Concretely: `server/login_gateway.gd` already holds a wired
`AssertionValidator` (`_validator`, set by `set_assertion_seams()` — see
`server/login_runtime.gd:78-80` and `:104-106`, called from
`server/login_server_main.gd`'s startup) but exposes it only through
`establish_session_from_assertion(peer_id, token, now_unix)`, which *binds* a
`SessionRegistry` session as a side effect — appropriate for the game server
accepting a connecting player, wrong for a stateless "is this assertion still
good" check from an HTTP delegator with no gameplay session. This slice adds
one new narrow pass-through method to `LoginGateway`:

```text
func validate_assertion(token: String, now_unix: int) -> Dictionary:
    if _validator == null:
        return {"outcome": REASON_UNAVAILABLE}
    return _validator.validate(token, now_unix)
```

— a one-line delegation to the already-constructed `_validator`, with **no**
`SessionRegistry` interaction (unlike `establish_session_from_assertion`),
consistent with `LoginGateway`'s other narrow account-assertion methods
(`issue_account_assertion`). No new secret, no new `AssertionValidator`
construction, no new config: the login authority process already builds and
wires this validator today for the game server's benefit; this slice reuses
it for the enrollment service's benefit.

`server/login_loopback_http_endpoint.gd` (Slice 088) is extended — not
duplicated — to accept a second exact-match path, `POST
/internal/validate-assertion`, alongside the existing `POST
/internal/verify-and-mint`. The existing single-path dispatch
(`REQUEST_PATH` constant + exact-match rejection in `_try_parse_headers()`)
becomes a small dispatch on the parsed `path`, reusing the same `TCPServer`,
strict header/body-byte caps, no-chunked-encoding rule, and connection
lifecycle already implemented and tested — only the body-shape parsing and
the post-parse handler differ per path. Request body: `{"assertion": String}`
(bounded length, matching the existing 1 KiB body cap — a token from
`shared/session_assertion.gd` is comfortably under that). Response: `200
{"outcome": "ok", "account_id": String, "expires_at": int}` on success (the
`aid`/`exp` claims `AssertionValidator.validate()` already returns), bounded
non-200 `{"outcome": "<reason>"}` on rejection, reusing
`SessionAssertion.REASON_*` string constants verbatim (`malformed`,
`unsupported_version`, `invalid_claims`, `bad_signature`, `wrong_issuer`,
`wrong_audience`, `expired`, `not_yet_valid`) rather than inventing new
strings — the same "reuse the vocabulary, don't invent a new one" discipline
Slice 088 used for `bad_credentials`/`malformed`/`unavailable`. Unlike the
verify-and-mint path, **no synthetic peer id is needed at all**: `_validator.validate()`
is a pure check with no `SessionRegistry` write, so there is nothing to
`clear_session()` and no collision hazard to guard against — the new handler
is strictly simpler than the existing one.

Confirmed from `shared/session_assertion.gd`: the account identity is present
in the assertion payload as the `aid` (`KEY_ACCOUNT_ID`) claim
(`session_assertion.gd:23`), a bounded non-empty string
(`_is_bounded_nonempty`, max 256 chars), required on every parse
(`_ORDERED_KEYS`). This is exactly the key `/redeem`'s idempotency (Design
decision 2) needs, and it comes back from the new loopback endpoint as
`account_id` without the enrollment service ever touching the token's
internal shape itself.

**Rejected alternative:** the enrollment service validates the HMAC locally
with a shared `PROJECT0_ASSERTION_SECRET`. Rejected for the same reason ADR
0004 sub-decision 2 and Slice 088 already reject the equivalent for
credential verification: the enrollment service is the most Internet-exposed
box in this system (public HTTPS behind Cloudflare, per Slice 054's live
deployment). Putting the assertion-signing/forging secret there means a
compromise of that single box yields the ability to forge arbitrary signed
session assertions — account takeover for the whole game, not just enrollment
data. Delegating keeps the forgery-capable secret confined to the login
authority process, matching the existing "auth home stays the login
authority" boundary.

### 2. Peer lifecycle / idempotency

`infra/enrollment/store.py`'s `allocations` table gains two nullable columns:

- `account_id TEXT` — `NULL` for invite-path allocations (unchanged
  behavior, non-goal 4), set to the validated `aid` claim for assertion-path
  allocations.
- `last_seen_at REAL` — set to the allocation time on insert, refreshed on
  every idempotent re-redeem "touch" (Design decision 3 reads this to decide
  aging eligibility).

A partial unique index, `CREATE UNIQUE INDEX IF NOT EXISTS
idx_allocations_account_id ON allocations(account_id) WHERE account_id IS NOT
NULL`, enforces at most one live assertion-path peer per account (SQLite
partial indexes exclude `NULL`s, so this adds no constraint to the existing
invite-path rows, which have no `account_id`). Because the live sqlite file
already exists on the deployed host (Slice 054), the store's `__init__` needs
an idempotent migration step (`ALTER TABLE allocations ADD COLUMN ...`,
tolerating "duplicate column" on a re-run, e.g. by checking `PRAGMA
table_info(allocations)` first) rather than relying on `CREATE TABLE IF NOT
EXISTS`, which does not add columns to an already-existing table. This is
called out again under Safety invariants.

New store methods (mirroring the existing `get_allocation_by_public_key`/
`redeem_invite` shapes):

- `get_allocation_by_account_id(account_id) -> AllocationRecord | None` —
  returns the full row (`ip_address`, `public_key`, `opnsense_client_uuid`,
  `last_seen_at`) so the service can answer idempotency and rebuild the
  `PeerConfigBundle` without a second OPNsense call.
- `record_assertion_redeem(account_id, public_key, ip_address,
  opnsense_client_uuid, now)` — the assertion-path analog of `redeem_invite`:
  a single atomic transaction inserting the allocation row. A concurrent
  insert racing on the same `account_id` (two simultaneous first-time
  redeems for one account) raises `AccountAlreadyHasPeerError` off the
  partial unique index's `sqlite3.IntegrityError`, mirroring how
  `redeem_invite` already turns an address collision into
  `PoolExhaustedError`.
- `touch_allocation_last_seen(account_id, now)` — updates `last_seen_at` only,
  used by the idempotent-return path (no OPNsense call, no new row).

`EnrollmentService` gains `redeem_with_assertion(assertion: str, public_key:
str) -> PeerConfigBundle`, constructed with a new injected
`AssertionValidationClient` (Design decision 1's consumer, mirroring
`LoginAuthorityClient`'s Protocol + `Real*` split — see Public seam). Flow:

1. Validate `public_key` (reuses `validate_public_key`, unchanged).
2. Call `assertion_validation_client.validate(assertion)` → `(account_id,
   expires_at)` or a bounded `AssertionValidationError`.
3. `store.get_allocation_by_account_id(account_id)`:
   - **No existing allocation:** proceed exactly like `redeem`'s invite path
     — allocate the next free address, call OPNsense `add_client` +
     `reconfigure`, and only on success call `record_assertion_redeem` to
     commit the durable row. The existing fail-closed ordering ("no local
     allocation committed unless OPNsense registration already succeeded")
     is preserved verbatim; `record_assertion_redeem` is the sole commit
     point exactly as `redeem_invite` already is for the invite path.
   - **Existing allocation, same `public_key`:** idempotent path — no OPNsense
     call, `touch_allocation_last_seen(account_id, now)`, and return a
     `PeerConfigBundle` built from the stored row plus the unchanged static
     config fields (`server_public_key`, `endpoint`, `allowed_ips`,
     `persistent_keepalive_seconds`). This is the re-login-from-the-same-
     device happy path the ADR names, and it makes zero upstream calls, so it
     cannot itself exhaust the pool or hammer OPNsense.
   - **Existing allocation, different `public_key`:** reject with a new
     bounded `RedeemRejectionReason.ACCOUNT_PEER_KEY_MISMATCH` (see non-goal
     above — rotation is out of scope). Chosen over silently re-registering
     the new key, because accepting a signed assertion alone as sufficient
     authority to redirect an *existing* peer's WireGuard identity to a new
     keypair has no cross-check that the caller actually controls the old
     keypair too, and ADR 0004 gives assertion validation no such guarantee —
     it proves account identity, not device continuity.
4. `AssertionValidationError`/`AccountAlreadyHasPeerError`
   (the race case, resolved by re-reading the winning row and applying the
   same same-key/different-key branch above) map to bounded
   `RedeemRejected` reasons the same way `RedeemRejected` already wraps
   `InvalidPublicKeyError`/`PoolExhaustedError`.

`POST /redeem`'s Pydantic model becomes `RedeemRequest {invite_code:
str | None = None, assertion: str | None = None, public_key: str}` with a
model validator requiring **exactly one** of `invite_code`/`assertion` (both
present or both absent is a bounded 400, not silently picking one). The route
dispatches to `service.redeem()` or `service.redeem_with_assertion()`
accordingly; both return the existing `RedeemResponse` shape unchanged, so
callers of the assertion path get the identical bundle shape the invite path
already returns.

**Rejected alternative (endpoint shape):** a separate `POST
/redeem-assertion` route. Rejected primarily because Slice 054's live
deployment publishes only `/healthz` and `/redeem` through the OPNsense
nginx TLS vhost in front of the enrollment service — adding a third public
path would need a new vhost allowlist entry, an ops change outside this
records-first slice's scope, whereas extending the existing `/redeem` body
schema needs no new ops work at all. It also avoids forking the
`RedeemResponse`/rejection-status-mapping logic across two routes for what is
the same "hand me a peer" operation gated by two different kinds of
credential.

### 3. Aging / deprovision

**Trigger:** a bounded, configurable idle threshold,
`ENROLLMENT_PEER_IDLE_TTL_SECONDS` (new `EnrollmentConfig` field, `os.getenv`-
driven with a fail-loud-on-invalid-value parse identical to the existing
`ENROLLMENT_PERSISTENT_KEEPALIVE_SECONDS`/`LOGIN_AUTHORITY_TIMEOUT_SECONDS`
pattern; proposed default `2592000` seconds / 30 days, open for Copilot to
confirm against operator expectations), measured from `last_seen_at`.

**Design decision — fold "assertion expired" into the same idle signal,
rather than tracking per-peer assertion expiry separately.** An assertion is
short-lived (300s TTL, Slice 088's `ASSERTION_TTL_SECONDS`) and is used once
at redeem time, then discarded — nothing about it is meaningful to persist on
a peer row that may live for weeks. Persisting it would also cut against
Slice 088's "no persistent loopback-originated session/artifact" safety
invariant. Because `touch_allocation_last_seen`/`record_assertion_redeem` can
only ever be reached by presenting a *currently-valid* assertion (Design
decision 1's `validate_assertion` call gates every path into them),
"`last_seen_at` older than the idle threshold" already implies "no valid
assertion has been presented for this account in that window" — a single
mechanism covers both trigger conditions ADR 0004 names ("idle past a bounded
threshold" and "assertion expired") without double-bookkeeping.

**Scope limitation, stated explicitly:** `last_seen_at` reflects the last
*redeem* call, not the last live WireGuard packet — the enrollment service
has no visibility into OPNsense/WireGuard handshake or traffic telemetry, only
its own `/redeem` calls. A player who redeems once and then plays for weeks
without calling `/redeem` again looks idle by this measure. This is an
accepted approximation for this slice (the launcher, per Slice 090's future
scope, is expected to call `/redeem` on every connect attempt, not just the
first), not a claim that `last_seen_at` tracks tunnel activity.

**Mechanism:** a new store method, `list_stale_account_allocations(older_than:
float) -> list[(account_id, public_key)]`, scoped to `account_id IS NOT NULL
AND last_seen_at < ?` — invite-path allocations (`account_id IS NULL`) are
never selected, preserving non-goal 4. A new `EnrollmentService.deprovision_stale_peers(now)
-> list[RevocationResult]` iterates the stale list and calls the existing
`RevocationService.revoke(public_key)` (Slice 049) for each — **reused
verbatim, not reimplemented**: `RevocationService.revoke` already provides
the atomic, fail-closed guarantee this decision needs (no local release
unless the OPNsense `delete_client` + `reconfigure` calls already succeeded).
A single peer's `RevocationRejected` (upstream delete failure) is isolated to
that peer — the sweep continues to the next stale allocation rather than
aborting the batch, and the failed peer's row is untouched, so it is
retried on the next sweep rather than silently dropped.

**Driving mechanism:** a new operator CLI subcommand,
`infra/enrollment/cli.py deprovision-stale [--older-than-seconds N]
[--dry-run]`, mirroring the existing CLI-only `mint-invite`/`revoke-peer`
commands (Slice 049 deliberately kept `revoke-peer` CLI-only, no HTTP admin
route, "logic + tests" scope — this slice follows the same precedent). A
systemd timer invoking this command on a schedule is deployment evidence for
a later handoff (the same records-first/deployment-evidence split Slice 088
used), not something this slice runs.

**Rejected alternative:** an in-process background asyncio sweep inside the
FastAPI app, running on a timer. Rejected because (a) `CLAUDE.md` explicitly
disallows "placeholder runtime loops or speculative production code" absent a
bounded delivered slice backing them, and an implicit always-on background
task is exactly that shape; (b) it couples deprovision timing to the FastAPI
process's own lifecycle/restarts, so a redeploy silently resets or skips a
sweep window; (c) it has no operator-visible, individually auditable
invocation the way a CLI call (loggable, wrapped in cron/systemd with its own
exit-code/log trail) does — the same reasoning that already kept
`revoke-peer` CLI-only rather than automatic in Slice 049.

### 4. Invite path retained

No change to `EnrollmentService.redeem`, `EnrollmentStore.redeem_invite`,
`EnrollmentStore.mint_invite`, the `invites` table, or the
`{invite_code, public_key}` request/response contract. The `allocations` table
change (two new nullable columns) is additive and does not alter any existing
column, constraint, or query the invite path already uses — an invite-path
`redeem_invite` call continues to insert `account_id = NULL`, `last_seen_at =
now` (harmless — invite-path rows are never selected by
`list_stale_account_allocations`, so the new column has no observable effect
on that path).

## Public seam

**Login authority (Godot, `server/`):**

- `server/login_gateway.gd`: new method `validate_assertion(token: String,
  now_unix: int) -> Dictionary` — a one-line pass-through to the already-wired
  `_validator.validate()`, no `SessionRegistry` interaction, fail-closed
  `REASON_UNAVAILABLE` when no validator is wired (mirrors
  `issue_account_assertion`'s existing `_issuer == null` guard).
- `server/login_loopback_http_endpoint.gd` (extend Slice 088's class, do not
  duplicate it): a second accepted exact-match path, `POST
  /internal/validate-assertion`, dispatched from the same `TCPServer`/strict
  parser/byte-cap machinery. Request body `{"assertion": String}` (bounded,
  1 KiB cap unchanged). Response `200 {"outcome": "ok", "account_id": String,
  "expires_at": int}` on success; bounded non-200 `{"outcome": "<reason>"}`
  reusing `SessionAssertion.REASON_*` strings on rejection. No synthetic
  peer id, no session bind/clear (unlike the verify-and-mint path) — this
  path has no `SessionRegistry` interaction at all.
- No change to `server/login_runtime.gd`'s existing
  `AssertionValidatorScript.new(...)` construction or
  `gateway.set_assertion_seams(issuer, validator)` wiring — both already
  exist and are reused as-is.

**Enrollment service (Python, `infra/enrollment/`):**

- `infra/enrollment/login_client.py`: a second Protocol + `Real*` pair
  alongside the existing `LoginAuthorityClient`/`RealLoginAuthorityClient` —
  `AssertionValidationClient` with `validate(assertion: str) -> tuple[str,
  int]` (returns `(account_id, expires_at)`, raises a bounded
  `AssertionValidationError` on rejection/timeout/connection failure, reusing
  the same bounded-reason vocabulary shape as `LoginAuthorityError`), and
  `RealAssertionValidationClient(host, port, timeout_seconds)` posting to
  `POST /internal/validate-assertion` on the **same** `login_authority_host`/
  `login_authority_port`/`login_authority_timeout_seconds` config Slice 088
  already added — no new config surface, just a second client against the
  same already-configured loopback target.
- `infra/enrollment/store.py`: `allocations` table gains `account_id
  TEXT`/`last_seen_at REAL` (nullable, migrated idempotently — see Design
  decision 2 and Safety invariants), a partial unique index on
  `account_id`, and the new methods `get_allocation_by_account_id`,
  `record_assertion_redeem`, `touch_allocation_last_seen`,
  `list_stale_account_allocations`; a new `AccountAlreadyHasPeerError`
  exception for the race path.
- `infra/enrollment/service.py`: `EnrollmentService.redeem_with_assertion`,
  a new `RedeemRejectionReason.ACCOUNT_PEER_KEY_MISMATCH` /
  `RedeemRejectionReason.ASSERTION_REJECTED` pair, and
  `EnrollmentService.deprovision_stale_peers` (reusing the existing
  `RevocationService` instance already available to production wiring).
- `infra/enrollment/app.py`: `RedeemRequest` gains optional `assertion:
  str | None` alongside `invite_code: str | None`, with a Pydantic model
  validator enforcing exactly one is set; `_REJECTION_STATUS` gains
  `ACCOUNT_PEER_KEY_MISMATCH -> 409`, `ASSERTION_REJECTED -> 401`; the
  `/redeem` handler dispatches to `service.redeem()` or
  `service.redeem_with_assertion()` based on which field is present.
  `build_production_service`/a new
  `build_production_assertion_validation_client` follow the existing
  `build_production_login_authority_client` wiring pattern.
- `infra/enrollment/config.py`: new `EnrollmentConfig.peer_idle_ttl_seconds`
  field, `ENROLLMENT_PEER_IDLE_TTL_SECONDS` env var, same fail-loud parse
  pattern as the existing numeric config fields.
- `infra/enrollment/cli.py`: new `deprovision-stale [--older-than-seconds N]
  [--dry-run]` subcommand, mirroring the existing `mint-invite`/`revoke-peer`
  command shapes.

## Safety invariants (security-focused)

- **Loopback-only, no new bind.** `POST /internal/validate-assertion` is
  served from the same `TCPServer` Slice 088 already bound to the literal
  `"127.0.0.1"` — this slice adds no new bind, no new port, and no new
  override surface. The "never reachable except from the same host" argument
  from Slice 088's Safety invariants applies unchanged.
- **The assertion-signing/verification secret never reaches the enrollment
  service.** `PROJECT0_ASSERTION_SECRET` stays exclusively on the login
  authority process; the enrollment service only ever sees the bounded
  `(account_id, expires_at)` result or a bounded rejection reason over the
  loopback call — never the secret, never the raw token internals beyond what
  it already held (the opaque assertion string itself, which it also already
  handled in Slice 088's `/login` response).
- **Fail-closed on any validation/parse error.** A malformed, expired,
  tampered, or wrong-issuer/audience assertion, or an unreachable/erroring
  loopback endpoint, must all result in a bounded `RedeemRejected` and no
  local allocation commit, no OPNsense call, and no `last_seen_at` touch —
  the existing "no local state changes unless the upstream call already
  succeeded" ordering (already true for `redeem`'s invite path and
  `RevocationService.revoke`) extends unchanged to `redeem_with_assertion`.
- **Atomic allocation and atomic reclamation.** `record_assertion_redeem`
  commits its row in one `sqlite3` transaction (mirroring `redeem_invite`),
  and the aging sweep's per-peer reclamation reuses
  `RevocationService.revoke`'s existing atomic, fail-closed delete-then-
  release ordering verbatim — no partial durable state on either path.
- **No collision between an account's live peer and a same-account race.**
  The partial unique index on `account_id` is the enforcement point (not
  merely an application-level `SELECT`-then-`INSERT` check, which would race);
  a losing concurrent insert raises `AccountAlreadyHasPeerError` and is
  resolved by re-reading the winning row rather than silently overwriting it.
- **No key-mismatch takeover.** As stated in Design decision 2, an assertion
  proving account identity is not treated as sufficient authority to
  re-point an existing peer's WireGuard public key — `ACCOUNT_PEER_KEY_MISMATCH`
  fails closed rather than silently rotating.
- **Idempotent schema migration on an already-live database.** The
  `ALTER TABLE allocations ADD COLUMN` migration in `EnrollmentStore.__init__`
  must be safe to run against the already-populated, already-deployed sqlite
  file on `192.168.1.254` (Slice 054) without data loss or duplicate-column
  errors on repeated boots — verified by a test that runs the migration twice
  against a store pre-seeded with an invite-path allocation row and asserts
  the row is unchanged and the second run does not raise.
- **No assertion, account id, or public key logged verbatim beyond the
  existing bounded-reason discipline.** Every log/print added by this slice
  (`redeem_with_assertion`, the new loopback handler, the CLI sweep command)
  logs only bounded outcome/reason strings and non-secret identifiers already
  treated as loggable elsewhere in this codebase (`account_id`, `public_key`
  — both already appear in existing `RevocationService`/`redeem_invite` call
  sites and are not secrets), never the assertion token itself or exception
  `str()` text that could embed request content, matching `CLAUDE.md`'s
  Telemetry rule and Slice 088's identical discipline.
- **Aging sweep is operator-invoked, not silently automatic.** As stated in
  Design decision 3, no in-process background loop runs inside the FastAPI
  service; deprovisioning only happens when the CLI command is explicitly
  invoked (by an operator or an ops-owned scheduler outside this slice's
  scope), so there is no implicit runtime behavior to reason about beyond
  what is exercised by tests.

## BDD/TDD plan (tests to write in the implementation handoff — not written here)

**Godot/GUT — the new loopback validate-assertion path** (proposed file:
`tests/integration/test_login_loopback_http_endpoint.gd`, extending Slice
088's existing suite rather than a new file, since it is the same class):

- *Valid assertion → account id + expiry.* Given a `LoginGateway` with a real
  wired `AssertionValidator`/`AssertionIssuer` pair and a minted assertion
  (via `issue_account_assertion`), when a raw `StreamPeerTCP` client sends
  `POST /internal/validate-assertion` with that token, then the response is
  `200` with `{"outcome": "ok", "account_id": "<the issuing account>",
  "expires_at": <int>}` matching the claims the issuer signed, and
  `SessionRegistry` holds no new session (asserting the "no bind" invariant —
  the key behavioral difference from `/internal/verify-and-mint`).
- *Expired / tampered / wrong-issuer assertion → bounded reject.* An expired
  token, a token with a flipped signature byte, and a token signed for a
  different issuer/audience each return a non-200 with the corresponding
  `SessionAssertion.REASON_*` string and, again, no session created.
- *Malformed/oversized request → reject, listener keeps serving.* Missing
  `assertion` key, non-string value, and an oversized body each produce a
  bounded rejection without crashing `_process()`'s loop, matching the
  existing malformed-request coverage for `/internal/verify-and-mint`.
- *Two paths coexist on one listener.* A `/internal/verify-and-mint` request
  and a `/internal/validate-assertion` request against the same running
  endpoint instance both dispatch correctly (regression test for the
  extended dispatch-by-path logic not regressing the existing route).
- *`LoginGateway.validate_assertion` unit coverage* (proposed file:
  `tests/unit/test_login_gateway_assertions.gd` extension or a focused new
  script): valid token → claims returned, no `SessionRegistry` call recorded
  against a fake sessions object; `_validator == null` → `REASON_UNAVAILABLE`.

**Python/pytest — the enrollment `/redeem` assertion path and lifecycle**
(proposed files: `infra/enrollment/tests/test_service.py` extension for
`redeem_with_assertion`/`deprovision_stale_peers`, `infra/enrollment/tests/test_store.py`
extension for the new store methods and the migration, `infra/enrollment/tests/test_app.py`
extension for the `/redeem` route's dual-shape dispatch, a new
`infra/enrollment/tests/test_assertion_validation_client.py` mirroring
`test_login_service.py`'s structure, and `infra/enrollment/tests/test_cli.py`
extension for `deprovision-stale`):

- *Valid assertion, new account → peer allocated.* A fake
  `AssertionValidationClient.validate()` returns `(account_id, expires_at)`;
  `redeem_with_assertion` allocates a new address, calls the fake OPNsense
  client's `add_client`/`reconfigure`, and commits a row with that
  `account_id`; the returned bundle matches the invite path's shape.
- *Expired/tampered assertion → reject, no side effect.* The fake raises
  `AssertionValidationError` with a bounded reason; no address is allocated,
  no OPNsense call is made (asserting the fake OPNsense client's call count
  is zero — the same "no upstream call on a rejected credential" pattern
  `test_service.py` already asserts for `INVITE_NOT_FOUND`).
- *Idempotent re-redeem, same account + same public key → same bundle, no
  new OPNsense call.* Redeem once, then redeem again with a fresh (fake)
  assertion for the same account and the same public key; the second call
  returns byte-for-byte the same `PeerConfigBundle` and the fake OPNsense
  client's `add_client` is called exactly once total (not twice) —
  the direct regression test for the ADR's idempotency requirement.
- *Re-redeem, same account + different public key → `ACCOUNT_PEER_KEY_MISMATCH`,
  409, no allocation change.* Confirms the rejection path from Design
  decision 2, and that the original allocation row is untouched.
- *Concurrent first-time redeem for the same account → one winner, one
  `AccountAlreadyHasPeerError` resolved without duplicate allocation.*
  Simulates the store-level race directly against a real (non-fake) temp
  sqlite `EnrollmentStore`, asserting the partial unique index rejects the
  second insert and exactly one allocation row exists afterward.
- *Pool exhaustion still handled on the assertion path.* With the pool
  pre-filled to exhaustion, a new-account assertion redeem raises
  `POOL_EXHAUSTED` exactly as the invite path already does (reusing
  `test_service.py`'s existing exhaustion fixture pattern).
- *`/redeem` request-shape validation.* A request with both `invite_code` and
  `assertion` set, and a request with neither set, are both rejected by
  Pydantic validation with a bounded 400 before either service method is
  called (fake call counts stay zero for both).
- *Migration idempotency.* Opening an `EnrollmentStore` twice in a row against
  the same temp db file (simulating a service restart) does not raise and
  leaves any pre-existing invite-path allocation row (`account_id IS NULL`)
  unchanged; a third open after some assertion-path rows already exist
  likewise leaves them unchanged.
- *Aging sweep reclaims only stale, assertion-path allocations.* Given one
  fresh assertion-path allocation, one stale (past-threshold `last_seen_at`)
  assertion-path allocation, and one invite-path allocation (`account_id`
  `NULL`, arbitrarily old `last_seen_at`), `deprovision_stale_peers` calls the
  fake OPNsense `delete_client` exactly once (for the stale assertion-path
  row only) and leaves the fresh and invite-path rows untouched.
- *Aging sweep isolates a single peer's upstream failure.* Two stale
  allocations, one whose fake `delete_client` raises `OpnsenseApiError`; the
  sweep still processes the second stale allocation, the failing one's row
  remains allocated (untouched, retryable), and the sweep's return value
  reports both outcomes rather than raising and aborting.
- *CLI `deprovision-stale --dry-run` performs no mutation.* Reuses the
  existing CLI test harness pattern (`test_cli.py`) to assert a dry run lists
  candidates without calling revoke.

## Validation plan (commands for the implementation handoff to run)

- **GDScript/GUT, focused first:** run the extended
  `tests/integration/test_login_loopback_http_endpoint.gd` directly, then
  `godot --headless --check-only -s server/login_gateway.gd` and `-s
  server/login_loopback_http_endpoint.gd` as the cheapest discriminating
  parse checks (Slice 088's Root-cause learning recorded a parse-only defect
  that the full suite alone did not surface fast enough — repeating that
  check here before the full run), then the full gate:
  `scripts/run_gut_validation.sh`. Expected pass signal: exit 0, with
  `build/validation/gut.xml` and `build/validation/validation-summary.json`
  showing all scripts green, no reduction from Slice 088's 415/415 baseline
  plus the new cases.
- **Python/pytest:** `python3 -m pytest infra/enrollment/tests -q` (or the
  Linux host's `.venv-enrollment/bin/python`, matching every prior enrollment
  slice's validation command). Expected pass signal: all tests pass, exit 0,
  no reduction from Slice 088's 70/70 baseline plus the new
  assertion-redeem/lifecycle/migration/CLI cases.
- **Record sync:** `scripts/check_record_sync.sh`, expected exit 0.
- **Not run by this records-first handoff:** no build/test/git command was
  executed to produce this planning record. That is Copilot's/the
  implementation handoff's next step, per this repository's records-first
  delivery gate (`AGENTS.md`, `docs/DEVELOPMENT-WORKFLOW.md`).

## Validation evidence

Implemented directly by Copilot (Claude CLI was at its session limit; the user
explicitly authorized direct Copilot implementation for this slice).

- **GUT full suite** on the Linux host (192.168.1.254), isolated git worktree
  of commit `65ccc54`, `GODOT_BIN=godot bash scripts/run_gut_validation.sh`
  (Windows cannot run GUT — no `windows.x86_64` `gdsqlite`/`wgnetstack`
  binaries): `validation-summary.json` status `passed`, exit 0,
  scripts 62/62, **420 tests passing, 1553 asserts, 0 failing** (up from Slice
  088's 415 — +5 new validate-assertion/dual-path/`validate_assertion` cases in
  `tests/integration/test_login_loopback_http_endpoint.gd`).
- **Enrollment pytest** on the host `.venv-enrollment`
  (`python -m pytest infra/enrollment/tests -q`): **96 passed, exit 0** (up
  from 70 — +26 new store-migration/lifecycle, `redeem_with_assertion`,
  dual-`/redeem`, assertion-validation-client, and `deprovision-stale` cases).
  Reproduced locally on Windows (fresh venv): 96 passed, exit 0.
- **Parse checks** (Windows, cheapest discriminating check before the host
  run, per Slice 088's learning): `godot --headless --check-only -s
  server/login_loopback_http_endpoint.gd` and `-s server/login_gateway.gd`
  both exit 0.

## Root-cause learning

- **Adding a required `EnrollmentConfig` field broke every test `make_config`
  helper.** Symptom: after adding `peer_idle_ttl_seconds` (a non-default
  dataclass field), 18 existing tests failed / 12 errored with
  `TypeError: EnrollmentConfig.__init__() missing 1 required positional
  argument`. Seam: `infra/enrollment/config.py::EnrollmentConfig`. Discriminating
  check: `pytest infra/enrollment/tests -q`. Root cause: two duplicated
  `make_config()` builders (in `test_service.py` and `test_app.py`, imported by
  the rest) construct the frozen dataclass positionally-by-keyword and do not
  tolerate a new required field. Countermeasure applied: added the field to both
  builders in the same change; regression evidence is the green 96/96 run.
  Remaining debt: the duplicated config builder is a small liability (a future
  slice could centralize a single test config factory), not opened as a formal
  DT item given its low cost. No unexpected *runtime* failure occurred — this
  was a compile-time/test-fixture surface caught immediately by the suite.

## ADR link

[ADR 0004 — Auth-gated, on-demand tunnel provisioning](../adr/0004-auth-gated-tunnel-provisioning.md)
(accepted). This slice implements follow-up item (B) — sub-decision 3 (peer
lifecycle: gate `/redeem` on an assertion, idempotent and aging provisioning)
in full, and reuses sub-decision 2's delegation posture (extended here from
credential verification to assertion validation) for Design decision 1.
Sub-decision 4 (invite path retained) is preserved unmodified. Sub-decision 1
(HTTPS transport) and the rest of sub-decision 2 were already implemented by
Slice 088 and are reused without re-litigation.

## Record links

- Planning ticket / decision basis: [ADR 0004](../adr/0004-auth-gated-tunnel-provisioning.md).
- Slice registry reservation: [docs/slices/SLICE-REGISTRY.md](SLICE-REGISTRY.md)
  (row 089; 090 reserved for the launcher/client flow that follows).
- Governing feature: [P-024](../FEATURE-LIST.md#p-024-public-game-access-via-opnsense-native-wireguard),
  Phase 11 — Public game access.
- Sibling delegation pattern this design extends without re-deriving:
  [Slice 088 — Auth-gated onboarding A: HTTPS /login delegation](088-auth-gated-onboarding-login-delegation.md).
- Related prior slices this design reuses without modification: [Slice 059 — Signed session assertion contract, issuer, and validator](059-session-assertions.md),
  [Slice 048 — WireGuard invite-code enrollment service](048-wireguard-enrollment-service.md)
  (the `next_free_address`/atomic-commit pattern `record_assertion_redeem`
  mirrors), [Slice 049 — WireGuard peer revocation/ban lifecycle](049-wireguard-revocation-lifecycle.md)
  (`RevocationService.revoke`, reused verbatim by the aging sweep, and the
  CLI-only admin-action precedent the new `deprovision-stale` command
  follows).
- Open liability referenced, not re-opened: [DT-009](../TECHNICAL-DEBT-TRACKER.md#dt-009-public-login-on-the-enrollment-service-has-no-rate-limiting-lockout-or-anti-enumeration).

## Open forks for review

Surfaced for Copilot design review — these are judgment calls this record
made to keep the slice bounded, not decisions the brief or ADR text dictated
outright:

1. **Key-mismatch rejection vs. silent rotation** (Design decision 2, and the
   restated non-goal above). The ADR text only says a re-login "MUST return
   that existing peer configuration"; it does not address what happens when
   the presented `public_key` differs from the one on file. This record
   chose fail-closed rejection over silent rotation. If reinstall/lost-keypair
   recovery needs to work without an operator's manual `revoke-peer` in the
   near term, that changes this slice's scope or accelerates a rotation
   follow-up.
2. **Idle-TTL default (30 days) and its "redeem-call recency, not tunnel
   activity" semantics** (Design decision 3). Both the exact default and the
   accepted approximation (idle = no `/redeem` call, not no WireGuard
   traffic) are proposals pending operator input; Slice 090's launcher design
   (how often it calls `/redeem`) directly affects whether this measure is
   meaningful in practice.
3. **Endpoint reuse vs. duplication for the loopback listener** (Design
   decision 1). This record chose to extend Slice 088's single-path
   `LoginLoopbackHttpEndpoint` class into a two-path dispatcher rather than
   standing up a second listener/class. That is a real (if narrow)
   modification to a slice already marked `delivered`, and its own test
   suite grows in place rather than gaining a parallel file — flagging in
   case review prefers stricter isolation between the two loopback purposes
   despite the shared-process, shared-trust-boundary rationale given above.

## Root-cause learning

Not applicable yet — no code exists for this slice, so no runtime failure,
validation failure, or integration surprise has occurred. This section is a
placeholder per `docs/DEVELOPMENT-WORKFLOW.md`'s root-cause learning gate and
must be filled in before this slice can be marked delivered, exactly as
Slice 088's two pre-merge defects were recorded in its own Root-cause
learning section.
