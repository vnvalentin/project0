# Slice 016: Starting town hub fixture
GitHub issue: #95

Tracker context: Phase 8 — JIT world generation and local inference; advances
[F-019](../FEATURE-LIST.md#f-019-starting-town-hub-fixture).
Planning tickets: [Starting Town map](../../.scratch/starting-town/map.md),
[issue 03 — Hub sector identity and pinning](../../.scratch/starting-town/issues/03-hub-sector-identity-and-pinning.md)
(resolved), with structure content per
[issue 05 — Player house allocation](../../.scratch/starting-town/issues/05-player-house-allocation.md)
(resolved: a fixed pool of 10 houses matching the 10-player max — this slice
authors that content only, not the allocation logic).

## SDD

Goal: Provide the starting town hub as a hard-coded, schema-v2-shaped sector
blueprint that is validated and held in memory at server boot, so a future
slice can replicate it to clients. The hub is deliberately not live-generated:
a player's house pool plus the Smithy, Armor Shop, and Inn must reliably exist
every run, which live Llama output cannot guarantee. Validation still flows
through the same `SectorBlueprintSchema` the LLM path uses, proving the
pipeline seam end-to-end without depending on LLM output quality.

Public seams:

- `server/starting_town_hub_fixture.gd` — a `RefCounted` with static-only
  functions. `SECTOR_ID` is the reserved literal `"starting_town_hub"`.
  `blueprint()` returns a fresh schema-v2 Dictionary each call (perimeter wall
  ring, central corridor cross, floor interior, and 13 structures).
  `materialize(source)` validates a candidate blueprint and returns
  `{ ok: bool, blueprint: Dictionary, outcome: String, detail: String }` — the
  fail-closed decision seam the server acts on, kept pure so both branches are
  unit-testable without a live server.
- `server/server_main.gd` — at the very top of `_start_server()` (before any
  socket is opened) calls `materialize(blueprint())`. On `ok == false` it
  `push_error`s the outcome/detail and `quit(1)` (fail closed); on success it
  stores the validated blueprint in `_starting_town_hub_blueprint` and exposes
  it read-only via `get_starting_town_hub_blueprint()`.
- `tests/unit/test_starting_town_hub_fixture.gd` — pure unit tests over the
  static functions (no server process / scene tree).

Fixture content:

- `schema_version` 2, `sector_id` `"starting_town_hub"`, `origin` `{x: 0, y: 0}`.
- Tiles: for x, y in `[-8, 8]`, a cell is `wall` on the `±8` perimeter ring,
  `corridor` on the central cross (`x == 0` or `y == 0`), and `floor`
  otherwise — a 17×17 = 289-tile footprint, well under `MAX_TILE_COUNT` (512),
  all within `MAX_COORDINATE_ABS` (32).
- Structures: exactly 10 `house` + 1 `smithy` + 1 `armor_shop` + 1 `inn` (13
  total). Every `structure_id` is unique (`house_01`…`house_10`, `smithy_01`,
  `armor_shop_01`, `inn_01`) and every `(x, y)` is a distinct interior floor
  cell with `x != 0` and `y != 0` (so none sit on the corridor cross).
  `facing_degrees` are all within `[0, 360)`.
- No `spawn_points`: monster markers are explicitly out of scope here; a future
  Basic Monsters slice extends the fixture.

Implementation decisions:

- The hub bypasses `provisional_sector_generator.gd` / `LocalLLMClient`
  entirely — it is static data, so materialization is synchronous and eager at
  boot, not an async request.
- Fail-closed is enforced before the server opens a socket: a fixture that
  fails its own schema is a programming error (e.g. after a future schema
  change), so the server refuses to start and logs the validator's outcome and
  detail rather than silently degrading to an empty/flat world.
- Tiles are generated with a loop inside `blueprint()` rather than written as
  289 literal entries; the function still returns a plain, fully-materialized
  Dictionary/Array graph (a fresh copy per call, so callers/tests cannot mutate
  shared fixture state).

## BDD

### Fixture validates through the real schema

Given the hard-coded hub blueprint returned by `StartingTownHubFixture.blueprint()`
When it is passed to `SectorBlueprintSchema.validate()`
Then the outcome is `OUTCOME_VALID` (the core regression guard: a future schema
change that would break the shipped hub is caught here).

### Fixture content matches the resolved town shape

Given the hub blueprint
When its structures are inspected
Then there are exactly 10 houses, 1 smithy, 1 armor shop, and 1 inn, every
`structure_id` is unique, every `(x, y)` is distinct, and no `spawn_points`
key is present.

### Server materializes the hub eagerly and fails closed

Given the server starts
When `_start_server()` runs
Then it materializes and validates the fixture before opening a socket, holds
the validated blueprint in memory (readable via
`get_starting_town_hub_blueprint()`), and — if the fixture ever fails
validation — refuses to start (`quit(1)`) after logging the outcome/detail,
rather than proceeding with an empty world.

## TDD evidence

`tests/unit/test_starting_town_hub_fixture.gd` (8 tests, 45 assertions) covers:
the fixture passing `validate()` with `OUTCOME_VALID`; identity fields
(`schema_version` 2, reserved `sector_id`, origin); exact structure kind counts
(10/1/1/1, 13 total); `structure_id` uniqueness; `(x, y)` position uniqueness;
absence of `spawn_points`; `materialize()` accepting the real fixture (ok, non-
empty blueprint); and `materialize()` failing closed on a corrupted fixture (ok
false, empty blueprint, specific `OUTCOME_UNSUPPORTED_KIND`).

Known coverage gap: the full live server-boot fail-closed path (the `quit(1)`
branch in `_start_server()`) is not exercised by a live-process test; instead
the decision it acts on is unit-tested through the pure `materialize()` seam.
Booting a headless server purely to assert a non-zero exit on a deliberately
corrupted fixture would add a live-process test harness this slice does not
otherwise need; the pure seam covers the branching logic.

## ADR decision

No new ADR. This slice ships static, server-owned, schema-validated data and a
fail-closed boot check. It introduces no new authority boundary, persistence
decision, or client-facing contract beyond what `CLAUDE.md` and ADR 0002
already establish; the hub is explicitly not Canon (no SQLite) and is not yet
replicated to clients.

## Validation

- `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit
  -gselect=test_starting_town_hub_fixture -gexit`: PASS, 8/8 tests, 45
  assertions, exit 0.
- `scripts/run_gut_validation.sh`: PASS, 96/96 tests, 273 assertions, exit 0;
  telemetry written to `build/validation/gut.xml` and
  `build/validation/validation-summary.json`. Prior Phase 8 suites (Slices 008,
  009, 014, 015) pass unchanged, confirming no regression.
- `godot --headless --check-only -s server/server_main.gd` and
  `... -s server/starting_town_hub_fixture.gd`: both exit 0 (clean parse/type
  check) — the server wiring compiles under strict GDScript 2.0 typing.

## Explicit non-goals and next boundary

This slice does not replicate the fixture to any client, does not call the
Slice 015 geometry translator from the server, does not implement per-player
house allocation (the 10-house pool is authored, not claimed), does not add
building facade `Area3D`/enter-exit interaction, adds no monster/spawn-point
content or logic, and touches no SQLite/Canon persistence. The next Starting
Town boundary is the server-to-client blueprint replication contract (the
map's "Not yet specified" item) — once the hub can reach a client, the Slice
015 translator can render it and facade/house-allocation slices can follow.
