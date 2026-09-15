# Slice 091 — Auth-gated onboarding C-client-seam: Godot `EnrollmentHttpClient`

Status: **delivered**

Tracker context: Phase 13 — Public game access; advances
[P-024](../FEATURE-LIST.md#p-024-public-game-access-via-opnsense-native-wireguard)
per [ADR 0005](../adr/0005-character-selection-over-https.md) (Option A). The
client-consumer seam of the HTTPS character surface; the UI-scene rewiring +
live tunnel handoff that consumes it is the runtime-validated follow-up
(Slice 093). Implemented directly by Copilot with the user's explicit
authorization.

## User outcome

The Godot client can perform the entire pre-tunnel account-and-character flow
over public HTTPS — log in, list/create/select/delete characters, and receive
the signed **character** assertion world entry needs — through one bounded,
fail-closed client seam, without any ENet reach to the login server (9998).

## Problem

ADR 0005 (Option A) put character selection on the public HTTPS enrollment
surface (Slices 088/090). The Godot client needs a client-side consumer of
those routes (`/login`, `/characters/*`) using `HTTPRequest`, replacing the
ENet character RPCs for the tunnelled flow. This slice delivers that seam as a
deep, fully-tested module; wiring it into the login/character **scenes** and
the tunnel handoff (which needs a real Windows client run to validate) is
Slice 093.

## Scope and non-goals

**In scope:** `client/enrollment_http_client.gd` (`EnrollmentHttpClient`) — a
`Node` wrapping one `HTTPRequest` with coroutine methods `login`,
`list_characters`, `create_character`, `select_character`, `delete_character`,
plus a static `resolve_base_url()` (`PROJECT0_ENROLLMENT_URL`, default
`https://enroll.valentin.vip`). Each returns a bounded, typed result Dictionary
and never raises. GUT coverage against the existing fake HTTP server fixture.

**Non-goals:** wiring `client/account_gate.gd` / `client/character_gate.gd` to
this seam, the tunnel-then-present sequence, and any scene/UI change (all
Slice 093, runtime-validated); the launcher (Slice 092); TLS pinning; ret/
rate-limiting.

## Public seam

`client/enrollment_http_client.gd`: `login/list_characters/create_character/
select_character/delete_character` (coroutines returning `{"outcome": ...}`),
`resolve_base_url()`, and the bounded `OUTCOME_*` constants. Mirrors
`shared/local_llm_client.gd`'s `HTTPRequest` + `await request_completed` pattern.

## Safety invariants

- **Fail-closed, bounded outcomes.** A non-2xx → `http_error` (carrying the
  parsed error body when present), a timeout → `timeout`, any other transport
  failure → `transport_error`, a non-JSON body → `malformed`; only a 2xx JSON
  object with the expected typed field is `ok`. No method raises.
- **Client boundary.** Talks only to the public HTTPS surface; never the
  loopback endpoint or the ENet login server. `HTTPRequest` validates server
  certificates by default (Godot 4.3).
- **One request at a time.** Godot's single child `HTTPRequest` runs one
  request at a time; every method awaits completion before returning, so the
  caller sequences calls naturally.

## BDD/TDD

`tests/integration/test_enrollment_http_client.gd` (fake-HTTP-server-backed):
login→assertion; non-2xx→`http_error`; list→array; create→character;
select→character assertion; delete→ok; non-JSON→`malformed`; unreachable
server→`transport_error`; `resolve_base_url` env/trim/default.

## Validation

`scripts/run_gut_validation.sh` on the Linux host.

## Validation evidence

- **GUT full suite** on the Linux host (192.168.1.254), isolated git worktree
  of the slice commit, `GODOT_BIN=godot bash scripts/run_gut_validation.sh`:
  status `passed`, exit 0, scripts 63/63, **432 tests passing** (up from Slice
  090's 423 — +9 `test_enrollment_http_client.gd` cases). _(filled from the
  host run.)_

## Root-cause learning

No unexpected failure. The seam has no native-lib dependency, so it parse-checks
and (unlike the DB-backed suites) runs on Windows too; the authoritative gate
remained the Linux host full-suite run.

## ADR link

[ADR 0005](../adr/0005-character-selection-over-https.md) (Option A).

## Record links

- [SLICE-REGISTRY.md](SLICE-REGISTRY.md) (091; 092 launcher, 093 client wiring).
- Consumes the routes delivered by [Slice 088](088-auth-gated-onboarding-login-delegation.md)
  and [Slice 090](090-https-character-endpoints.md).
- Pattern reused: `shared/local_llm_client.gd` (`HTTPRequest` + await),
  `scripts/fake_ollama_http_server.gd` (test fixture).
