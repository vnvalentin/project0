Type: grilling
Status: unclaimed
Blocked by: None

## Question

Give each structure kind a **footprint** so overlap and on-valid-tile placement
become checkable (strategy ticket 01, decision 2). This is the keystone the
repair pass (ticket 03) depends on. Resolve with `domain-modeling` + `grilling`:

- **Representation.** Per-kind axis-aligned rectangle in tile units
  (`width_x` x `depth_y`); per-kind radius (cheapest overlap test:
  distance < r1 + r2); or an explicit occupied tile-cell set (most precise,
  snaps to the tile grid). Recommended default: per-kind rectangle in tile
  units, grid-snapped, with a configurable inter-structure margin.
- **Rotation.** Does the footprint rotate with `facing_degrees`
  (0/90/180/270 swaps width/depth; arbitrary angles use the bounding box), or
  stay axis-aligned regardless of facing?
- **Where the values live.** A new server-owned, version-tagged tuning resource
  (a `shared/` contract shape + `server/` values) so footprints are inspectable
  and versioned — never magic numbers scattered in placement code.
- **Consistency with rendering.** The tuned footprint MUST match or exceed the
  geometry translator's fixed-size prefab extent per kind, so what the server
  validates equals what the client draws (no "validated but visually
  overlapping"). Cross-reference the existing per-kind prefabs.

Output: the footprint contract (fields + bounds + schema/tuning version), the
per-kind values, and the rotation/margin rules — enough for ticket 03 to
consume.
