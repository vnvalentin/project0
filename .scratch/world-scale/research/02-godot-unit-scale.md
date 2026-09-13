Type: research
Status: complete
Sources: Godot 4 official docs (docs.godotengine.org/en/stable) + engine source
  (github.com/godotengine/godot). Docs served label "Godot Engine 4.7
  documentation" (the `stable` channel); the unit conventions and settings cited
  here are stable across 4.x. Project targets 4.3 — version-sensitive points are
  flagged inline.

# Godot 4 World-Unit Scale: Facts for the "1 unit = 1 yard" Decision

Research for ticket
[02-godot-physics-unit-scale-research.md](../issues/02-godot-physics-unit-scale-research.md).
Every claim cites its primary source (full URL + the exact property / method /
symbol). This note reports engine facts only; it does not re-decide the anchor.

## 1. Does Godot 4 assume 1 unit = 1 meter in 3D?

**Yes — the meter is the documented convention, but it is a labeling/tuning
convention, not a hard-coded engine dependency.** Multiple first-party places
name the unit "meter":

- `physics/3d/default_gravity` is described as "The default gravity strength in
  3D (**in meters per second squared**)."
  [class_projectsettings.html](https://docs.godotengine.org/en/stable/classes/class_projectsettings.html)
  (property `physics/3d/default_gravity`).
- `Camera3D.size` is "The camera's size **in meters** measured as the diameter…"
  [class_camera3d.html](https://docs.godotengine.org/en/stable/classes/class_camera3d.html)
  (property `size`).
- The Large World Coordinates guide expresses the safe single-precision play
  area as "…a playable on-foot area not exceeding **8192×8192 meters**", and its
  precision table is headed in "meters".
  [large_world_coordinates.html](https://docs.godotengine.org/en/stable/tutorials/physics/large_world_coordinates.html).
- The Jolt physics settings are explicitly labeled "in meters" / "in meters per
  second" (see §4).
  [class_projectsettings.html](https://docs.godotengine.org/en/stable/classes/class_projectsettings.html).

There is **no** official statement that "1 unit = 1 yard is fine," but there is
also no meter constant baked into the integrator — see §3.

## 2. `physics/3d/default_gravity`: value and unit semantics

- Default value: `physics/3d/default_gravity = 9.8`; direction
  `physics/3d/default_gravity_vector = Vector3(0, -1, 0)`.
  [class_projectsettings.html](https://docs.godotengine.org/en/stable/classes/class_projectsettings.html)
  (properties `physics/3d/default_gravity`, `physics/3d/default_gravity_vector`).
- The doc labels it "meters per second squared", but the physics engine consumes
  the raw number as **units/s²**: gravity is applied via `RigidBody3D.gravity_scale`
  ("multiplied by `ProjectSettings.physics/3d/default_gravity`")
  [class_rigidbody3d.html](https://docs.godotengine.org/en/stable/classes/class_rigidbody3d.html)
  (property `gravity_scale`), and velocities are in unit terms, not meter terms
  (`RigidBody3D.linear_velocity` = "in **units** per second") — so the label is
  advisory. The engine never converts units to SI internally.

**Yard reinterpretation (confirming the ticket's figure):** keep the number 9.8
and call the unit a yard → objects accelerate at 9.8 yd/s². Converting to SI
(1 yd = 0.9144 m exactly): 9.8 × 0.9144 = **8.961 m/s²**. Versus real Earth
gravity (9.80665 m/s²) that is **≈ 8.6% weaker** (the ticket's "~9%" is a fair
round number; precise deviation is ~8.6%, i.e. the yard/metre factor 0.9144).

Important nuance: a *pure relabel* (keep every number, just call units "yards")
changes **nothing** in the simulation — it stays internally consistent. The
~8.6% "weakness" only appears when you cross-check against *real-world* physics
for the object's real-world (yard) size. For gameplay feel this is negligible;
if you ever want Earth-accurate free-fall for yard-sized objects, set
`default_gravity ≈ 10.72` (9.80665 ÷ 0.9144) instead of 9.8.

## 3. Do CharacterBody3D / RigidBody3D / move_and_slide hard-assume meters?

**No. They are unit-agnostic; everything scales as long as you stay internally
consistent.**

- `RigidBody3D.linear_velocity` — "The body's linear velocity **in units per
  second**." `angular_velocity` is "in **radians** per second."
  [class_rigidbody3d.html](https://docs.godotengine.org/en/stable/classes/class_rigidbody3d.html).
- `CharacterBody3D.velocity` — "Current velocity vector (**typically** meters per
  second)". The hedge "typically" confirms it is a convention, not a requirement.
  `move_and_slide()` "uses the physics step's `delta` value automatically", i.e.
  it just integrates velocity × time with no meter term.
  [class_characterbody3d.html](https://docs.godotengine.org/en/stable/classes/class_characterbody3d.html)
  (property `velocity`, method `move_and_slide`).
- The 2D/3D physics model applies gravity as a plain acceleration you add per
  tick (`velocity.y += gravity * delta`) at a fixed 60 Hz step — no unit
  assumption in the loop.
  [physics_introduction.html](https://docs.godotengine.org/en/stable/tutorials/physics/physics_introduction.html).

Caveat: a few `CharacterBody3D` **defaults are absolute distances in units**,
implicitly sized for ~1 m: `floor_snap_length = 0.1`, `safe_margin = 0.001`
(angles like `floor_max_angle = 0.7853982` are radians, scale-free).
[class_characterbody3d.html](https://docs.godotengine.org/en/stable/classes/class_characterbody3d.html).
At yard scale these are off by only ~8.6% from their meter intent — harmless.

For this project specifically: server-authoritative movement runs as custom
integration at a fixed tick (not `RigidBody3D`), which is inherently
unit-agnostic — so the anchor choice does not perturb current movement. The
sensitivities below matter only if/when engine physics bodies, navigation, or
3D audio Doppler are introduced.

## 4. Subsystems with meter-tuned defaults (real primary-source values only)

These have **absolute** defaults chosen around 1 unit ≈ 1 m. They only misbehave
if the unit is *much* larger/smaller than a meter; a yard (0.9144 m) is ~8.6%
off, i.e. comfortably inside tolerance.

- **GodotPhysics3D solver thresholds** (the engine used by Godot 4.3 by default;
  "only effective when using GodotPhysics3D"):
  `physics/3d/solver/contact_max_allowed_penetration = 0.01`,
  `contact_max_separation = 0.05`, `contact_recycle_radius = 0.01`,
  `physics/3d/sleep_threshold_linear = 0.1`.
  [class_projectsettings.html](https://docs.godotengine.org/en/stable/classes/class_projectsettings.html).
  These are raw distances/speeds in units; at extreme unit scales, penetration
  and sleep behavior degrade.
- **Jolt physics** (default 3D engine only for projects created in **Godot 4.6+**
  — informational for a 4.3 project). Values are explicitly "in meters":
  `penetration_slop = 0.02`, `speculative_contact_distance = 0.02`,
  `body_pair_contact_cache_distance_threshold = 0.001`,
  `soft_body_point_radius = 0.01` (all "in meters");
  `bounce_velocity_threshold = 1.0`, `sleep_velocity_threshold = 0.03`,
  `limits/max_linear_velocity = 500.0` (all "in meters per second");
  `limits/world_boundary_shape_size = 2000.0`.
  [class_projectsettings.html](https://docs.godotengine.org/en/stable/classes/class_projectsettings.html).
- **Audio Doppler / speed of sound.** There is **no** speed-of-sound project
  setting. Doppler is opt-in and **off by default**: `Camera3D.doppler_tracking`
  defaults to `DOPPLER_TRACKING_DISABLED` (`0`)
  [class_camera3d.html](https://docs.godotengine.org/en/stable/classes/class_camera3d.html)
  (property `doppler_tracking`). When enabled, the speed of sound is a
  **hard-coded constant** — `static constexpr float speed_of_sound = 343.0F;` in
  [scene/3d/audio_stream_player_3d.cpp](https://github.com/godotengine/godot/blob/master/scene/3d/audio_stream_player_3d.cpp)
  — i.e. 343 units/s, tuned for units = metres and **not** rescalable via API. If
  Doppler is ever used with a non-metre unit, pitch shift is mistuned by the same
  scale factor (~8.6% at yard scale).
- **NavigationServer / NavigationAgent3D defaults.** Map defaults:
  `navigation/3d/default_cell_size = 0.25`, `default_cell_height = 0.25`,
  `default_edge_connection_margin = 0.25`, `default_link_connection_radius = 1.0`
  [class_projectsettings.html](https://docs.godotengine.org/en/stable/classes/class_projectsettings.html).
  Agent defaults sized for a ~1 m human: `radius = 0.5`, `height = 1.0`,
  `max_speed = 10.0`, `neighbor_distance = 50.0`, `path_desired_distance = 1.0`,
  `target_desired_distance = 1.0`, `path_max_distance = 5.0`.
  [class_navigationagent3d.html](https://docs.godotengine.org/en/stable/classes/class_navigationagent3d.html).
- **VisualInstance3D LOD / visibility ranges.** Mesh-LOD switching is measured in
  **pixels**, so it is scale-independent: `rendering/mesh_lod/lod_change/
  threshold_pixels = 1.0`
  [class_projectsettings.html](https://docs.godotengine.org/en/stable/classes/class_projectsettings.html).
  In contrast, `GeometryInstance3D.visibility_range_begin/end` and camera clip
  planes are absolute world units (`Camera3D.near = 0.05`, `far = 4000.0`)
  [class_camera3d.html](https://docs.godotengine.org/en/stable/classes/class_camera3d.html)
  (properties `near`, `far`) — set per node, so unaffected by a small unit
  relabel.
- **Large-world / double precision.** Single precision is "safe" up to the
  8192×8192 m band for third-person, degrading past ~32768 m; going double
  ("large world coordinates") requires recompiling with the `precision=double`
  SCons flag.
  [large_world_coordinates.html](https://docs.godotengine.org/en/stable/tutorials/physics/large_world_coordinates.html).
  Because a yard < a metre, per-unit precision is *slightly better*, not worse —
  a Sector of 440 units (¼ mile) sits far inside the safe single-precision band.

## 5. Recommended convention: Imperial presentation vs. engine unit

Primary sources establish two things: (a) Godot's defaults are authored for
1 unit ≈ 1 metre (§1, §4), and (b) the simulation core is unit-agnostic (§2, §3).
The standard, well-supported advice that follows:

- **Keep the internal engine unit ≈ 1 metre and convert Imperial for display**
  is the lowest-risk path in general, because it leaves every meter-tuned default
  (GodotPhysics/Jolt solver thresholds, navigation sizes, the 343 Doppler
  constant, LOD/visibility distances) at its intended scale.
- **However, "1 unit = 1 yard" is a special, low-risk case.** A yard is 0.9144 m
  — only ~8.6% off a metre — so *all* meter-tuned defaults stay within ~9% of
  their design point, i.e. inside normal tuning tolerance. No solver, navigation,
  audio, or precision behavior is meaningfully disturbed. This is materially
  different from anchoring to feet (~3.3× off) or kilometres (1000× off), where
  keeping units ≈ metre and converting at the boundary becomes important.
- Trade-off summary: yard-as-unit buys an honest Imperial internal scale with
  near-zero engine risk; the only cost is that any code cross-checking against
  *real-world SI* (e.g. Earth-accurate gravity, or an enabled Doppler effect)
  must apply the 0.9144 factor. Both are easily handled in a versioned,
  server-owned tuning seam (which the project already mandates) rather than by
  fighting the engine.

## Bottom line / recommendation

- 1 unit = 1 metre is Godot's **documented convention** (gravity "m/s²", camera
  size "in meters", large-world "meters", Jolt "in meters"), but the physics
  integrator is **unit-agnostic** (velocities "in units per second"; gravity is
  data via `gravity_scale × default_gravity`). Nothing forces metres.
- Anchoring **1 unit = 1 yard is safe** for this project: the yard/metre factor
  (0.9144) keeps every meter-tuned default within ~8.6% of intent — negligible.
  Because current movement is custom server integration, the anchor doesn't
  perturb existing behavior at all.
- Do it as a **pure relabel** (keep magnitudes) to preserve current feel. Record
  two SI-reconciliation constants in the versioned tuning seam for the rare
  real-world cross-checks: (1) if Earth-accurate free-fall is ever wanted, use
  `default_gravity ≈ 10.72` (= 9.80665 ÷ 0.9144) instead of 9.8; (2) if 3D audio
  Doppler is ever enabled, remember its speed of sound is the fixed 343-unit
  constant and is not API-rescalable.
- Watch items only if new systems are added later: GodotPhysics3D solver
  thresholds (4.3 default engine), NavigationAgent sizing, and the hard-coded
  Doppler 343 — all tolerate yard scale, none tolerate a large unit change.
