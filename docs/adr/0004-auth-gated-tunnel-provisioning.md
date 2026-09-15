---
status: accepted
---

# Auth-gated, on-demand tunnel provisioning

Replace invite-code key delivery with self-service login: a player authenticates
over public HTTPS before any tunnel exists, and a successful login both
provisions their WireGuard peer on demand and hands the same signed session
assertion to the in-tunnel game server, eliminating the third-device invite step
and the login-over-tunnel failure it currently causes.

## Context

Remote onboarding today requires an operator to mint a single-use WireGuard
invite code on the server (`infra/enrollment/cli.py` `mint-invite`) and deliver
it out-of-band to the player, who pastes it into the Windows launcher. This
third-device key delivery is not a functional self-service onboarding path.

After the Slice 084/085 login-split cutover, the game server
(`server/server_main.gd`, UDP 9999) is assertion-only: it builds no
`AuthService` and refuses register/login/Character-CRUD with
`account_authority_disabled` (`server/login_gateway.gd`). Accounts live only on
the standalone login server (UDP 9998, `server/login_server_main.gd`), which
mints signed HMAC session assertions (Slices 059/060) that the game server
already knows how to accept via `establish_session_from_assertion`.

The Windows tunnel is a single-destination userspace-WireGuard UDP proxy:
`native/wgnetstack/bridge/bridge.go` dials one `game_host`
(`tnet.DialUDPAddrPort` against `cfg.GameHost`), and
`native/windows_launcher/main.go` hardcodes
`PROJECT0_TUNNEL_GAME_HOST=<assigned_ip>:9999`. `client/network_client.gd`
overrides the connect port with the single tunnel loopback port. An in-tunnel
client can therefore only ever reach 9999, never 9998 — remote login currently
fails with `account_authority_disabled` because the login server is
unreachable through the tunnel at all. This ADR is triggered by needing a
remote onboarding path that both removes the invite-delivery step and closes
that reachability gap.

## Decision

Move authentication in front of the tunnel. The sequence becomes: HTTPS login
(no tunnel yet) → signed assertion issued → client provisions its WireGuard
peer using that assertion → tunnel comes up → client presents the same
assertion to the assertion-only game server inside the tunnel via
`establish_session_from_assertion`. No invite code is minted or delivered for
this path, and the login port (9998) never needs to be reachable through the
tunnel, since the assertion — not a live connection to the login server — is
what crosses the tunnel boundary.

Four sub-decisions:

1. **Public pre-tunnel login transport is HTTPS, not raw ENet/UDP.** The
   player's credential exchange extends the existing Cloudflare-fronted
   enrollment service (`infra/enrollment/`, currently `app.py` /
   `service.py`), not the Godot login server's ENet/UDP protocol. Rationale:
   TLS termination, WAF, and rate-limiting are already provided by Cloudflare
   in front of the enrollment service. Opening the raw Godot ENet login port
   (UDP 9998) to the public Internet would expose a far larger DDoS and
   unauthenticated-packet surface with none of those protections, and would
   duplicate transport-security work the enrollment service already gets for
   free.

2. **Auth home stays the login authority; the enrollment service delegates,
   it does not duplicate.** The enrollment HTTPS service verifies credentials
   by calling into the existing login authority (the service that owns the
   accounts database and already mints the signed HMAC assertion per Slices
   059/060), rather than reading or writing the accounts store directly. The
   rejected alternative is giving the enrollment service its own copy of, or
   direct query access to, the accounts store. That alternative was rejected
   because it creates two systems capable of authenticating a player against
   diverging credential state, and duplicates password-verification and
   credential-storage logic that must otherwise only ever live in one place.
   Delegation keeps the login authority as the single source of truth for
   "is this account/credential pair valid," with the enrollment service acting
   as a public-facing caller of that authority, not a second implementation
   of it.

3. **Peer lifecycle: gate `/redeem` on an assertion, and make provisioning
   idempotent and aging.** `POST /redeem` (`infra/enrollment/service.py`,
   `EnrollmentService.redeem`) currently accepts an `invite_code`, looks it up
   via `self._store.get_invite`, and allocates one address per successful
   redeem. For the auth-gated path, `/redeem` (or a parallel endpoint reusing
   the same peer-allocation path) MUST instead accept and verify a signed
   session assertion in place of the invite code. Because a player may log in
   from the same account repeatedly, peer provisioning for this path MUST be
   idempotent per account: a re-login for an account that already has a live,
   unexpired peer MUST return that existing peer configuration rather than
   allocating a new `/24` address. Peers provisioned this way MUST also age
   out — a peer left idle past a bounded threshold, or belonging to a session
   whose assertion has expired, MUST become eligible for deprovisioning and
   address reclamation. Without idempotency and aging, this path exhausts the
   enrollment service's `/24` address pool the way unlimited invite minting
   would.

4. **The invite-code path is retained, not replaced.** Invite-code
   mint/redeem (`infra/enrollment/cli.py` `mint-invite`, the existing
   `EnrollmentService.redeem` invite branch) remains in the codebase as an
   admin and fallback onboarding path, and as the mechanism the ban/revocation
   lifecycle (Slice 049) already depends on. This ADR adds a second,
   self-service entry point; it does not remove or deprecate the first.

## Consequences

- Becomes possible/easier: self-service remote onboarding (username + password,
  click Connect) with no third-device invite-code delivery step; the
  login-over-tunnel `account_authority_disabled` failure is fixed as a side
  effect, since the login port no longer needs to be tunneled at all for this
  path.
- Harder/riskier/given up: the enrollment service now exposes a public
  authentication surface (credentials over HTTPS) and MUST carry
  rate-limiting, lockout, and anti-enumeration protections it did not
  previously need as an invite-only redeemer; on-demand per-account peer
  provisioning adds idempotency and aging/deprovisioning complexity that flat
  invite-redeem allocation did not have; the enrollment service gains a
  runtime dependency on the login authority being reachable, where previously
  it was self-contained against its own invite store.
- Follow-up work (a proposed slice sequence; slice numbers are NOT reserved by
  this ADR — allocate from `docs/slices/SLICE-REGISTRY.md` starting at the
  next free number, 088, only after this ADR is accepted):
  - (A) HTTPS `/login` on the enrollment service that delegates credential
    verification to the login authority and returns a signed session
    assertion.
  - (B) `/redeem` accepts a signed assertion as an alternative to
    `invite_code`, with idempotent per-account peer lifecycle and
    aging/deprovisioning.
  - (C) launcher/client flow change: login → redeem (assertion-gated) →
    tunnel up → present the same assertion to the game server via
    `establish_session_from_assertion`.
