# Slice 053 — F-026 derive monster exclusion from town bounds
GitHub issue: #95

Status: **delivered**

Phase: 8 (JIT world generation and local inference), completing
[F-026](../FEATURE-LIST.md#f-026-organic-districted-starting-city).

## User outcome

Monster spawn/respawn exclusion is derived from the actual town's tile bounds
in the validated blueprint, instead of the hard-coded
`TOWN_EXCLUSION_HALF_EXTENT = 32.0` constant, so any town size (the shipped
fixture, a differently-sized fixture, or a future validated LLM town) keeps
monsters just outside the walls automatically. This was F-026's last
remaining item; the feature moves to `Implemented`.

## Scope and non-goals

In scope:
- A pure static helper,
  `ServerMonsterManager.town_exclusion_half_extent(blueprint: Dictionary) ->
  float`, that computes `max over tiles of max(abs(tile.x), abs(tile.y))` and
  adds a named margin constant `TOWN_EXCLUSION_MARGIN_YARDS = 2.0`. Falls back
  to the existing `TOWN_EXCLUSION_HALF_EXTENT` constant when the blueprint has
  no tiles (defensive — should not occur for a validated blueprint).
- A per-instance exclusion half-extent on `ServerMonsterManager`, used by
  `_random_position_outside_town` instead of the bare constant. Added as an
  optional trailing `_init` parameter (`exclusion_half_extent :=
  TOWN_EXCLUSION_HALF_EXTENT`) so every existing constructor call site and
  test that passes only `spawn_points` (or up to `respawn_cooldown_ticks`)
  keeps today's exact 32.0 behavior unchanged.
- Boot wiring in `server/server_main.gd`: the exclusion half-extent is
  computed from `_starting_town_hub_blueprint` via the new static helper and
  passed to the manager constructor, with a one-line boot log
  (`"Monster exclusion half-extent derived from town: %.1f yd."`).

Out of scope (unchanged by this slice):
- Monster AI, damage/death, respawn timing, spawn-point parsing, the schema,
  the fixture, or the client.
- Non-square/true-octagon exclusion geometry — a square half-extent derived
  from the max tile bound matches today's model and is sufficient; no polygon
  test is introduced.
- Live-Ollama dependency in tests, or re-deriving exclusion on JIT sector
  generation (this slice is the starting-town boundary only, matching
  [Slice 031](031-bigger-village-npc-leader-housing.md)'s scope, which
  hard-coded the current 32.0 value this slice now replaces with a
  derivation).

## Public seam

- `server/server_monster_manager.gd`: new static
  `town_exclusion_half_extent(blueprint: Dictionary) -> float`, new
  `TOWN_EXCLUSION_MARGIN_YARDS` constant, and a new optional trailing
  `exclusion_half_extent` `_init` parameter feeding the existing
  `_random_position_outside_town`.
- `server/server_main.gd`: `_start_server()` now derives the exclusion
  half-extent from `_starting_town_hub_blueprint` before constructing
  `ServerMonsterManager`.

## ADR rationale

No new ADR. This replaces a hard-coded tuning-adjacent constant with a pure
derivation from already-validated blueprint data; it introduces no new
authority, persistence, network contract, or validation rule, and the server
remains the sole owner of the exclusion computation (CLAUDE.md's "the server
owns outcomes"). The square half-extent model is unchanged — only its source
of truth moves from a hand-tuned constant to the blueprint itself.

## BDD

### The shipped fixture derives the same extent it hard-coded before

Given the `StartingTownHubFixture` blueprint (radius 30 octagon)
When `town_exclusion_half_extent(blueprint)` is called
Then it returns exactly `32.0`, matching the prior hard-coded constant, so
default boot behavior is unchanged.

### A differently-sized blueprint scales the exclusion box

Given a hand-built blueprint whose furthest tile is at `max(|x|, |y|) == 5`
When `town_exclusion_half_extent(blueprint)` is called
Then it returns `7.0` (`5 + TOWN_EXCLUSION_MARGIN_YARDS`); a larger blueprint
(furthest tile `40`) returns `42.0` proportionally.

### An empty-tiles blueprint fails safe to the fixed constant

Given a blueprint with an empty (or missing) `tiles` array
When `town_exclusion_half_extent(blueprint)` is called
Then it returns the fixed fallback `TOWN_EXCLUSION_HALF_EXTENT` (32.0) rather
than 0 or a crash.

### Respawn stays outside a derived (non-default) exclusion box

Given a `ServerMonsterManager` constructed with a small hand-built blueprint's
derived extent (7.0, far smaller than the fixture's 32.0)
When repeated kill/respawn cycles run across many ticks
Then every respawn position lands outside that smaller derived box —
confirming the manager actually uses the per-instance derived value, not the
fixed fallback constant.

## TDD

`tests/unit/test_server_monster_manager.gd` (extended, not duplicated):
- `test_town_exclusion_half_extent_matches_fixture_constant`: the shipped
  fixture derives to exactly 32.0.
- `test_town_exclusion_half_extent_scales_with_small_blueprint`: a hand-built
  blueprint with furthest tile `5` derives to `5 + margin`.
- `test_town_exclusion_half_extent_scales_with_larger_blueprint`: furthest
  tile `40` derives to `40 + margin`.
- `test_town_exclusion_half_extent_falls_back_when_no_tiles`: empty `tiles`
  array and a blueprint missing the `tiles` key both fall back to the fixed
  constant.
- `test_respawn_stays_outside_derived_extent_for_a_small_blueprint`: many
  kill/respawn cycles with a manager constructed at a small derived extent
  (7.0) never land inside that smaller box.
- All 11 pre-existing tests in the file (spawn count, initial positions,
  chase, death/respawn cooldown, `living_targets`, `receive_player_hit`
  variants, and `test_every_respawn_stays_outside_town` using the default
  32.0 constant) pass unchanged — proving the default trailing-parameter value
  preserves prior behavior exactly.

## Validation

Focused: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit
-gselect=test_server_monster_manager -gexit` passed **16/16 tests, 175
assertions**, exit 0.

Parse checks:
- `godot --headless --check-only -s server/server_monster_manager.gd` exit 0.
- `godot --headless --check-only -s server/server_main.gd` exit 0.

Full suite: `scripts/run_gut_validation.sh` passed **315/315 tests across
44/44 scripts and 1224 assertions**, exit 0 (one pre-existing unrelated
`push_warning` from the sector-geometry-translator tests, not a failure);
`build/validation/validation-summary.json` recorded `scripts_expected: 44,
scripts_ran: 44`.

Record sync: `scripts/check_record_sync.sh` exited 0 (0 errors, 6 pre-existing
unrelated warnings about slice docs with no named feature).

Runtime boot evidence (2026-09-14), default-off flags (no LLM-at-boot, no E2E
collision bypass), using a bare relative `user://`-scoped DB path (an absolute
`/tmp` path was confirmed this session to fail to open and fail-close the
server, per SqliteStore's own rule):

```
PROJECT0_ACCOUNTS_DB_PATH=boot053.db godot --headless --path . -s server/server_main.gd --quit-after 300
```

```
Starting town hub fixture validated: 28 structures.
Town collision map ready: 477 solid cells.
Starting town house pool ready: 10 houses.
Monster exclusion half-extent derived from town: 32.0 yd.
Spawned 4 monsters outside the town.
Opened database successfully (/home/vic/.local/share/godot/app_userdata/Project0/boot053.db)
Starting town Canon ready: ok.
Accounts database ready at user://boot053.db (schema ensured).
Server listening on 127.0.0.1:9999
Closed database (/home/vic/.local/share/godot/app_userdata/Project0/boot053.db)
```

The derived half-extent (32.0 yd) exactly matches the previously hard-coded
constant for the shipped fixture, confirming default runtime behavior is
unchanged end to end. The throwaway DB file was deleted from
`~/.local/share/godot/app_userdata/Project0/` after capture.

## Surfaced and fixed

This slice's full-suite validation surfaced a pre-existing, unrelated
intermittent failure in
`tests/integration/test_character_crud_rpc.gd::test_select_records_selected_character_id_on_session_and_refreshes_last_played_at`.
The test waited on a fixed `create_timer(1.1).timeout` before asserting
`last_played_at` (whole-second resolution) had advanced; in headless GUT the
fixed real-time timer intermittently under-waited, landing create and select
in the same integer second and failing `assert_gt` (observed ~1 in 3 runs).
Fixed test-only, per the Slice 041 precedent of fixing a latent issue surfaced
by validation: the fixed-duration wait was replaced with a deterministic
`await get_tree().process_frame` loop that spins until
`Time.get_unix_time_from_system()` strictly exceeds the creation second, so
the refreshed timestamp is reliably newer regardless of real-time timer
accuracy. No production code, schema, or `_now()` semantics changed. Verified
with three consecutive full-suite runs, all green at 315/315, exit 0.
