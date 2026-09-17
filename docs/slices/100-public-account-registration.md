# Slice 100 - Public HTTPS account registration
GitHub issue: #95

Status: **delivered**

Phase: 13 (Public game access), advancing DT-010 under P-024.

## User outcome

A new remote player can create an Account over the protected public HTTPS enrollment path, then use the existing login and Character flow.

## Scope and non-goals

In scope: loopback-delegated account registration, public enrollment `POST /register`, the Godot `EnrollmentHttpClient.register` seam, and WAN account-screen wiring. The route inherits Slice 099 abuse controls.

Out of scope: launcher changes, OPNsense changes, password recovery, CAPTCHA, distributed rate limiting, and Phase 10 work.

## Safety invariants

- The enrollment service never owns credentials or PBKDF2 logic; registration delegates to the login authority.
- The loopback listener remains bound to `127.0.0.1` and uses a synthetic negative peer id that is always cleared.
- Username-taken and malformed outcomes are bounded and never expose credential material.
- Registration is rate-limited by the existing public-auth limiter before authority delegation.

## Validation evidence

- Focused registration/login pytest: `python -m pytest infra/enrollment/tests/test_register_app.py infra/enrollment/tests/test_login_app.py -q` — **8 passed**, exit 0.
- Full enrollment suite: `python -m pytest infra/enrollment/tests -q` — **120 passed**, exit 0. Only the existing Starlette deprecation warning was emitted.
- `godot --headless --check-only -s server/login_loopback_http_endpoint.gd` — no GDScript parse error; Windows emitted the known missing Linux-only GDExtension warnings.
- `godot --headless --check-only -s client/enrollment_http_client.gd` — no GDScript parse error; same known extension warnings.

## Review outcome

Delivered. Registration delegates through the existing login authority, inherits
the public-auth limiter, keeps the loopback listener private, and reuses the
existing account screen login flow after a successful registration.

## Record links

- Debt: [DT-010](../TECHNICAL-DEBT-TRACKER.md#dt-010-no-public-https-account-registration-surface-for-the-wan-client)
- Feature: [P-024](../FEATURE-LIST.md#p-024-public-game-access-via-opnsense-native-wireguard)
- Registry: [SLICE-REGISTRY.md](SLICE-REGISTRY.md), reservation 100
