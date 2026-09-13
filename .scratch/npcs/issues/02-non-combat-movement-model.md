Type: grilling
Status: unclaimed
Blocked by: 01

## Question

Decide how an NPC "moves around" when it has **no combat target** — the user's
explicit "not static" requirement. Today a monster only moves while `CHASE`ing;
`IDLE` is stationary and there is no wander. Resolve with `grilling` (consider a
`prototype` if the feel is the crux):

- **Fidelity.** Bounded idle **wander** (random gentle steps within a radius
  around a home/spawn anchor), waypoint **patrol** (an authored path), or full
  **pathfinding**? The existing chase is deliberately straight-line with no
  obstacle avoidance — does non-combat movement match that, or introduce
  `NavigationServer3D`?
- **Who wanders.** Both dispositions when they have no target, only `PASSIVE`,
  or does a `HOSTILE` NPC also wander before it detects a player (vs. standing at
  spawn until it aggros)? (Depends on the disposition model from ticket 01.)
- **Bounds.** The tuning-shaped constants (wander radius, step cadence/pause,
  wander speed vs. chase speed) as named constants, not magic numbers — matching
  the existing `DETECTION_RADIUS_YARDS` / `CHASE_SPEED_YARDS_PER_SEC` pattern.
- **Containment.** Wander must respect existing spatial rules (e.g. a hostile
  monster's town-exclusion zone; a passive villager staying near its home).
- **Telemetry.** What each movement/idle transition emits.

Recommended default: bounded straight-line idle **wander** within a home radius
for both dispositions when they have no target; `NavigationServer3D`/obstacle
avoidance deferred to fog; wander radius + cadence + speed as named tuning
constants; wander stays within the same containment bounds already enforced for
spawns.
