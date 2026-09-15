# Slice 090 — Auth-gated onboarding C-server: HTTPS character endpoints (loopback-delegated)

Status: **delivered**

Tracker context: Phase 13 — Public game access; advances
[P-024](../FEATURE-LIST.md#p-024-public-game-access-via-opnsense-native-wireguard)
per [ADR 0004](../adr/0004-auth-gated-tunnel-provisioning.md) and
[ADR 0005](../adr/0005-character-selection-over-https.md) (Option A). Server-only
first slice of the Option-A arc; 091 (Godot client cutover) and 092 (launcher)
follow. Implemented directly by Copilot with the user's explicit authorization
while Claude CLI was at its session limit.

## User outcome

A player who holds a signed **account** assertion (from Slice 088's `/login`) can
list, create, delete, and select characters over the **public HTTPS** enrollment
surface — and a successful select returns a signed **character** assertion, the
token world entry needs — without any ENet reach to the login server (9998). This
is the server half of making character selection work in the tunnelled flow; the
Godot client consumes it in Slice 091.

## Problem

World entry binds a Player from a signed **character** assertion (Slices 074/075),
but character CRUD/selection and character-assertion minting live on the login
authority, reachable only over ENet on 9998 — which the single-destination tunnel
does not forward. Per ADR 0005 (Option A), character selection moves onto the
public HTTPS enrollment surface, loopback-delegated to the login authority so the
`PROJECT0_ASSERTION_SECRET` never leaves that process.

## Scope and non-goals

**In scope:**
- Four loopback-only endpoints on `server/login_loopback_http_endpoint.gd`
  (extending the Slice 088/089 listener): `POST /internal/characters/{list,create,
  delete,select}`. Each validates a presented **account** assertion, binds a
  **synthetic negative-peer-id** session via `establish_session_from_assertion`,
  runs the existing `LoginGateway` character op (`list/create/delete/select_character`),
  and — for select — `issue_character_assertion`, then unconditionally
  `clear_session`. No new `LoginGateway`/`CharacterService` methods.
- Enrollment HTTPS routes `POST /characters/{list,create,delete,select}` with an
  injectable `CharacterClient` (`RealCharacterClient` posting to the loopback),
  bounded reason→status mapping, and production wiring
  (`build_production_character_client`, `asgi.py`).

**Non-goals:** the Godot client HTTPS cutover (Slice 091); the launcher (Slice 092);
rate-limiting on the new public surface (widens [DT-009](../TECHNICAL-DEBT-TRACKER.md#dt-009-public-login-on-the-enrollment-service-has-no-rate-limiting-lockout-or-anti-enumeration),
restated not re-opened); any change to the ENet login/character path (retained for
LAN dev).

## Public seam

- Login authority: `server/login_loopback_http_endpoint.gd` — new paths + handlers
  `_handle_char_list/create/delete/select`, `_bind_synthetic_from_assertion`,
  `_extract_assertion`, `_is_character_path`; per-path body cap (`MAX_CHAR_BODY_BYTES`
  = 4096, since a create carries a cosmetic). Reuses `LoginGateway`'s existing
  `list/create/delete/select_character`, `issue_character_assertion`,
  `establish_session_from_assertion`, `clear_session`.
- Enrollment: `infra/enrollment/login_client.py`
  (`CharacterClient`/`RealCharacterClient`/`CharacterAuthorityError`);
  `infra/enrollment/app.py` (routes + `_CHARACTER_REJECTION_STATUS` + builder);
  `infra/enrollment/asgi.py`.

## Safety invariants (security-focused)

- **Account-scoped by the assertion, never a client-supplied `account_id`.** Each
  op runs only after `establish_session_from_assertion` binds the synthetic session
  from the validated account assertion; `CharacterService` derives the account from
  that session, so account A can never touch account B's characters.
- **Loopback-only, secret stays off the enrollment box.** The new paths share the
  Slice 088 `127.0.0.1`-hardcoded listener; `PROJECT0_ASSERTION_SECRET` never
  reaches the Internet-facing enrollment service.
- **Synthetic negative peer id, always cleared.** Real ENet ids are non-negative;
  the per-request negative id is provably disjoint, and every handler
  `clear_session`s win or lose — no synthetic session outlives a request (asserted
  by test).
- **Fail-closed + bounded.** A bad/expired/tampered account assertion → 401; a
  malformed request → 400; domain rejections (name taken, no such character, …) are
  relayed as bounded reason strings and mapped to bounded public statuses; no token
  or secret is logged.

## BDD/TDD

- GUT (`tests/integration/test_login_loopback_http_endpoint.gd`): list→create→select
  end-to-end (select mints a character assertion that independently validates and
  carries the selected `cid`), delete removes a character, a bad account assertion is
  401, and no synthetic session remains bound.
- pytest (`test_character_client.py`, `test_app_characters.py`): the loopback client's
  request shapes and reason mapping (domain reason, assertion-rejected, transport),
  and the four routes' happy paths + status mapping (NAME_TAKEN→409, NO_SUCH_CHARACTER→404,
  bad assertion→401, missing field→422, client-not-wired→503).

## Validation

- GUT: `scripts/run_gut_validation.sh` on the Linux host (Windows lacks the native
  libs). Enrollment: `python -m pytest infra/enrollment/tests -q`.

## Validation evidence

- **GUT full suite** on the Linux host (192.168.1.254), isolated git worktree of
  commit `362387f`, `GODOT_BIN=godot bash scripts/run_gut_validation.sh`:
  `validation-summary.json` status `passed`, exit 0, scripts 62/62, **423 tests
  passing, 1595 asserts, 0 failing** (up from Slice 089's 420 — +3 character-flow
  cases in `tests/integration/test_login_loopback_http_endpoint.gd`).
- **Enrollment pytest** on the host `.venv-enrollment`: **112 passed, exit 0** (up
  from 96 — +16 character-client/route cases). Reproduced on Windows: 112 passed,
  exit 0.
- **Parse check** (Windows): `godot --headless --check-only -s
  server/login_loopback_http_endpoint.gd` exit 0.

## Root-cause learning

No unexpected runtime failure occurred. The slice reused the Slice 088/089
synthetic-negative-peer-id + loopback-dispatch pattern wholesale, so the only
new server-side risk (a non-constant `const` or a boundary violation, the two
defects Slice 088 caught) was pre-empted by a `godot --headless --check-only`
parse check before the host run (exit 0). The `LoginGateway` already exposed
every character op and `issue_character_assertion`, so no new account/character
authority code was written on the login authority — the slice is purely new
loopback *paths* + HTTPS routes, which is why the diff is small relative to its
scope.

## ADR link

[ADR 0004](../adr/0004-auth-gated-tunnel-provisioning.md) and
[ADR 0005](../adr/0005-character-selection-over-https.md) (Option A).

## Record links

- [SLICE-REGISTRY.md](SLICE-REGISTRY.md) (090; 091/092 reserved).
- Sibling loopback slices reused: [088](088-auth-gated-onboarding-login-delegation.md),
  [089](089-auth-gated-onboarding-peer-provisioning.md).
- [DT-009](../TECHNICAL-DEBT-TRACKER.md#dt-009-public-login-on-the-enrollment-service-has-no-rate-limiting-lockout-or-anti-enumeration) (restated).
