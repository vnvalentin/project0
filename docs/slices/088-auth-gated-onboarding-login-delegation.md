# Slice 088 — Auth-gated onboarding A: HTTPS `/login` on the enrollment service, delegating credential verification to the login authority
GitHub issue: #95

Status: **delivered**

Tracker context: Phase 13 — Public game access; advances
[P-024](../FEATURE-LIST.md#p-024-public-game-access-via-opnsense-native-wireguard)
per [ADR 0004](../adr/0004-auth-gated-tunnel-provisioning.md) follow-up (A). This is
the first of a three-slice sequence the ADR names but deliberately does not
reserve numbers for; `docs/slices/SLICE-REGISTRY.md` reserves 088 (this slice),
089 (peer provisioning / `/redeem`), and 090 (launcher/client flow) against that
sequence. No new feature id is created: 088's registry title cites only
`P-024, ADR 0004` (not `F-035`) — see "Feature id note" below.

## Feature id note (read before assigning telemetry/tracker entries)

The handoff brief that produced this record asked to confirm "P-024, and the
WAN-enrollment feature id, likely F-035." Checking `SLICE-REGISTRY.md`'s
already-reserved title for 088 resolves this: it cites `(P-024, ADR 0004)`
only. `F-035` ([Secure Windows tunnel enrollment and credential
storage](../FEATURE-LIST.md#f-035-secure-windows-tunnel-enrollment-and-credential-storage))
is the *Windows-launcher-side* feature — DPAPI credential storage and the
launcher's `/redeem` call — and is the governing feature for Slice 090
(launcher/client flow), not this slice. This slice adds a new public HTTPS
surface and a new internal delegation seam on infrastructure P-024 already
owns (the enrollment service and the login authority), with no launcher-side
code. It is therefore tracked directly under **P-024** (Phase 13), matching
the registry's own title. This record does not create a new `F-` id; Copilot
review should confirm this reading before merge.

## User outcome

A player who has never received an invite code can authenticate with just a
username and password over public HTTPS and receive a signed session
assertion — the credential the rest of the auth-gated onboarding chain (Slice
089's `/redeem`, Slice 090's launcher/tunnel/game handoff) needs to provision a
tunnel peer and enter the world. No third-device invite-code delivery step
exists on this path. (This slice delivers only the login step; provisioning
and the launcher flow are Slices 089/090 — see Scope below.)

## Problem

Today the only way to obtain a WireGuard peer is `POST /redeem` with an
invite code minted out-of-band by an operator
(`infra/enrollment/cli.py mint-invite`). ADR 0004 replaces that first step with
self-service login, but the enrollment service (`infra/enrollment/`) has no
accounts database, no PBKDF2 verification, and no assertion-signing key — all
of that lives on the login authority (`server/auth_service.gd`,
`server/assertion_issuer.gd`, fronted by `server/login_gateway.gd`), which
today only accepts ENet/UDP connections on port 9998 (`server/login_server_main.gd`).
That ENet surface is not meant to be Internet-facing (ADR 0004 sub-decision 1:
opening raw UDP 9998 to the WAN duplicates TLS/WAF/rate-limiting work
Cloudflare already does in front of the enrollment service, and enlarges the
unauthenticated-packet attack surface). This slice closes the gap: a public
HTTPS `/login` on the enrollment service that delegates the actual credential
check to the login authority over a new **loopback-only** seam, never
duplicating PBKDF2 verification or HMAC signing (ADR 0004 sub-decision 2).

## Scope and non-goals

**In scope:**

- A new loopback-only HTTP/JSON endpoint on the Godot login process
  (`server/login_server_main.gd`'s process), `POST /internal/verify-and-mint`,
  implemented with `TCPServer`/`StreamPeerTCP` (the same primitives as
  `scripts/fake_ollama_http_server.gd`) behind a strict, bounded request
  parser. It reuses `LoginGateway.login()` (→ `AuthService.login()`, PBKDF2
  verify + session bind) and `LoginGateway.issue_account_assertion()` (→
  `AssertionIssuer.issue()`, HMAC signing) — it adds no new credential or
  signing logic.
- A new public endpoint on the enrollment service (`infra/enrollment/`),
  `POST /login {username, password}`, that calls the loopback endpoint above
  and returns its signed assertion (or a bounded rejection) to the caller. The
  enrollment service gains no accounts-DB access and no PBKDF2 code.
- Verifying (or correcting) the co-location assumption that `project0-login`
  and `project0-enrollment` run on the same host, so the enrollment→login-authority
  hop is a loopback call, not a second public hop.
- New, narrowly scoped configuration to locate the loopback endpoint
  (host/port) from the enrollment service's config, and to bind/port the
  loopback listener on the login process.

**Explicitly out of scope (non-goals of this slice):**

- Peer provisioning: `/redeem` accepting a signed assertion in place of
  `invite_code`, and the idempotent per-account peer lifecycle/aging ADR 0004
  sub-decision 3 requires. That is **Slice 089**.
- Any Windows launcher or Godot client change (login screen, DPAPI storage,
  tunnel-then-handoff sequencing). That is **Slice 090** (and reuses F-035 for
  the launcher-side pieces).
- **Rate-limiting, lockout, and anti-enumeration on the public `/login`.**
  ADR 0004's Consequences section states this is now *required* because the
  enrollment service exposes a public authentication surface it did not
  previously have. This slice does **not** implement it — `AuthService.login`
  already pays a fixed PBKDF2 cost on an unknown username (no timing
  enumeration) and returns an identical `BAD_CREDENTIALS` reason for both
  "unknown user" and "wrong password" (no message enumeration), but neither
  the enrollment service nor the loopback endpoint added here throttles
  *repeated* attempts, and Cloudflare's WAF in front of the enrollment service
  is not a substitute for application-level lockout. **This is a named,
  tracked liability, not a silent gap**: it must be filed in
  `TECHNICAL-DEBT-TRACKER.md` (or closed by a follow-up slice) before this
  path is treated as safe to advertise publicly. Flagged again under Safety
  invariants below.
- Peer/session cleanup of the synthetic loopback session beyond the
  request/response lifetime described in Public seam (no persistent
  loopback-originated session is left bound).
- Any change to the invite-code path (`POST /redeem` with `invite_code`),
  which ADR 0004 sub-decision 4 retains unmodified.

## Co-location assumption — verified

ADR 0004 assumes `project0-login` and `project0-enrollment` run on the same
host so the enrollment→login-authority call is loopback/private. Cross-checking
the repository's own delivery records (not just the ADR's prose) confirms
this for the *currently deployed* topology:

- The enrollment service is deployed live as systemd `project0-enrollment.service`
  on the Linux host `192.168.1.254` ("okami"), bound to `192.168.1.254:8095`
  ([Slice 054](054-secure-windows-tunnel-enrollment.md) tracker entry;
  [FEATURE-LIST.md F-035 change history](../FEATURE-LIST.md#f-035-secure-windows-tunnel-enrollment-and-credential-storage)).
- The game server and, per Slices 055–064's "Runtime evidence" sections, the
  login-split login process are all run and validated on the same host
  `192.168.1.254` (e.g. [Slice 058](058-login-gateway-seam.md),
  [Slice 059](059-session-assertions.md), [Slice 060](060-assertion-session-binding.md),
  [Slice 070](070-deploy-supervise-login-server.md)'s `project0-login` systemd
  unit).

So the assumption holds for today's deployment: both processes are on
`192.168.1.254`, and the enrollment→login-authority hop is a call to
`127.0.0.1` (or the host's LAN address) on that single box, never a public
hop. **What was not independently reverified**: whether `project0-login`'s
systemd unit is guaranteed to stay co-located with `project0-enrollment` as a
durable operational invariant, or whether that's simply where it happens to
run today. This record treats co-location as a load-bearing assumption for the
loopback design below and calls it out again for Copilot review — if a future
deployment ever splits these processes across hosts, the loopback bind
(127.0.0.1-only, see Safety invariants) would need to become a private
LAN/VPN-only bind instead, which is a design change, not a config flag.

## Public seam

**Login authority (Godot, `server/`):**

- New file (proposed): `server/login_loopback_http_endpoint.gd`,
  `class_name LoginLoopbackHttpEndpoint`. A `Node` following
  `scripts/fake_ollama_http_server.gd`'s `TCPServer`/`StreamPeerTCP` +
  `_process()` poll pattern, but with a real strict parser (the fixture script
  deliberately does *not* parse — it drains and ignores the request; this
  production seam must not reuse that shortcut). Public methods: `start() ->
  int` (returns the bound port, or `-1` on bind failure), `stop() -> void`.
  Bound **hard-coded to `127.0.0.1`** — never resolved from
  `PROJECT0_SERVER_BIND_ADDRESS` or any other override (see Safety
  invariants). Port resolved by a new `NetworkConfig.resolve_login_http_port()`
  (proposed: CLI `--login-http-port=`, env `PROJECT0_LOGIN_HTTP_PORT`, default
  `9997` — adjacent to the existing `9998` ENet login port; open for Copilot
  to confirm the exact default against any existing firewall/port allocation
  the operator has already reserved).
- Wired from `server/login_server_main.gd`'s `_start_login_server()`,
  constructed with the same `_login_gateway` handle already built by
  `LoginRuntime.build_services()` — no second gateway, no second
  `AssertionIssuer`.
- Request contract: `POST /internal/verify-and-mint` (exact path match, POST
  only), JSON body `{"username": String, "password": String}` (both required,
  non-empty, bounded length — matching `AuthService._validate_credentials`
  plus an explicit byte cap so a huge body can't force wasted PBKDF2/parse
  work). Response `200 {"outcome": "ok", "assertion": "<token>"}` on success;
  bounded non-200 `{"outcome": "<reason>"}` on rejection (reasons: `bad_credentials`,
  `malformed`, `unavailable` — reusing `CharacterRecord.REJECT_BAD_CREDENTIALS`
  and `LoginGateway.REASON_UNAVAILABLE` verbatim rather than inventing new
  strings). TTL for the minted assertion: reuse the existing
  `client/network_client.gd` `ASSERTION_REQUEST_TTL_SECONDS` (300s) constant
  rather than inventing a new tuning value — this assertion is consumed
  promptly by `/redeem` (Slice 089) and the game handoff (Slice 090), the same
  short-lived purpose that constant already serves.
- **Session-binding mechanism (the key non-obvious design point — see
  full rationale under Safety invariants):** `LoginGateway.login()` and
  `issue_account_assertion()` are keyed by an ENet `peer_id` (int) via
  `SessionRegistry`, but an HTTP request from the enrollment service has no
  ENet peer. The endpoint handler synthesizes a **negative** `peer_id` (a
  monotonically decrementing counter starting at `-1`) for the lifetime of
  one request, calls `gateway.login(synthetic_id, username, password)`, then
  on success `gateway.issue_account_assertion(synthetic_id, now, ttl)`, then
  **always** `gateway.clear_session(synthetic_id)` before writing the HTTP
  response — win or lose, no synthetic session outlives one request.

**Enrollment service (Python, `infra/enrollment/`):**

- New route in `app.py`: `POST /login`, Pydantic `LoginRequest {username: str,
  password: str}` → `LoginResponse {assertion: str}`, mirroring the existing
  `/redeem` route's `try/except RedeemRejected` → `HTTPException` mapping
  pattern with a parallel `LoginRejected` exception and `_LOGIN_REJECTION_STATUS`
  dict (`BAD_CREDENTIALS` → 401, `MALFORMED` → 400, `UPSTREAM_UNAVAILABLE` /
  `UPSTREAM_ERROR` → 502).
- New injectable client seam in `service.py` (or a new `login_client.py`
  module, mirroring `opnsense_client.py`'s `Protocol` + `Real*` split): a
  `LoginAuthorityClient` Protocol with `verify_and_mint(username, password) ->
  str` (returns the assertion, raises a bounded `LoginAuthorityError` on
  rejection/timeout/connection failure), and a `RealLoginAuthorityClient` that
  makes the actual loopback HTTP POST to `server/login_loopback_http_endpoint.gd`.
  `EnrollmentService` (or a small new `LoginDelegationService`, TBD at
  implementation time) depends on the Protocol, never on `requests`/`httpx`
  directly in a way that can't be faked in tests — same discipline as the
  existing OPNsense seam.
- New config in `config.py` (`EnrollmentConfig`): `login_authority_host`
  (default `"127.0.0.1"`, since co-located per the verification above),
  `login_authority_port` (must match the Godot side's resolved
  `PROJECT0_LOGIN_HTTP_PORT`), `login_authority_timeout_seconds` (bounded
  default, proposed `5`) — following the existing `os.getenv`-driven,
  fail-loud-on-missing-secret pattern already used for the OPNsense
  credentials.

## Safety invariants (security-focused)

- **Loopback-only bind, never the LAN/public IP.** The internal endpoint's
  `TCPServer.listen()` call MUST use the literal `"127.0.0.1"`, not
  `NetworkConfig.resolve_server_bind_address()` or any environment-driven
  value. This is a deliberate divergence from the existing ENet login port
  (which *does* allow a configurable bind for LAN dev, with a printed WARNING
  when non-default) — the loopback endpoint gets no such override, because
  its entire safety argument depends on it never being reachable except from
  the same host. Test coverage must assert the hardcoded bind, not just the
  default.
- **Strict, bounded HTTP parser — untrusted input cannot exhaust memory or
  smuggle requests.** Unlike `scripts/fake_ollama_http_server.gd` (which is
  test-only and does not parse), this seam accepts input from a process
  (`project0-enrollment`) that itself relays untrusted public traffic, so the
  parser must: accept `POST` only (reject all other methods with a bounded
  405); match the path exactly (`/internal/verify-and-mint`, reject others
  with a bounded 404); cap total header bytes (proposed 8 KiB) and total body
  bytes (proposed 1 KiB — a username/password pair never needs more) before
  reading further, closing the connection over either cap rather than
  buffering unbounded; require `Content-Type: application/json`; reject
  `Transfer-Encoding` (no chunked support — chunked parsing is exactly the
  kind of request-smuggling surface this parser must not grow); parse the
  body strictly as JSON with exactly the two expected string keys, rejecting
  unknown top-level keys, non-string values, and empty strings before calling
  into `AuthService`.
- **Credentials and the assertion value are never logged.** Every log/print
  in this seam and in the enrollment `/login` route must log only the bounded
  outcome/reason string (`ok`, `bad_credentials`, `malformed`, `unavailable`,
  `upstream_error`, ...), matching `AuthService`'s existing no-enumeration
  discipline and `CLAUDE.md`'s Telemetry rule ("Telemetry MUST avoid prompts
  containing sensitive player text, secrets..."). This applies to error paths
  too — an exception's `str(exc)` must not be logged or returned verbatim if
  it could ever embed the request body.
- **The internal endpoint is not reachable from the WAN.** Beyond the bind
  address itself, this must be verified operationally once deployed (host
  firewall / no port-forward rule for `PROJECT0_LOGIN_HTTP_PORT`), the same
  defense-in-depth pattern Slice 028 used for the game port (OPNsense rule
  *and* an independent host iptables lockdown) — a bind-address bug and a
  firewall misconfiguration should not both have to fail for this to leak.
  This is validation/deployment evidence for a later handoff, not something
  this records-first slice can prove.
- **Fail-closed on any parse/verify error.** A malformed request, an oversized
  request, an unparseable JSON body, or an `AuthService`/`LoginGateway`
  rejection must all result in an explicit bounded rejection and **no** bound
  session — the `clear_session` call in the handler is unconditional (success
  and failure paths both clear), so a rejected or errored request can never
  leave a synthetic session bound on the login process.
- **No synthetic-peer-id collision with real ENet sessions.** The negative
  `peer_id` counter is a hard requirement, not a convenience: real ENet peer
  ids assigned by `ENetMultiplayerPeer` are always non-negative (server is
  `1`, clients are positive), so a negative synthetic id space is provably
  disjoint from any real connected peer's `SessionRegistry` entry. Using a
  positive counter (even a "very large" one) would not have this guarantee
  and risks two coroutines (a real peer's register/login RPC and this
  endpoint's request) racing on the same `SessionRegistry` key across the
  `await get_tree().process_frame` points inside `AuthService`'s PBKDF2
  hashing — a real hazard given both paths call the same off-thread
  hash/verify helpers. This must be covered by a dedicated test (see BDD/TDD).
- **Public `/login` rate-limiting/anti-enumeration is an open liability, not
  silently accepted.** As stated under Scope, this slice does not add
  throttling beyond what `AuthService.login` already provides (fixed-cost
  hashing on unknown users, identical rejection reason). Before this path is
  advertised to real users, either a follow-up slice must add rate-limiting/
  lockout on the enrollment service's `/login`, or an explicit accepted-risk
  entry must be recorded in `TECHNICAL-DEBT-TRACKER.md`. Filed as
  [DT-009](../TECHNICAL-DEBT-TRACKER.md#dt-009-public-login-on-the-enrollment-service-has-no-rate-limiting-lockout-or-anti-enumeration)
  (Strategic Technical Debt, Security) during the implementation handoff; it
  remains open until a follow-up slice adds the limiter/lockout or the risk is
  permanently accepted with a recorded compensating control.

## BDD/TDD plan (tests to write in the implementation handoff — not written here)

**Godot/GUT — the login-authority loopback seam** (proposed file:
`tests/integration/test_login_loopback_http_endpoint.gd`, alongside the
existing `tests/integration/test_login_gateway_assertions.gd`):

- *Valid credentials → assertion.* Given a registered account and a running
  `LoginLoopbackHttpEndpoint` wired to a real `LoginGateway`, when a raw
  `StreamPeerTCP` client sends a well-formed `POST /internal/verify-and-mint`
  with correct `{username, password}`, then the response is `200` with a
  non-empty `assertion` string that `AssertionValidator` (the game server's
  side) accepts, and the endpoint's `SessionRegistry` holds no session
  afterward (asserting the `clear_session` invariant above). Public seam
  under test: `LoginLoopbackHttpEndpoint.start()`/the raw socket contract, not
  a mocked HTTP layer.
- *Bad credentials → bounded reject, no session left.* Wrong password and
  unknown username each return a non-200 with `{"outcome": "bad_credentials"}`
  (same reason for both — no enumeration), and no session remains bound.
- *Malformed/oversized request → reject, connection does not hang the
  process.* Missing JSON body, wrong `Content-Type`, non-string field,
  oversized body (over the 1 KiB cap), and an unknown top-level key each
  produce a bounded rejection (not a parse exception that crashes the
  endpoint's `_process()` loop) and the listener keeps accepting further
  connections afterward.
- *Loopback-only.* Assert `LoginLoopbackHttpEndpoint` calls
  `TCPServer.listen(port, "127.0.0.1")` literally — never
  `NetworkConfig.resolve_server_bind_address()` — e.g. by asserting the
  resolved bind constant directly, or via a test that confirms no
  environment/CLI override changes the bound address.
- *Synthetic peer-id disjointness.* A real ENet-style positive `peer_id`
  session bound in the same shared `SessionRegistry` is unaffected by a
  concurrent (or sequential) loopback request — the loopback request's
  `clear_session` call never erases the real peer's session. This is the
  regression test for the collision hazard called out under Safety
  invariants.

**Python/pytest — the enrollment `/login` delegation** (proposed files:
`infra/enrollment/tests/test_login_service.py` mirroring `test_service.py`'s
structure, and route coverage added to `test_app.py` or a new
`test_login_app.py`):

- *Happy path.* A fake `LoginAuthorityClient.verify_and_mint()` returns a
  token string; `POST /login {username, password}` returns `200
  {"assertion": "<token>"}`; the fake is called with exactly the submitted
  credentials and nothing else is asserted about the request body reaching
  the fake (i.e., the fake — not a real socket — is the seam, matching the
  existing `OpnsenseWireguardClient` fake pattern in `tests/fakes.py`).
- *Bad-credentials path.* The fake raises the bounded rejection the real
  client would raise on a `bad_credentials` outcome; the route returns `401`
  with a bounded body, never the fake's internal exception text.
- *Upstream-failure path.* The fake raises a connection/timeout error
  (simulating the login process being unreachable or slow); the route returns
  a bounded `502`, and the enrollment service's own logs contain no
  credential material (asserted the same way `test_service.py` already
  asserts `RedeemRejected` never leaks a private key).
- *Malformed request.* Missing/empty `username` or `password` in the request
  body is rejected by Pydantic/FastAPI validation before the fake client is
  even called (asserting the fake's call count is zero).

## Validation plan (commands for the implementation handoff to run)

- **GDScript/GUT, focused first:** run the new
  `tests/integration/test_login_loopback_http_endpoint.gd` script directly
  (narrowest seam) via the project's existing GUT invocation pattern, then the
  full gate: `scripts/run_gut_validation.sh`. Expected pass signal: exit 0,
  with `build/validation/gut.xml` and `build/validation/validation-summary.json`
  showing all scripts green (no reduction in the current 407/407 baseline from
  Slice 087, plus the new script's cases). A parse-only check via `godot
  --headless --check-only -s server/login_loopback_http_endpoint.gd` is the
  cheapest discriminating check before running the suite.
- **Python/pytest:** `python3 -m pytest infra/enrollment/tests -q` (matching
  every prior enrollment-slice validation command verbatim — see Slices 048/049).
  Expected pass signal: all tests pass, exit 0, with no reduction from the
  current 55/55 baseline plus the new login-delegation cases.
- **Record sync:** `scripts/check_record_sync.sh`, expected exit 0.
- **Not run by the original planning handoff:** no build/test command was
  executed to produce the original records-first version of this record. The
  implementation handoff that followed wrote the code and tests below but
  likewise ran none of these commands (see Validation evidence below) — that
  is Copilot's next step.

## Validation evidence

Validated on the canonical Linux host (`192.168.1.254`), in an isolated git
worktree of commit `d732ff6` (Windows cannot run GUT for this repository — the
`addons/godot-sqlite` and `native/wgnetstack` extensions have no
`windows.x86_64` binaries, so only the Linux host is authoritative for the GUT
gate).

- Full GUT gate: `GODOT_BIN=godot bash scripts/run_gut_validation.sh`, run on
  the Linux host. Result: `build/validation/validation-summary.json` status
  `passed`, exit code `0`, `scripts_expected` 62, `scripts_ran` 62; Run Summary
  415 tests, 415 passing, 1511 asserts, 0 failing. Includes the new
  `tests/integration/test_login_loopback_http_endpoint.gd`.
- Python/pytest: `.venv-enrollment/bin/python -m pytest infra/enrollment/tests -q`
  on the Linux host — 70 passed, exit 0. Also reproduced locally on Windows
  (fresh venv, `requirements.txt` + `pytest`) — 70 passed, exit 0.

## ADR link

[ADR 0004 — Auth-gated, on-demand tunnel provisioning](../adr/0004-auth-gated-tunnel-provisioning.md)
(accepted). This slice implements exactly follow-up item (A) from the ADR's
Consequences section; sub-decisions 1 (HTTPS transport, not raw ENet/UDP) and
2 (login authority stays the auth home; enrollment delegates, never
duplicates) are the two decisions this record's design directly executes.
Sub-decisions 3 (peer lifecycle) and 4 (invite path retained) are out of scope
here and belong to Slice 089.

## Record links

- Planning ticket / decision basis: [ADR 0004](../adr/0004-auth-gated-tunnel-provisioning.md).
- Slice registry reservation: [docs/slices/SLICE-REGISTRY.md](SLICE-REGISTRY.md)
  (row 088; 089 and 090 reserved for the rest of the ADR's follow-up sequence).
- Governing feature: [P-024](../FEATURE-LIST.md#p-024-public-game-access-via-opnsense-native-wireguard),
  Phase 13 — Public game access.
- Related prior slices this design reuses without modification: [Slice 059 — Signed session assertion contract, issuer, and validator](059-session-assertions.md),
  [Slice 060 — Assertion-backed session establishment in the login gateway](060-assertion-session-binding.md),
  [Slice 068 — Login runtime extraction + standalone login-server process](068-login-runtime-and-standalone-process.md),
  [Slice 048 — WireGuard invite-code enrollment service](048-wireguard-enrollment-service.md)
  (the injectable-client/Protocol pattern this design mirrors for the new
  `LoginAuthorityClient` seam).

## Root-cause learning

Two defects were caught before merge (per `AGENTS.md`'s root-cause gate),
during Linux-host validation and Copilot review.

**(a) Non-constant const initializer in `login_loopback_http_endpoint.gd`.**

- Symptom: `const HEADER_BODY_SEPARATOR: PackedByteArray =
  PackedByteArray([13,10,13,10])` failed to parse — `Assigned value for
  constant "HEADER_BODY_SEPARATOR" isn't a constant expression`.
- Public seam: `server/login_loopback_http_endpoint.gd` load (script parse).
- Hypothesis: a `PackedByteArray` literal/constructor should be foldable at
  parse time like other typed constants in this codebase.
- Discriminating check: `godot --headless --check-only -s
  server/login_loopback_http_endpoint.gd` — exit 1, reproducing the parse
  error in isolation from the rest of the suite.
- Confirmed root cause: in GDScript 2.0, a `PackedByteArray` constructor call
  is not a compile-time constant expression, so it cannot initialize a
  `const`, unlike literal `int`/`String`/`Array` constants.
- Why existing tests missed it: the initial implementation was never
  parse-checked in isolation before this handoff. On Windows the whole suite
  fails environmentally (missing `addons/godot-sqlite`/`native/wgnetstack`
  native libs), which masked this specific parse failure behind an unrelated
  environmental failure.
- Countermeasure: parse-check new/changed server scripts locally with
  `--check-only` before Linux-host validation, rather than relying on the full
  suite to surface a parse error.
- Regression evidence: `--check-only` now exits 0 for this file, and the full
  Linux-host GUT gate is green (415/415, exit 0). Fix: changed
  `HEADER_BODY_SEPARATOR` from a `const` to an instance
  `var _header_body_separator`.

**(b) Server→client dependency inversion.**

- Symptom: `server/login_loopback_http_endpoint.gd` (server-only) `preload`ed
  `client/network_client.gd` solely to read
  `ASSERTION_REQUEST_TTL_SECONDS`.
- Public seam: `server/login_loopback_http_endpoint.gd`.
- Hypothesis/confirmed root cause: reaching into `client/` from `server/`
  violates this document's server/client boundary (`CLAUDE.md`'s
  Implementation Placement and Shared Contracts rules) — server code must not
  depend on client-owned files, even for a shared numeric constant.
- Why existing tests missed it: the preload compiles and runs correctly, so no
  test failure flags it; this is an architecture-review finding, not a
  runtime or parse failure, and was caught in Copilot review rather than by
  GUT/pytest.
- Countermeasure: `server/` code must not `preload`/reference `client/`
  scripts; a server-owned tuning constant must live server-side even when its
  value happens to match an existing client-side constant.
- Fix: replaced the `client/network_client.gd` preload with a local `const
  ASSERTION_TTL_SECONDS: int = 300` in
  `server/login_loopback_http_endpoint.gd`.
- Regression evidence: full Linux-host GUT gate green (415/415, exit 0) with
  no `server/` → `client/` reference remaining in this file.

## Non-goals (restated for scan-ability)

- No peer provisioning / `/redeem` changes (Slice 089).
- No launcher/client flow changes (Slice 090).
- No rate-limiting/lockout/anti-enumeration implementation on the public
  `/login` (named liability, not silently deferred — filed as
  [DT-009](../TECHNICAL-DEBT-TRACKER.md#dt-009-public-login-on-the-enrollment-service-has-no-rate-limiting-lockout-or-anti-enumeration);
  see Safety invariants).
- No live network commands, deployment changes, or config file edits on
  `192.168.1.254` — this slice's own validation is local/headless only; live
  deployment evidence is a later handoff.
