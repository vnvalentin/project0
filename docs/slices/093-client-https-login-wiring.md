# Slice 093 — Auth-gated onboarding C-client-wiring: wire account/character gates to HTTPS + tunnel
GitHub issue: #95

Status: **delivered** (unit + suite validated on the Linux host; live WAN
runtime run is user-pending — see Validation evidence)

Tracker context: Phase 11 — Public game access; advances
[P-024](../FEATURE-LIST.md#p-024-public-game-access-via-opnsense-native-wireguard)
per [ADR 0005](../adr/0005-character-selection-over-https.md) (Option A). Consumes
the [Slice 091](091-client-https-auth-character-seam.md) `EnrollmentHttpClient`
seam and the [Slice 088](088-auth-gated-onboarding-login-delegation.md)/[090](090-https-character-endpoints.md)
HTTPS routes. Implemented directly by Copilot with the user's explicit
authorization (Claude CLI rate-limited).

## User outcome

A remote (WAN/tunnel) player can log in, pick or create a character, and enter
the world from the packaged Windows client — instead of hitting
`Login failed (account_authority_disabled)`, which is what the pre-093 client
produced because it authenticated with ENet register/login RPCs directly
against the assertion-only game server (game server holds no accounts authority
since [Slice 085](085-remove-game-in-process-login.md)).

## Problem

Slice 091 delivered the client HTTP consumer seam but left the login/character
**scenes** still driving the ENet account/character RPCs. Under the tunnel the
client can only reach the game server (9999), which rejects those RPCs with
`account_authority_disabled`. The gates need to run the pre-tunnel HTTPS flow
(log in → list/select/create → obtain a signed **character** assertion), then
bring up the tunnel and present that assertion to the game server for world
entry via the existing `establish_session_from_assertion` path (Slices
074/075/077).

## Scope and non-goals

**In scope:**

- `shared/network_config.gd`: `client_https_login_enabled()` gate
  (`PROJECT0_CLIENT_HTTPS_LOGIN` forces on `"1"`/off `"0"`; unset defaults to
  tunnel mode `PROJECT0_TUNNEL="1"`), so the WAN launcher enables it implicitly
  while LAN dev keeps the ENet path.
- `client/account_gate.gd`: HTTPS login via `EnrollmentHttpClient`; stores the
  account assertion on `PlayerIdentity`; register disabled in WAN mode.
- `client/character_gate.gd`: HTTPS list/create/select/delete; on select,
  obtains the character assertion and enters the world through the tunnel.
- `client/network_client.gd`: `perform_https_world_entry(host, port, character_assertion)`
  — connect (tunnel) → present assertion → enter world, reusing the existing
  bounded `_handoff_*` steps and the `login_to_game_handoff_finished` signal.
- `client/player_identity.gd`: in-memory `account_assertion` / `character_assertion`.
- `tests/unit/test_network_config_https_login.gd`.

**Non-goals:** the launcher (Slice 092); a public HTTPS **registration** surface
(none exists — register is disabled in WAN mode, tracked as
[DT-010](../TECHNICAL-DEBT-TRACKER.md#dt-010-no-public-https-account-registration-surface-for-the-wan-client));
TLS pinning; rate-limiting ([DT-009](../TECHNICAL-DEBT-TRACKER.md#dt-009-public-login-on-the-enrollment-service-has-no-rate-limiting-lockout-or-anti-enumeration));
any server/enrollment change; the ENet LAN path (unchanged).

## Public seams

- `shared/network_config.gd::client_https_login_enabled()`.
- `client/network_client.gd::perform_https_world_entry()`.
- `client/account_gate.gd` / `client/character_gate.gd` scene controllers.

## Safety invariants

- **Server owns every outcome.** The client only carries assertions; the game
  server validates the character assertion (`establish_session_from_assertion`)
  and binds the Player. A tampered/expired assertion binds nothing.
- **Fail-closed UI.** Every HTTPS call returns a bounded `EnrollmentHttpClient`
  outcome; failures re-enable the control with a short, input-free status string
  (`_https_failure_reason` never echoes credentials).
- **Two-path, opt-in.** The ENet LAN login/character path is untouched and
  remains the default off-tunnel; the HTTPS path activates only under the gate.
- **No new secrets client-side.** Assertions live in `PlayerIdentity` in memory
  only and are cleared on `clear_session()`.

## BDD/TDD

`tests/unit/test_network_config_https_login.gd`: LAN default (no flag, no
tunnel) → off; tunnel mode → on; `PROJECT0_CLIENT_HTTPS_LOGIN=1` forces on
without tunnel; `=0` forces off despite tunnel. The seam's HTTP outcome mapping
is already covered purely by
`tests/integration/test_enrollment_http_client.gd` (Slice 091); the scene
controllers are thin orchestration over those validated seams, and their live
behavior is the runtime run below.

## Validation

`scripts/run_gut_validation.sh` on the Linux host; live WAN client run by the
user for the runtime path.

## Validation evidence

- **GUT full suite** on the Linux host (192.168.1.254), isolated git worktree of
  commit `230cd06`, `GODOT_BIN=godot bash scripts/run_gut_validation.sh`: status
  `passed`, exit 0, scripts **64/64**, **436 tests passing, 0 failing** (up from
  Slice 091's 432 — +4 `test_network_config_https_login.gd` cases).
- **Local Windows parse checks** of the edited non-autoload scripts passed;
  scene controllers reference autoloads and so only compile in full-project
  context (covered by the Linux suite). The local Windows GUT run cannot host
  the server autoload (no Windows `godot-sqlite` binary), so server-dependent
  tests are validated on Linux only — an environment limitation, not a slice
  regression.
- **Live WAN runtime run is user-pending.** A real Windows client, over the
  tunnel, against the live enrollment service, reaching
  `Server: connected: player spawned`, is the remaining evidence this slice
  needs before its runtime claim is complete. Never claimed here without that
  evidence.

## Root-cause learning

- **Symptom (originating defect):** the packaged WAN client failed both login
  and register with `Login failed (account_authority_disabled)`. Seam:
  `client/account_gate.gd` → ENet `receive_login_request_on_server` →
  `server/login_gateway.gd`. Hypothesis: the deployed client predated the login
  split and still authenticated on the game server. Discriminating check: the
  game server has built an assertion-only login graph with no `AuthService`
  since Slice 085, so `LoginGateway.login` returns
  `REASON_ACCOUNT_AUTHORITY_DISABLED` unconditionally. Confirmed root cause: a
  client/server version mismatch — the reused `0.9.0-split` export authenticates
  over ENet, which the current server refuses by design. Why existing tests
  missed it: unit/integration suites exercise the login **process** gateway
  (authority enabled), never a packaged client against the assertion-only game
  server over a tunnel; there is no automated WAN-client e2e. Countermeasure:
  this slice moves client auth to the HTTPS pre-tunnel flow so the client never
  sends account RPCs to the game server; the gate makes the ENet path LAN-only.
  Regression evidence: 436/436 on the Linux host. Remaining limitation: no
  automated WAN-client e2e — the live run stays a manual gate (and the missing
  public registration surface is [DT-010](../TECHNICAL-DEBT-TRACKER.md#dt-010-no-public-https-account-registration-surface-for-the-wan-client)).

## ADR link

[ADR 0005](../adr/0005-character-selection-over-https.md) (Option A);
[ADR 0004](../adr/0004-auth-gated-tunnel-provisioning.md).

## Record links

- [SLICE-REGISTRY.md](SLICE-REGISTRY.md) (093).
- Consumes [Slice 091](091-client-https-auth-character-seam.md),
  [Slice 088](088-auth-gated-onboarding-login-delegation.md),
  [Slice 090](090-https-character-endpoints.md).
- Debt filed: [DT-010](../TECHNICAL-DEBT-TRACKER.md#dt-010-no-public-https-account-registration-surface-for-the-wan-client).
