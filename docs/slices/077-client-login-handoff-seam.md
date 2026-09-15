# Slice 077 — Client login→game handoff seam

Status: **delivered**

Phase: 10 (Authoritative runtime and action input), advancing
[P-014](../FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)
and the [login-boundary decision](../../.scratch/container-platform/issues/02-account-login-service-boundary.md).
Twenty-third delivery of the [container-platform map](../../.scratch/container-platform/map.md);
it moves the login→game handoff out of the test harness into a **production
client seam** on `NetworkClient`, so the login-screen scenes can perform the
cutover by calling one method — validated end-to-end over real ENet.

## User outcome

The client has a single, reusable, bounded operation that takes a
login-authenticated session with a selected Character and completes the cutover:
it obtains a signed assertion, hands off to the game process, and enters the
world — emitting one result signal. This is the production code the login screen
will call (wired in a follow-up), proven now by the multi-process e2e harness.

## Scope and non-goals

In scope:
- `client/network_client.gd`: `perform_login_to_game_handoff(game_host, game_port)`
  — a poll-based, bounded coroutine that requests an assertion, disconnects from
  the login process, connects to the game process, presents the assertion, and
  enters the world; plus `login_to_game_handoff_finished(outcome, world_character)`.
- Refactor `scripts/login_handoff_client_harness.gd` to drive Phase 2 through this
  production seam, so the e2e harness proves the real handoff code.

Out of scope (Slice 078): wiring the account/character gate scenes to connect to
the login endpoint and call this seam (GUI, validated via the UI smoke harness);
flipping `PROJECT0_GAME_ASSERTION_ONLY` on by default; the DB split. This slice
adds and proves the reusable handoff; the scene wiring follows.

## Public seam

- `client/network_client.gd` (`perform_login_to_game_handoff`,
  `login_to_game_handoff_finished`).

## Safety invariant

The handoff drives only existing public seams (`submit_request_assertion`,
`disconnect_from_server`, `connect_to_server`, `submit_present_assertion`,
`submit_enter_world`) and the server owns every outcome; the client never
fabricates a session. Each step is bounded (a dropped reply ends the step with a
terminal outcome rather than hanging), and the one-shot signal captures are
disconnected on timeout so no listener leaks. The assertion token is a
peer-scoped bearer credential held only for the reconnect.

## ADR rationale

No new ADR. This factors the already-proven handoff sequence (Slice 073/075's
harness) into production client code so the UI can reuse it, per the
login-boundary decision.

## BDD / TDD

`scripts/test_login_handoff_e2e.gd` (multi-process) drives the harness, which now
performs Phase 2 via `perform_login_to_game_handoff`; it asserts the client
registers/selects on the login process, then the game process establishes the
session and world entry returns `ok` bound as the expected Character — proving
the production seam over real ENet. The GUT suite is unaffected (the seam is
exercised by the e2e script, not the GUT gate).

## Validation

- Full suite: `scripts/run_gut_validation.sh` on the Linux host — **passed, 56/56
  scripts, exit 0** (unaffected; the seam is exercised by the e2e script).
- Runtime (Linux): `godot --headless --path . -s scripts/test_login_handoff_e2e.gd`
  printed **`ALL PASS`** including `world_entry == ok` bound as `Handoff Hero`,
  now driven through `perform_login_to_game_handoff` over real ENet.
- `scripts/check_record_sync.sh` exit 0 (6 pre-existing WARN).

## Root-cause learning

None yet.
