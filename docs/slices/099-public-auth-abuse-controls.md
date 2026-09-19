# Slice 099 - Public authentication abuse controls
GitHub issue: #95

Status: **delivered**

Phase: 13 (Public game access), advancing DT-009 under P-024.

## User outcome

Repeated failed public authentication or excessive character-authority requests are bounded and recover automatically, while ordinary login and Character management remain available.

## Scope and non-goals

In scope: a deterministic, in-memory public-auth abuse policy at the enrollment FastAPI boundary; coverage for `POST /login` and every `POST /characters/*` route; configuration through bounded environment values; focused pytest coverage and synchronized records.

Out of scope: account registration (DT-010), credential or assertion verification, launcher/client changes, OPNsense changes, distributed rate-limit storage, and Phase 10 gameplay work.

## Public seam

`infra/enrollment/app.py::create_app` and the public `/login` and `/characters/*` routes. The policy receives only a bounded route key, source host, and injected clock; it never receives or logs credentials or assertion values.

## Safety invariants

- Login authority and assertion authority remain in the login process.
- Rejected requests return bounded `429` detail `public_auth_rate_limited`; no exception text or credential material is exposed.
- Failed login attempts are keyed by source host and normalized username; successful login clears that key.
- Character requests are bounded by source host and do not store raw assertions.
- A monotonic injected clock makes expiry deterministic; policy state is process-local and distributed enforcement is explicitly deferred.

## Acceptance scenarios

1. Given a normal login or Character request below the limit, the upstream fake is called and the existing response is returned.
2. Given repeated bad login attempts from one host and username, the configured threshold returns `429` and does not call the login authority while locked.
3. Given the lockout window has expired, the same key can attempt again.
4. Given excessive requests to any Character route, the route returns `429` before the Character authority is called; a different source host remains independent.
5. Given malformed request validation, the authority is not called and the abuse policy does not store credentials or assertion text.

## TDD and validation

Focused commands: `python -m pytest infra/enrollment/tests/test_public_auth_rate_limit.py -q` and `python -m pytest infra/enrollment/tests/test_login_app.py infra/enrollment/tests/test_app_characters.py -q`.

Full command: `python -m pytest infra/enrollment/tests -q`. Expected pass signal is exit 0 with all tests passing. Record-sync is `scripts/check_record_sync.sh` on the Linux host.

## Validation evidence

- `python -m pytest infra/enrollment/tests/test_public_auth_rate_limit.py -q` — **7 passed**, exit 0.
- `python -m pytest infra/enrollment/tests -q` — **119 passed**, exit 0. Only the existing Starlette `anyio.abc.BlockingPortal` deprecation warning was emitted.
- The focused suite caught and drove a recovery fix: expired lockouts now clear stale threshold events before allowing a new attempt.

## Review outcome

Delivered. The limiter is injectable, stores only bounded route keys and
timestamps, preserves the login/character authority boundaries, and returns a
bounded 429 response before calling the upstream client when limited.

## Root-cause learning

The first edit attempt left `app.py` partially updated while the newly created module, tests, and slice record were not durable because the active alternate terminal intercepted the edit session. The discriminating check was the clean VS Code task runner, which reported the focused test file missing. The countermeasure was to restore the missing files explicitly and rerun through the task runner before claiming completion. The focused suite then exposed stale failure events surviving lockout expiry; clearing the key's events on expiry fixed the root cause and the 7-test focused suite passed.

## Record links

- Debt: [DT-009](../TECHNICAL-DEBT-TRACKER.md#dt-009-public-login-on-the-enrollment-service-has-no-rate-limiting-lockout-or-anti-enumeration)
- Feature: [P-024](../FEATURE-LIST.md#p-024-public-game-access-via-opnsense-native-wireguard)
- Registry: [SLICE-REGISTRY.md](SLICE-REGISTRY.md), reservation 099
