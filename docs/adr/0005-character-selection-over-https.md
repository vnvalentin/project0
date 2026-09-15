---
status: accepted
---

# Character selection over HTTPS, client-consumed

Character listing/creation/deletion/selection and character-assertion minting are
exposed over the public HTTPS enrollment surface, loopback-delegated to the login
authority (the same pattern as ADR 0004 Slices 088/089). The Godot client consumes
these HTTPS endpoints directly for the whole pre-tunnel account-and-character flow,
obtains a signed **character** assertion, then brings up the tunnel and presents
that assertion to the game server — so the ENet login server (9998) is never reached
through the tunnel.

## Context

ADR 0004 moved authentication in front of the tunnel: a player logs in over public
HTTPS, receives a signed assertion, provisions a WireGuard peer, brings up the
tunnel, and presents the assertion to the assertion-only game server. Slices 088 and
089 delivered the `/login` and assertion-gated `/redeem` halves.

But world entry needs more than an *account* assertion. Since Slice 085 the game
server (UDP 9999) is assertion-only and holds **no** accounts/character database;
Slices 074/075 established that the game binds a Player from a **signed character
snapshot** carried inside a *character* assertion (claims `cid`/`cnm`/`cos`).
Character CRUD, selection, and character-assertion minting all live on the login
authority (`CharacterService` + `LoginGateway`), reachable today only over ENet on
UDP 9998 — which the single-destination tunnel does not forward. So a remote,
tunnelled client cannot list or select a character, and therefore cannot obtain the
character assertion world entry requires. This ADR chooses how character selection
happens in the auth-gated, tunnelled flow. It is triggered by Slice 090 (the
launcher/client flow) and governed by [P-024](../FEATURE-LIST.md#p-024-public-game-access-via-opnsense-native-wireguard).

Three options were weighed: (A) character selection over HTTPS, client-consumed;
(B) account-assertion-only world entry with the game server hosting in-world
character selection; (C) the launcher performs character selection and hands the
client a character assertion.

## Decision

Adopt **Option A**.

- The public HTTPS enrollment surface (`infra/enrollment/`) gains character
  endpoints — list, create, delete, select — and a character-assertion mint,
  each **loopback-delegated** to the login authority
  (`server/login_loopback_http_endpoint.gd` extended with the corresponding
  paths, backed by narrow `LoginGateway` pass-throughs to the existing
  `CharacterService` / `issue_character_assertion`). No accounts/character logic
  or `PROJECT0_ASSERTION_SECRET` moves onto the Internet-facing enrollment box;
  it only relays bounded results, exactly as `/login` and `/redeem` already do.
- Every character call is **account-scoped by the account assertion** minted by
  `/login`: the caller presents that assertion, the enrollment service validates
  it via the loopback `/internal/validate-assertion` seam (Slice 089) to resolve
  the account, and the login authority performs the account-scoped operation.
  The client never supplies an `account_id`.
- The **Godot client** consumes these HTTPS endpoints (via `HTTPRequest`) for the
  full pre-tunnel flow: log in, list/select (or create) a character, obtain a
  signed **character** assertion. It then brings up the tunnel and presents that
  assertion to the game server (9999) through the **existing**
  `establish_session_from_assertion` path — world entry and snapshot binding are
  unchanged (Slices 074/075/077).
- The ENet login/character path (direct 9998) remains for **LAN development**; it
  is not reached over the tunnel and is not removed by this decision.

Rejected alternatives:

- **B (game server hosts character selection).** Rejected: it re-introduces
  accounts/character authority into the assertion-only game process, reversing the
  Slice 084/085 login/game split and undermining the signed-snapshot world-entry
  design (074/075). It would need its own ADR to amend that split and is the
  highest-churn option.
- **C (launcher performs character selection).** Rejected: it needs the *same* new
  HTTPS character endpoints as A but moves the character-selection UX out of the
  Godot client into a plain Win32 launcher flow (worse UX, awkward for multi-character
  accounts and first-time character creation), and adds a launcher→client token hand-off.
  A keeps selection in the game client where the existing `character_gate` UX already lives.

## Consequences

- Becomes possible/easier: one HTTPS auth-and-character path serves both LAN and
  WAN; the game-side world entry (`establish_session_from_assertion` + snapshot
  binding) is reused unchanged; the signing secret stays confined to the login
  authority; the tunnel carries only game traffic (9999) and the login server never
  needs tunnel or public exposure.
- Becomes harder/riskier/given up: a new **public HTTPS character-CRUD surface**
  must enforce account-scoped authorization on every call (via the presented account
  assertion) and inherits the rate-limiting/anti-enumeration concern already tracked
  as [DT-009](../TECHNICAL-DEBT-TRACKER.md#dt-009-public-login-on-the-enrollment-service-has-no-rate-limiting-lockout-or-anti-enumeration)
  (its scope widens from `/login` to the character endpoints); the Godot client gains
  an `HTTPRequest`-based client path that replaces its ENet character RPCs for the
  tunnelled flow (the ENet path stays for LAN dev, a deliberate two-path cost).
- Follow-up work (allocated from [SLICE-REGISTRY.md](../slices/SLICE-REGISTRY.md);
  090 re-scoped and 091/092 reserved):
  - **090** — HTTPS character endpoints on the enrollment service (list/create/
    delete/select + issue-character-assertion), each loopback-delegated and
    account-scoped by the account assertion. Server-only; does not touch the
    launcher.
  - **091** — Godot client HTTPS cutover: log in, list/select/create a character,
    obtain the character assertion, bring up the tunnel, present it to the game
    server. Client-only.
  - **092** — Windows launcher: login + `redeem`-with-assertion + tunnel bring-up
    (coordinated with the in-flight `native/windows_launcher/` work).
