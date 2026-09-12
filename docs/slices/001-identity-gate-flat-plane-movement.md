# Slice 001: Identity gate, flat plane, and player movement

Tracker context: Phase 1 — First playable vertical slice; advances
[F-001](../FEATURE-LIST.md#f-001-local-identity-gate-flat-plane-scene-and-player-movement)
and surfaces [DT-002](../TECHNICAL-DEBT-TRACKER.md#dt-002-no-automated-gdscript-test-framework).

## SDD

Goal: A player can pass a local identity gate (enter a display name), be
placed in a scene containing only a flat plane, and move a Player node around
that plane using keyboard input.

Public seam: `client/identity_gate.gd` (`_on_enter_pressed`) for the identity
gate → gameplay transition, and `client/player.gd` (`_physics_process`,
`get_planar_input`) for movement.

Inputs/outputs: The identity gate seam takes a non-empty display name string
from a `LineEdit` and, on submit, changes the scene to the gameplay scene; an
empty name is rejected and the scene does not change. The movement seam takes
the four directional `Input` actions (`move_forward`, `move_back`,
`move_left`, `move_right`) each physics tick and outputs an updated
`CharacterBody3D` position constrained to the XZ plane (no flight, no
falling through the plane).

Non-goals: No networking, no server process, no world generation, no world
save/persistence, no Ollama/SQLite integration, no production art — flat
`StandardMaterial3D`-shaded primitives only, per the user's explicit scope.

Safety invariant: This slice makes no external network calls, writes no files,
and stores the display name only in memory for the life of the process. See
[ADR 0001](../adr/0001-client-side-authority-for-first-slice.md) for why
movement is fully client-side here and what must change before networking is
added.

## BDD

### Normal path: enter identity and move

Given the identity gate scene is running and the name field contains "Vic"
When the player activates the Enter button
Then the gameplay scene loads with a flat plane and a Player positioned at
its spawn point.

### Highest-risk: empty identity is rejected

Given the identity gate scene is running and the name field is empty
When the player activates the Enter button
Then the scene does not change and no Player is created.

### Movement is bounded to the plane

Given the gameplay scene is running with the Player at rest
When the player holds the `move_forward` input for several physics ticks
Then the Player's X/Z position changes while its Y position stays fixed to
the plane's surface height.

## TDD evidence

Originally exercised only by a hand-rolled headless smoke-test script under
the accepted [DT-002](../TECHNICAL-DEBT-TRACKER.md#dt-002-no-automated-gdscript-test-framework)
scope cut. That gap is now remediated: the public seam is covered by GUT
(Godot Unit Test, vendored at `addons/gut/`) tests in
`tests/unit/test_identity_gate_and_movement.gd`, which drive the identity
gate submit handler and step the Player's movement function directly,
asserting on the resulting state with GUT's `assert_*` API. Run with
`godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit`
(3/3 passing as of 2026-09-12).

## ADR decision

[ADR 0001](../adr/0001-client-side-authority-for-first-slice.md) — client-side
movement authority is accepted for this slice only; a networked-authority
redesign is expected and tracked as future work, not treated as settled
architecture.

## Validation

- `godot --headless --path . --check-only -s client/player.gd`: PASS, exit 0.
- `godot --headless --path . --check-only -s client/player_identity.gd`:
  PASS, exit 0.
- `godot --headless --path . --check-only -s client/identity_gate.gd`: FAILS
  with "Identifier not found: PlayerIdentity". Root-caused: `--check-only -s`
  parses a single script without starting a `SceneTree`, so autoload
  singletons (declared under `[autoload]` in `project.godot`) are never
  registered as global identifiers — this reproduces on a minimal isolated
  script too and is a limitation of that check, not a defect in
  `identity_gate.gd`. Corroborated by the two runtime checks below, where the
  autoload resolves and the scene runs cleanly.
- `godot --headless --path . --quit-after 2 client/identity_gate.tscn`: PASS,
  exit 0, no errors — confirms the identity gate scene loads and the
  `PlayerIdentity` autoload resolves at real runtime.
- `godot --headless --path . --quit-after 5 client/gameplay.tscn`: PASS, exit
  0, with one benign, non-fatal engine print: `ERROR: Parameter "m" is null.
  at: mesh_get_surface_count (...)`. Root-caused via isolated repro
  (a bare `MeshInstance3D` with a `BoxMesh`/`CapsuleMesh` under
  `--display-driver headless`'s dummy renderer prints this once; a
  `MeshInstance3D` with no mesh does not). This is a Godot 4.3 headless
  dummy-renderer stub artifact, not a scene or script defect — it does not
  stop scene load, does not repeat per frame, and exit code stays 0 for any
  `--quit-after` value tried.
- `godot --headless --path . -s scripts/test_identity_gate_and_movement.gd`:
  **ALL PASS**, exit 0. All 6 assertions passed: empty name rejected with an
  error shown and no scene change; non-empty name stored on `PlayerIdentity`;
  zero input yields zero planar input; the Player moves along X/Z over 30
  physics ticks; Y position stays exactly fixed at the plane's surface height
  throughout. This test caught one real defect during development (see
  below) and one real scene-format defect, both fixed before this result.
- `godot --headless --path . --editor --quit`: PASS, exit 0 — confirms the
  project opens and closes cleanly under the editor codepath with no import
  or parse errors. This is a headless, non-interactive check; it does not
  exercise interactive keyboard input or visual rendering.
- Manual (interactive, GUI) editor run: not performed (headless environment
  only). Recorded as a known validation gap, not an implied claim of
  interactive-input or visual correctness.

### Defects found and fixed during this slice's validation

- `client/identity_gate.tscn` used `unique_name_in_owner="true"` with `%Name`
  lookups in `_ready()`. This failed at runtime ("Node not found: %NameInput")
  because a scene root's own `owner` is null, so `%Name` resolution from the
  root itself does not find its own scene's unique names in this
  instantiation path. Fixed by using plain `$Path/To/Node` lookups instead.
- `client/gameplay.tscn` declared `[sub_resource ... name="..."]`; Godot 4.3's
  format-3 `.tscn` parser requires `id=`, not `name=`, on `sub_resource`
  blocks (confirmed by minimal isolated repro). Fixed by renaming the
  attribute on all six sub-resources.
- The original test for "non-empty name transitions the scene" drove the
  transition through the real `_on_enter_pressed()` → `change_scene_to_file`,
  which left a second live `gameplay.tscn` instance (with its own `Player`)
  running for the rest of the suite; its `CharacterBody3D` collided with the
  movement test's own `Player`, pushing it upward (observed climbing from
  Y=1 to Y≈6.6) and failing the "Y stays fixed" assertion. Fixed by asserting
  the identity-storage side effect directly instead of triggering a real
  scene change from that sub-test, so only one gameplay scene is ever live
  at a time.
