# Slice 037: World-scale constant relabel (meters → yards)
GitHub issue: #95

Tracker context: Phase 8 — JIT world generation and local inference (completes the
constant-adoption half of the world-scale foundation). Advances
[F-028](../FEATURE-LIST.md#f-028-imperial-world-scale-measurement-contract).
Planning ticket: [World Scale map](../../.scratch/world-scale/map.md) (ticket 04);
decision [ADR 0003](../adr/0003-imperial-world-scale.md).

## SDD

Goal: adopt the Imperial vocabulary fixed by
[Slice 036](036-world-scale-measurement-contract.md) in the existing code — the
world-scale-bearing constants and comments were still labeled "meters" while ADR 0003
anchors 1 world unit = 1 yard. This is a pure, behavior-preserving **relabel**:
identifiers and comments change, magnitudes do not.

Public seam (renames; values unchanged):

- `shared/monster_contracts.gd` — `DETECTION_RADIUS_METERS` → `DETECTION_RADIUS_YARDS`
  (8.0), `CHASE_SPEED_METERS_PER_SEC` → `CHASE_SPEED_YARDS_PER_SEC` (3.0),
  `MONSTER_REACH_METERS` → `MONSTER_REACH_YARDS` (2.0).
- `shared/combat_contracts.gd` — `MeleeWeaponArchetype.reach_meters` → `reach_yards`
  (field, `_init` param, and the `is_within_reach_and_arc()` usage); Generic Sword = 2.0.
- `server/server_monster_manager.gd` — `RESPAWN_AREA_RADIUS_METERS` →
  `RESPAWN_AREA_RADIUS_YARDS` (2.0).
- `server/server_monster_state.gd`, `client/melee_strike_visual.gd` — updated to the
  renamed constants/field.
- `shared/network_config.gd`, `client/player.gd` — unit comments relabeled units→yards
  (`AUTHORITATIVE_MOVE_SPEED`, `NETWORKED_PLAYER_SMOOTH_SPEED`,
  `NETWORKED_PLAYER_SNAP_DISTANCE`, `move_speed`); identifiers unchanged (they carry no
  "meters").
- Tests: `tests/unit/test_melee_combat_contracts.gd`,
  `tests/unit/test_server_monster_state.gd` — updated to the renamed field/constant.

Behavior: nothing changes. Every renamed constant keeps its exact value.

Implementation decisions:

- **Relabel, not re-tune** (ADR 0003 / world-scale ticket 04): no magnitude changes.
- **Base magnitudes stay literal**, not `WorldScale`-derived — because 1 unit = 1 yard,
  routing them through the contract is an identity no-op; they carry a doc pointer to
  `shared/world_scale.gd` instead.
- **`default_gravity` and render heights left unchanged** (ticket 04): gravity has no
  vertical mechanic yet, and `_WALL_HEIGHT` / `_FLOOR_CORRIDOR_HEIGHT` are already
  yard-consistent.
- **Historical slice docs (013/021/022) left as point-in-time records**; the live
  FEATURE-LIST IP-023 public-seam listing was updated to the new names.

## BDD

### Behavior is preserved after the relabel

Given the meters→yards rename
When the full test suite runs
Then every existing combat/monster test passes unchanged (same counts), because only
identifiers and comments changed.

## TDD

- No new tests — this is a rename; the existing suite is the regression guard.
  `tests/unit/test_melee_combat_contracts.gd` (reach hit tests) and
  `tests/unit/test_server_monster_state.gd` (detection/chase/reach) exercise the renamed
  symbols and must stay green.

## Validation

- Straggler check: `grep` for `*_METERS` / `reach_meters` across
  `client|server|shared|tests` → no matches (rename complete); the edited files parse
  clean (no language-server errors).
- Full gate: `scripts/run_gut_validation.sh` — **27 scripts, 207/207 tests, 808 asserts,
  exit 0**, unchanged from before the rename (`scripts_expected == scripts_ran == 27`).

## Non-goals (this slice)

- No magnitude/tuning change, no `default_gravity` change, no geometry-height change.
- No rewrite of historical slice docs (013/021/022) or `.scratch` planning records.
- No new `WorldScale` consumers (base magnitudes stay literal).
