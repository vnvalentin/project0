# Slice 014: Sector blueprint schema v2 — structures and spawn points

Tracker context: Phase 8 — JIT world generation and local inference; advances
[F-017](../FEATURE-LIST.md#f-017-sector-blueprint-schema-v2-structures-and-spawn-points).
Planning tickets: [Starting Town map](../../.scratch/starting-town/map.md),
[issue 01 — Schema v2: structures and spawn points](../../.scratch/starting-town/issues/01-schema-v2-structures-and-spawn-points.md)
(resolved).

## SDD

Goal: Extend the existing version-one sector blueprint validator
(`shared/sector_blueprint_schema.gd`, Slice 008) to also accept an optional
version-two shape carrying `structures` and `spawn_points` arrays, without
replacing or weakening version-one's tiles-only contract, and without
performing any geometry translation, gameplay state, persistence, or Canon
work.

Public seams:

- `shared/sector_blueprint_schema.gd` — validates parsed blueprint data for
  both `schema_version` 1 and 2. `structures` and `spawn_points` become
  recognized, optional top-level arrays validated with the same fail-closed
  style as `tiles`.
- `tests/unit/test_sector_blueprint_schema_v2.gd` — new fast unit test file
  exercising the validator directly with Dictionary/Array fixtures (no
  HTTP/service involved).

`server/sector_blueprint_service.gd` is unaffected: it already forwards
whatever outcome/blueprint the schema validator returns and contains no
version-specific branching of its own, so it requires no code change for this
slice.

Contract additions (schema_version 2, per resolved ticket 01):

- `structures`: optional array (absent or empty is valid). Each entry:
  `{ structure_id: non-empty unique String, kind: String in
  SUPPORTED_STRUCTURE_KINDS ("house", "smithy", "armor_shop", "inn"), x:
  number bounded by MAX_COORDINATE_ABS, y: number bounded by
  MAX_COORDINATE_ABS, facing_degrees: number in [0, 360) }`. No
  footprint/size field (ticket 01/02: fixed-size prefab per kind, facades
  only).
- `spawn_points`: optional array (absent or empty is valid), bounded by
  `MAX_SPAWN_POINT_COUNT`. Each entry: `{ spawn_id: non-empty String, x:
  number bounded by MAX_COORDINATE_ABS, y: number bounded by
  MAX_COORDINATE_ABS }`. No `kind`/monster field (deliberately deferred to
  the future Basic Monsters slice).
- `schema_version` becomes a supported-set check (`1` or `2`) instead of
  strict equality against a single `CURRENT_SCHEMA_VERSION`. Both versions
  validate `sector_id`, `origin`, and `tiles` identically. `structures` and
  `spawn_points` are optional for both versions (a `schema_version: 1`
  payload with no `structures`/`spawn_points` keys — the existing Slice 008
  shape — keeps validating exactly as before; a `schema_version: 2` payload
  may include either or both new arrays, or omit them for a town-adjacent
  sector with no buildings yet).

Implementation decisions:

- `MAX_SPAWN_POINT_COUNT = 16`. Justification: the Starting Town map's hub
  sector is the only known near-term producer of `spawn_points`, and the
  Basic Monsters map (still pre-slice, cross-map blocked on this ticket)
  only anticipates a small, readable, non-overwhelming number of monster
  markers in one hub-adjacent sector, consistent with `CLAUDE.md`'s bounded
  contract-validation-only bounds elsewhere in this file (e.g.
  `MAX_TILE_COUNT = 512` bounds a much larger surface). 16 is generous
  enough for a starting town's needs while still being a small, auditable,
  reviewable bound; it can be revised by a future versioned change if a
  later sector design needs more.
- `structure_id` uniqueness is enforced within a single blueprint. Rationale:
  a duplicate `structure_id` inside one sector cannot be resolved to a single
  addressable structure by any future consumer (geometry translation, house
  allocation), so accepting it would silently create ambiguity that fails
  closed later instead of now. Duplicate `structure_id` values reject with
  `OUTCOME_INCOMPLETE` (mirrors how missing/malformed required identity
  fields are already reported; no new outcome constant was needed).
- No new `OUTCOME_*` constants were added. `OUTCOME_INCOMPLETE`,
  `OUTCOME_OUT_OF_BOUNDS`, and `OUTCOME_UNSUPPORTED_KIND` already cover every
  new rejection case (missing/wrong-type fields, out-of-range
  coordinates/facing/count, and unsupported structure `kind`).

## BDD

### Valid version-two blueprint with structures and spawn points

Given a parsed `schema_version: 2` blueprint with a sector id, origin,
supported bounded tiles, a `structures` array of unique-id, supported-kind,
bounded-coordinate, bounded-facing entries, and a `spawn_points` array within
`MAX_SPAWN_POINT_COUNT`
When the schema validator runs
Then it returns `valid` and the validated blueprint, including the
`structures` and `spawn_points` arrays unchanged.

### Backward-compatible version-one blueprint

Given a parsed `schema_version: 1` blueprint identical in shape to Slice
008's existing valid fixture (no `structures`/`spawn_points` keys present)
When the schema validator runs
Then it returns `valid`, exactly as it did before this slice.

### Invalid structure or spawn point data

Given a `structures` or `spawn_points` entry that is missing a required
field, has a wrong-typed field, uses an unsupported structure `kind`, has an
out-of-bounds `x`/`y`/`facing_degrees`, repeats a `structure_id` already used
in the same blueprint, or a `spawn_points` array exceeding
`MAX_SPAWN_POINT_COUNT`
When the schema validator runs
Then it returns the specific matching failure outcome (`incomplete`,
`unsupported_kind`, or `out_of_bounds`) and no blueprint.

### Wrong schema version still rejected

Given a blueprint whose `schema_version` is neither `1` nor `2`
When the schema validator runs
Then it returns `wrong_schema_version` and no blueprint, unchanged from
Slice 008 behavior.

## TDD evidence

`tests/unit/test_sector_blueprint_schema_v2.gd` exercises the validator
directly (no service/HTTP) with Dictionary/Array fixtures covering: valid v2
payload with structures + spawn points, valid v1 payload with no
structures/spawn_points (regression), missing/wrong-type structure fields,
unsupported structure kind, out-of-bounds structure coordinates and facing,
out-of-bounds spawn point coordinates, duplicate `structure_id`, and
spawn_points exceeding `MAX_SPAWN_POINT_COUNT`. The existing
`tests/integration/test_sector_blueprint_contract.gd` (Slice 008) is left
unchanged and re-run as regression evidence that v1-only behavior and the
service seam are untouched.

## ADR decision

No new ADR. This slice extends an existing bounded validation contract
(Slice 008) with two new optional, still-server-validated fields. It
introduces no new authority boundary, world-state ownership, or persistence
decision beyond what `CLAUDE.md` and ADR 0002 already establish.

## Validation

- `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit
  -gselect=test_sector_blueprint_schema_v2 -gexit`: PASS, 16/16 tests, 20
  assertions, exit 0.
- `scripts/run_gut_validation.sh`: PASS, 77/77 tests, 188 assertions, exit 0;
  telemetry written to `build/validation/gut.xml` and
  `build/validation/validation-summary.json`. The existing Slice 008
  integration suite (`test_sector_blueprint_contract.gd`, 7/7) and Slice 009
  suite (`test_provisional_sector_generation.gd`, 9/9) pass unchanged,
  confirming v1-only behavior and the service seam are unaffected.

## Explicit non-goals and next boundary

This slice does not translate structures/tiles into geometry or scenes,
materialize the hub sector fixture at server boot, add building facade
`Area3D`/enter-exit behavior, allocate player houses, add any monster/combat
contract (`shared/monster_contracts.gd` is out of scope here), or touch
SQLite/Canon persistence. The next Starting Town slice must decide the
server-to-client blueprint replication contract (see the map's "Not yet
specified" section) before any of the above can be built.
