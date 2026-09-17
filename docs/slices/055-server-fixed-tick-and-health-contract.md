# Slice 055 — Server fixed-tick and health snapshot contract
GitHub issue: #95

Status: **delivered**

Phase: 10 (Authoritative runtime and action input), advancing
[P-014](../FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime).
First implementation slice of the
[container-platform map](../../.scratch/container-platform/map.md); it delivers
the bounded fixed-tick and machine-readable health contract the
[runtime-boundary decision](../../.scratch/container-platform/issues/01-runtime-boundary-and-container-adapter.md)
requires before the game server is containerized.

## User outcome

The authoritative server has a bounded, versioned health snapshot and an
explicit, bounded simulation tick rate that the future container image and
operator control plane can read, without changing any current gameplay
behavior.

## Scope and non-goals

In scope: a pure, server-only `ServerHealth` contract that resolves a bounded
tick rate (20–30 Hz, default 30) from configuration and builds a bounded,
versioned health snapshot from explicit inputs, with fail-closed validation.

Out of scope (later slices): setting `Engine.physics_ticks_per_second` on the
running server, writing the health snapshot to a file or endpoint, the
container image, the operator control plane, and any login/persistence split.
This slice deliberately delivers the contract only, mirroring how Slice 038
delivered the SQLite engine seam before any consumer — so no current runtime
behavior changes.

## Public seam

`server/server_health.gd` (`class_name ServerHealth`), pure and static:

- `resolve_tick_rate(raw: String) -> int` — returns the default tick rate for
  empty/invalid input, otherwise clamps the parsed integer to the bounded
  20–30 Hz range.
- `build_snapshot(inputs: Dictionary) -> Dictionary` — validates the input
  fields and returns `{ "outcome": "ok", "snapshot": {...} }` or a bounded
  `{ "outcome": "invalid", "detail": String }`. The snapshot carries a
  `snapshot_schema_version`, status, tick rate, uptime, server tick, connected
  and max peers, application schema version, and a caller-supplied timestamp
  (never read from the clock, so the contract stays pure and testable).

Server-only per CLAUDE.md: `shared/` and `client/` never reference it.

## Safety invariant

The contract is fail-closed and side-effect-free: an out-of-range status, tick
rate, peer count, or non-finite/negative number is rejected with a bounded
reason and no snapshot. It reads no clock, file, socket, or global state.

## ADR rationale

No new ADR. The bounded 20–30 Hz tick and server-owned health output are
already normative in `CLAUDE.md` (Runtime Ownership) and were accepted in the
container-platform runtime-boundary decision.

## BDD / TDD

`tests/unit/test_server_health.gd` (written first) covers tick-rate default,
below/above clamp, and valid pass-through; snapshot happy path and schema
version; and rejection of bad status, out-of-range tick, negative/non-finite
uptime, and connected-peers exceeding max-peers.

## Validation

Focused: `godot --headless --path . -s addons/gut/gut_cmdln.gd
-gdir=res://tests/unit -gtest=test_server_health -gdisable_colors -gexit`.
Full gate: `scripts/run_gut_validation.sh` (exit 0) and
`scripts/check_record_sync.sh` (exit 0). Evidence recorded on completion.

Windows-workstation result (2026-09-14): the unit directory ran 215 tests,
210 passing. All 11 new `test_server_health` cases pass. The 5 failures are
pre-existing and environment-specific in files this slice does not touch
(`tests/unit/test_lan_config.gd::test_server_fails_closed_on_unbindable_address`
spawns a real Godot subprocess and binds a socket via `OS.execute`;
`tests/unit/test_local_llm_client_config.gd`'s env-override cases depend on
`OS.set_environment`). This change is purely additive (git shows only new
`server/server_health.gd`, `tests/unit/test_server_health.gd`, this record, and
the registry row), so it cannot cause failures in those unrelated socket/env
tests.

Authoritative result on the Linux host `192.168.1.254` (`okami`, 2026-09-14),
run in an isolated `git worktree` of branch `slice/055-server-fixed-tick-health`
so the live server checkout was untouched: `scripts/run_gut_validation.sh`
passed **326/326 tests across 45/45 scripts** (`scripts_expected == scripts_ran
== 45`), status `passed`, exit 0; `test_server_health` passed;
`scripts/check_record_sync.sh` reported 0 errors and 6 pre-existing warnings,
exit 0. This confirms the Windows-only failures are environment-specific and the
slice is green on the authoritative gate.

## Root-cause learning

Process-spawning and `OS.set_environment` unit tests are environment-sensitive
and are not reliable on the Windows workstation; the authoritative GUT gate is
the Linux host per AGENTS.md. A Windows-local run is a useful smoke check for a
pure, additive contract module but is not the delivery gate for a slice.
