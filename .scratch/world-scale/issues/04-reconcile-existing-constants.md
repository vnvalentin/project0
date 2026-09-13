Type: grilling
Status: resolved
Blocked by: 02, 03

## Question

Decide the reconciliation policy that points existing magnitudes at the new scale
contract **without changing gameplay feel** (scope boundary: relabel, don't retune).

Sub-questions to resolve here:

- `shared/monster_contracts.gd`: rename `DETECTION_RADIUS_METERS` /
  `CHASE_SPEED_METERS_PER_SEC` / `MONSTER_REACH_METERS` → `*_YARDS`, same magnitudes.
  Do they stay literals or become contract-derived?
- `shared/network_config.gd`: `AUTHORITATIVE_MOVE_SPEED = 5.0`,
  `NETWORKED_PLAYER_SMOOTH_SPEED`, `NETWORKED_PLAYER_SNAP_DISTANCE` — relabel to
  yards/s and yards; reference the contract from ticket 03?
- Physics defaults (per ticket 02's findings): does ProjectSettings `default_gravity`
  get adjusted for the yard anchor, or left as-is with a recorded rationale?
- Confirm each change is a pure relabel / rehome — no magnitude is re-tuned in this
  effort — and enumerate the exact constants + files a downstream slice will touch.

## Answer

Grilled 2026-09-13; all four recommendations accepted. Decision = **relabel-only
reconciliation** (rename meters→yards, magnitudes unchanged); the edits themselves are a
downstream slice (plan-not-do).

- **Q1 — Rename all** meters→yards for one vocabulary, values unchanged.
- **Q2 — Base magnitudes stay literal** (no `WorldScale`-derived): 1 unit = 1 yard makes
  any conversion an identity, so `WorldScale` is consumed only by cross-unit callers
  (future HUD, Sector-span math), never by base gameplay magnitudes.
- **Q3 — `default_gravity` left at engine default 9.8** (untouched); the ADR records the
  deferred SI pointer (~10.72) for future vertical mechanics; nothing applied now.
- **Q4 — Render heights left as-is** (already yard-consistent: a 6-ft wall); recorded as
  no-change, not expanded into geometry.

### Downstream-slice checklist (exact edits; magnitudes unchanged)

**Renames (meters → yards):**
- `shared/monster_contracts.gd`: `DETECTION_RADIUS_METERS`→`DETECTION_RADIUS_YARDS`
  (8.0), `CHASE_SPEED_METERS_PER_SEC`→`CHASE_SPEED_YARDS_PER_SEC` (3.0),
  `MONSTER_REACH_METERS`→`MONSTER_REACH_YARDS` (2.0), + comment updates.
- `shared/combat_contracts.gd`: `reach_meters`→`reach_yards` (field + `p_reach_meters`
  param in `MeleeWeaponArchetype._init` + `is_within_reach_and_arc()` usage), Generic
  Sword = 2.0.
- `server/server_monster_manager.gd`: `RESPAWN_AREA_RADIUS_METERS`→
  `RESPAWN_AREA_RADIUS_YARDS` (2.0).
- `client/melee_strike_visual.gd`: comment/usage "reach_meters (2.0 m)"→"reach_yards
  (2.0 yд)" (reads `archetype.reach_yards`).
- Tests: `tests/unit/test_melee_combat_contracts.gd` (`archetype.reach_meters` +
  "reach meters matches…" assertions), `tests/unit/test_server_monster_state.gd`
  (comments) — updated with the rename.

**Relabels (comments only; identifiers keep their names — no "meters" in them):**
- `shared/network_config.gd`: `AUTHORITATIVE_MOVE_SPEED` (5.0) "units/second"→
  "yards/second"; `NETWORKED_PLAYER_SMOOTH_SPEED` (10.0), `NETWORKED_PLAYER_SNAP_DISTANCE`
  (15.0) "units"→"yards".
- `client/player.gd`: `move_speed` (5.0) doc note "yards/second".

**Left unchanged (recorded, no edit):**
- `project.godot` `default_gravity` (engine default 9.8) — gravity stance above.
- `shared/sector_geometry_lookup.gd`: `_TILE_FOOTPRINT = 1.0`, `_WALL_HEIGHT = 2.0`
  (6 ft), `_FLOOR_CORRIDOR_HEIGHT = 0.2` — already yard-consistent geometry.

No magnitude is re-tuned. Feeds ticket 05 (capstone ADR + spec).
