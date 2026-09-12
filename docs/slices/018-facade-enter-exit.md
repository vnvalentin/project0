# Slice 018: Facade enter/exit proximity labels

Tracker context: Phase 8 — JIT world generation and local inference; advances
[F-021](../FEATURE-LIST.md#f-021-facade-enter-exit-proximity-labels).
Planning tickets: [Starting Town map](../../.scratch/starting-town/map.md),
[issue 04 — Facade representation and enter/exit](../../.scratch/starting-town/issues/04-facade-representation-and-enter-exit.md)
(resolved). Builds on the now-visible town (Slice 017) to make its buildings
interactive.

## SDD

Goal: When the local player walks up to a starting-town building, show a
cosmetic "You are at the <building>" label; clear it when they walk away.
Purely client-observed and cosmetic — no server authority, no world mutation,
no interior scene, no exclusivity between players.

Public seams:

- `client/facade_proximity.gd` (`Area3D`) — a per-structure proximity trigger.
  On `body_entered`/`body_exited` it filters to the local WASD `Player` (via
  `is_local_player`, name `"Player"`) and calls `show_facade` / `clear_facade`
  on the facade presenter (found through the `facade_presenter` group). An
  exported `building_display_name` is set per prefab.
- `client/facade_presenter.gd` (`Label`) — the UI element in
  `client/gameplay.tscn`'s UI layer. Joins the `facade_presenter` group,
  starts hidden, and shows/clears the "You are at the <name>" line. `clear_facade`
  only clears when the line still matches the facade being left, so a late exit
  cannot blank a newer facade's line.
- `client/structures/{house,smithy,armor_shop,inn}.tscn` — each prefab gains a
  `FacadeProximity` `Area3D` (with `building_display_name` "House" / "Smithy" /
  "Armor Shop" / "Inn" and a bounded `BoxShape3D` proximity volume) so every
  instanced structure carries its own trigger.
- `client/gameplay.tscn` — a `FacadeLabel` `Label` under the UI `CanvasLayer`
  carrying `facade_presenter.gd`.

Design decisions:

- Only the node named `"Player"` (the local WASD player in `gameplay.tscn`)
  drives the label. The structure's own `StaticBody3D`, the `FlatPlane`, the
  `NetworkedPlayer`, and remote peers' `RemotePlayer_*` bodies are all ignored,
  which is exactly what makes this non-exclusive: two peers standing at the same
  facade each see only their own local label, and no peer's presence affects
  another's. It also naturally filters the Area3D's self-overlap with its parent
  building body and the ground plane.
- The presenter is discovered via a group rather than a hard node path, because
  `FacadeProximity` areas are instanced at runtime under `SectorGeometry`
  (Slice 017) and cannot reference an authored node by path.
- No server involvement at all: entering a building is presentation, not a world
  mutation or outcome, so it stays client-only per CLAUDE.md's Runtime Ownership
  split. If a future feature (shop economy, quests) needs server awareness of
  "which building", that is a separate decision when that feature is scoped.

## BDD

### Local player enters a facade

Given the town is rendered and a facade presenter is present
When the local `Player` body enters a structure's `FacadeProximity` area
Then the presenter shows "You are at the <building name>" and becomes visible.

### Local player leaves a facade

Given the presenter is showing a facade
When the local `Player` body exits that facade's area
Then the presenter clears the line and hides.

### Other bodies are ignored

Given a facade area
When a remote peer's Player, the structure body, or the flat plane overlaps it
Then the presenter is not shown (only the local player drives it).

### Overlapping facades resolve sanely

Given the presenter is showing facade A
When the player enters facade B and then a late exit from A arrives
Then B's line is shown and the stale A exit does not blank it.

## TDD evidence

- `tests/unit/test_facade_presenter.gd` (4 tests, 10 assertions): starts
  hidden/empty; `show_facade` sets the line and visibility; `clear_facade` only
  clears the matching facade (a mismatched clear is ignored); switching facades
  replaces the line.
- `tests/integration/test_facade_enter_exit.gd` (5 tests, 11 assertions): local
  player entry shows the name; exit clears it; non-local bodies (remote peer,
  structure body, flat plane) are ignored; the `is_local_player` filter
  (Player / remote / null); and a real Area3D physics-overlap test that
  instantiates the actual `smithy.tscn` prefab with a `CharacterBody3D` named
  `Player` overlapping it and asserts the presenter shows "You are at the Smithy"
  after physics frames — confirming the prefab's collision configuration
  actually fires `body_entered`.

## ADR decision

No new ADR. This slice adds cosmetic, client-only presentation over already-
rendered geometry. It introduces no authority boundary, persistence, or network
contract.

## Validation

- `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit
  -gselect=test_facade_presenter -gexit`: PASS, 4/4, 10 assertions, exit 0.
- `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/integration
  -gselect=test_facade_enter_exit -gexit`: PASS, 5/5, 11 assertions, exit 0.
- `scripts/run_gut_validation.sh`: PASS, 109/109 tests, 308 assertions, exit 0;
  telemetry written to `build/validation/`. Prior suites (including the Slice
  015 geometry and Slice 017 replication tests that load these structure
  prefabs) pass unchanged. (The "Parameter m is null" / "Parse JSON failed"
  lines are the pre-existing expected error-path output from malformed-JSON
  contract tests, not failures.)
- Regression caught and fixed during development (Jidoka): the initial
  `FacadeProximity` `CollisionShape3D` `Transform3D` in all four prefabs had 11
  values instead of 12 (a dropped origin component), which made every structure
  `.tscn` fail to parse and broke the Slice 015/017 tests that `load()` them.
  Corrected to a valid 12-value `Transform3D` (origin `(0, 2, 0)`); the full
  suite then returned to green.

## Explicit non-goals and next boundary

This slice adds no interior scenes, no interact keypress (proximity is
automatic), no shop economy/buy-sell/inventory, no per-player house ownership
(all houses show "House" — allocation is Starting Town ticket 05, a separate
slice), and no server awareness of which building a player is in. The remaining
Starting Town future slice is player house allocation (ticket 05); the Basic
Monsters map (3 resolved tickets) is independent.
