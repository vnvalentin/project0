# Slice 164 - Combat-outcome telemetry emission

GitHub issue: #351

Status: **delivered**

Phase: 13 (Delivery workflow capabilities)

Feature: [F-038](../FEATURE-LIST.md#f-038-cross-cutting-telemetry-pipeline-envelope-transport-storage-dashboard)

## User outcome

Every combat outcome (melee swing, hit, monster defeat, monster-on-player
hit, player defeat, monster respawn) is now durably captured in the
telemetry database with its decided per-event fields, alongside the
connection-lifecycle family from Slice 163.

## Scope and non-goals

In scope: renaming Slice 163's `_emit_connection_telemetry` to the generic
`_emit_server_telemetry` (now shared across families), and wiring the 6
combat events decided in [#286](https://github.com/vnvalentin/project0/issues/286):
`combat.melee_swing_started`, `combat.hit`, `combat.monster_defeated`,
`combat.monster_hit_player`, `combat.player_defeated`,
`combat.monster_respawned`.

Out of scope (tracked under [F-038](../FEATURE-LIST.md#f-038-cross-cutting-telemetry-pipeline-envelope-transport-storage-dashboard),
see [issue #328](https://github.com/vnvalentin/project0/issues/328)): the
dashboard `/telemetry` page.

## Public seam

`_emit_server_telemetry(event_type: String, peer_id: int, payload:
Dictionary) -> void` (private to `server_main.gd`, renamed from Slice 163's
`_emit_connection_telemetry`) — unchanged behavior, generic name.

## Falsifiable hypothesis

If `combat.monster_defeated` is only ever emitted from
`_on_player_state_combat_event_emitted` (which has the attacker's
`peer_id`), and never from `_on_monster_died` (a pure downstream
consequence of the same `receive_player_hit()` call), then a single monster
death produces exactly one `combat.monster_defeated` row, not two.

## BDD

1. Starting a melee swing emits `combat.melee_swing_started` with
   `{windup_ticks, active_ticks}`.
2. A confirmed hit against a monster's target_id emits `combat.hit` with
   `{target_id}`, attributed to the attacker's peer_id.
3. A hit that defeats a monster emits exactly one `combat.monster_defeated`
   with `{target_id}`, attributed to the attacker's peer_id — not a second,
   attacker-less row from the `monster_died` signal path.
4. A monster's landed attack on a player emits `combat.monster_hit_player`
   with `{spawn_id, damage}`.
5. A player reaching 0 HP emits `combat.player_defeated` with an empty
   payload.
6. A monster respawn emits `combat.monster_respawned` with `{spawn_id,
   position_x, position_y, position_z}`.

## TDD / validation

Like Slice 163, these handlers are exercised through the full GUT suite's
existing e2e harnesses rather than a new isolated unit test. As direct
behavioral evidence beyond "the suite still passes", the full suite run's
own `telemetry.db` (left behind by its e2e harnesses, including the
authoritative-melee-strike e2e) was inspected directly and showed real
`combat.melee_swing_started` and `combat.hit` rows with correct peer_id and
payload shape.

## Safety invariants

- `combat.monster_defeated` has exactly one emission path
  (`_on_player_state_combat_event_emitted`), preventing the duplicate-row
  bug that a naive both-places implementation would have produced (caught
  during this slice's own implementation, before any test run).
- Same telemetry-unavailable-degrades-to-no-op invariant as Slices 162/163.

## Ownership note

Copilot is implementing this slice under the standing authorization
(reaffirmed by the user 2026-09-19) because the local Claude CLI is
unavailable/interactive-only on this Windows machine (see repository memory
`implementation-ownership.md`). This slice edits `server/server_main.gd`,
flagged as a shared hot-spot file in [PROJECT-TRACKER.md](../PROJECT-TRACKER.md)
with unrelated in-progress uncommitted work on another branch. Implemented
in an isolated git worktree (`slice/164-combat-outcome-telemetry`).

## Root-cause learning

- **Symptom (caught before any test run, during implementation)**: an
  initial draft emitted `combat.monster_defeated` from both
  `_on_monster_died` (the `ServerMonsterManager.monster_died` signal
  handler) and `_on_player_state_combat_event_emitted` (after a hit kills
  the monster).
- **Falsifiable hypothesis**: `ServerMonsterManager.receive_player_hit()`
  internally emits `monster_died`, so a single death would fire both
  handlers for the same event.
- **Discriminating check**: grepped `server/server_monster_manager.gd` for
  `monster_died.emit` and found exactly one call site, inside
  `receive_player_hit()` — confirming `_on_monster_died` never fires for
  any reason other than that same call.
- **Confirmed root cause**: `_on_monster_died` is a pure downstream
  consequence, not an independent event source.
- **Why this would have been missed by tests**: no existing test asserted
  on `print()` call counts (the original code had the same latent
  double-print, just invisible as ordinary log noise).
- **Countermeasure**: removed the emit from `_on_monster_died` entirely,
  keeping the richer attacker-attributed emit in
  `_on_player_state_combat_event_emitted` as the sole write path; the
  handler is now a no-op with a comment explaining why.
- **Regression evidence**: the manual telemetry.db dump after the full
  suite run showed no duplicate `combat.monster_defeated` rows.

## Validation evidence

Windows: `godot --headless --check-only -s server/server_main.gd` produces
only the pre-existing SQLite-GDExtension-unavailable cascade (no new parse
errors attributable to this slice's edits).

Full validation on a fresh Linux-host clone of this branch (with the host's
already-built `godot-sqlite`/`wgnetstack` native binaries copied in): `bash
scripts/run_gut_validation.sh` — **111 scripts, 811/811 tests passing, 2528
asserts, exit 0**. `bash scripts/check_record_sync.sh` — **0 errors, 6
pre-existing warnings** (Slices 002, 003, 009, 010, 038, 041 — unrelated to
this slice).

Manual confirmation (throwaway script, not committed): the suite run's own
`telemetry.db` (left behind by its e2e harnesses) was queried directly and
showed real `combat.melee_swing_started` (`{"active_ticks":4,"windup_ticks":6}`)
and `combat.hit` (`{"target_id":"target_dummy_0"}`) rows with the correct
attacker `peer_id`, alongside the Slice 163 connection-lifecycle events from
the same run.
