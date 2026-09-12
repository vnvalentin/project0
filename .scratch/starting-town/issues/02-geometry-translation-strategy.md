Type: grilling
Status: resolved

## Question

How does a validated sector blueprint's tiles and structure/spawn-point
entities become actual 3D scene geometry — procedural per-tile mesh
generation (extending the existing `FlatPlane`/`BoxMesh` approach in
`client/gameplay.tscn`) vs. instancing authored prefab scenes per structure
`kind` (mirroring how `client/target_dummy.tscn` is instanced today) — and
where does that translation seam live (a new server-side data step vs. a
client-side rendering step)? CLAUDE.md currently treats geometry translation
as fully unimplemented, so this ticket picks the first real approach.
