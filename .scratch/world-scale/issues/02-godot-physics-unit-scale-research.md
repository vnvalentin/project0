Type: research
Status: resolved

## Question

Confirm, from primary sources (Godot 4 official docs / engine source), how Godot 4
interprets 3D world units and what anchoring **1 unit = 1 yard** (vs the engine's
implicit 1 unit = 1 meter) implies:

- Does Godot 4's 3D physics (default gravity, `CharacterBody3D`, `RigidBody3D`,
  ProjectSettings `physics/3d/default_gravity = 9.8`) assume 1 unit = 1 meter? What
  drifts if a unit is treated as 1 yard?
- Gravity / jump / fall feel: is `default_gravity` expressed in units/s² regardless
  of real-world label, so "9.8 yд/s²" is ~9 % weaker than 9.8 m/s²? Should gravity be
  scaled to keep an Earth-like feel, or left as-is?
- Any engine subsystems that hard-assume meters (audio Doppler, navigation, occlusion
  culling, LOD, physics stability thresholds)?
- The recommended convention for a game that wants Imperial world labels while keeping
  Godot's physics well-behaved.

Cite each claim's source. Write findings to
`.scratch/world-scale/research/02-godot-unit-scale.md`.

## Answer

Resolved by background research — full findings with primary-source citations in
[research/02-godot-unit-scale.md](../research/02-godot-unit-scale.md).

- Godot 4 documents **1 unit = 1 meter** (gravity "meters per second squared",
  `Camera3D.size` "in meters", Large World Coordinates "8192×8192 meters"), but this
  is a **labeling/tuning convention, not a hard engine dependency** — the integrator is
  unit-agnostic (`RigidBody3D.linear_velocity` is "units per second"; gravity is data
  via `gravity_scale × default_gravity`).
- `physics/3d/default_gravity` defaults to **9.8**. Relabeled as yд/s² that is
  9.8 × 0.9144 = **8.96 m/s² (≈ 8.6 % weaker** than Earth's 9.80665). A pure relabel
  changes nothing internally; the gap only exists versus real-world SI.
- Treating **1 unit = 1 yard is low-risk**: the 0.9144 factor keeps every meter-tuned
  default (GodotPhysics/Jolt solver thresholds, `NavigationAgent` sizes, the fixed 343
  Doppler speed-of-sound, LOD/visibility) within ~8.6 % of intent — unlike feet (~3.3×)
  or km (1000×). The current custom server-tick movement is unaffected entirely.
- Recommendation feeding tickets 03/04/05: anchor 1 unit = 1 yard as a **pure
  relabel**; store SI-reconciliation constants in the versioned tuning seam
  (`default_gravity ≈ 10.72` only if Earth-accurate fall is ever needed; note the
  Doppler 343 is not API-rescalable).
