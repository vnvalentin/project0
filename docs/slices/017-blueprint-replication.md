# Slice 017: Server-to-client blueprint replication

Tracker context: Phase 8 — JIT world generation and local inference; advances
[F-020](../FEATURE-LIST.md#f-020-server-to-client-sector-blueprint-replication).
Planning tickets: [Starting Town map](../../.scratch/starting-town/map.md),
[issue 06 — Blueprint replication contract](../../.scratch/starting-town/issues/06-blueprint-replication-contract.md)
(resolved). This is the last Starting Town ticket; it connects Slice 016 (the
server-held hub fixture) to Slice 015 (the client geometry translator),
producing a visible, end-to-end starting town.

## SDD

Goal: Replicate the validated starting town hub blueprint from the server to
each connecting client and render it, without weakening the client's
input-only / server-authoritative contract, and without adding persistence,
per-player allocation, facade interaction, or monster content.

Public seams:

- `server/server_main.gd` — at the start of `_on_peer_connected` (after the
  capacity check, before the player-spawn RPCs) the server calls
  `receive_sector_blueprint` on the connecting peer's `NetworkClient` with the
  in-memory validated hub Dictionary (`_starting_town_hub_blueprint`, held
  since Slice 016), and logs a send record (`peer_id`, `sector_id`).
- `client/network_client.gd` —
  - `receive_sector_blueprint(blueprint)` `@rpc("authority","call_remote","reliable")`:
    the RPC entry point. Resolves the `Gameplay` scene root, gets/creates a
    dedicated `SectorGeometry` `Node3D` child, delegates to the static render
    seam, logs a receive record, and emits `sector_blueprint_received`.
  - `render_sector_blueprint(blueprint, parent) -> Dictionary` (static): the
    testable seam. Re-validates the payload through
    `SectorBlueprintSchema.validate()` and, only on `OUTCOME_VALID`, calls the
    Slice 015 `SectorGeometryTranslator.translate()` into `parent`. Returns
    `{ outcome, tile_count, structure_count }`. On any non-valid outcome it
    logs and renders nothing.
  - `sector_blueprint_received(sector_id, outcome, tile_count, structure_count)`
    signal: client-side replication telemetry / observability seam, matching
    this file's existing relay-only `receive_*` → signal pattern.
- `tests/integration/test_blueprint_replication.gd` — GUT integration test of
  the static render seam against the real hub fixture in a live SceneTree.

Contract (per resolved ticket 06):

- **RPC shape / payload**: reuses the established
  `@rpc("authority","call_remote","reliable")` pattern; the payload is the raw
  validated blueprint `Dictionary` (Godot ENet RPC serializes the bounded
  nested Dictionary/Array natively — no JSON-string round-trip). Bounds come
  from the schema (`MAX_TILE_COUNT` 512, small structures/spawn_points), and
  `schema_version` inside the Dictionary already provides versioning.
- **When**: once per peer, at connect, before the player-spawn RPCs, so the
  world exists before its occupants. All involved RPCs are `reliable`, so
  ordering holds.
- **Client-side trust**: the client re-validates through the shared schema at
  the boundary before instantiating any geometry (CLAUDE.md: untrusted until
  validated at the boundary — never build scene geometry from an unvalidated
  network payload, regardless of source).
- **Scene parent**: renders into a dedicated `SectorGeometry` child of the
  `Gameplay` root, leaving `FlatPlane`, `Player`, camera, and UI untouched.
- **Failure / partial transfer**: one bounded `reliable` RPC carrying one
  Dictionary means there is no partial-transfer case (ENet reliable delivers
  the whole message or the peer disconnects). Failure reduces to: (a) peer
  disconnected mid-connect → no town (harmless); (b) payload fails
  re-validation → log + render nothing, never partial geometry.

Implementation decisions:

- The render logic is a **static, parent-injected** function
  (`render_sector_blueprint`) separated from the RPC entry point, so it is
  unit-testable without a live multiplayer peer, `current_scene`, or a
  `NetworkClient` instance. The RPC wrapper is a thin adapter that supplies the
  real scene container and emits the observability signal from the returned
  counts.
- Telemetry uses `print()` on both send (server) and receive (client), matching
  the repository's existing server/client log convention (e.g. "Peer connected",
  "Server listening on ..."), plus the `sector_blueprint_received` signal for a
  future HUD.

## BDD

### A connecting client renders the hub

Given the server has materialized and is holding the validated hub blueprint
(Slice 016)
When a client connects
Then the server sends the blueprint to that client before spawning any Player,
and the client re-validates it and renders one geometry node per tile and per
structure under a dedicated `SectorGeometry` node, without disturbing the
existing `FlatPlane`/`Player`/UI.

### An invalid payload renders nothing

Given a received blueprint that fails schema re-validation (e.g. an unsupported
structure kind, or missing required fields)
When the client processes it
Then it logs the rejection and renders no geometry at all (fail closed, never
partial), and reports a non-valid outcome with zero rendered counts.

### World built before occupants

Given a client connecting to a server with existing peers
When the connect RPCs are delivered
Then the blueprint RPC precedes the player-spawn RPCs, so the town exists
before any Player representation appears in it (guaranteed by reliable
ordering).

## TDD evidence

`tests/integration/test_blueprint_replication.gd` (4 tests, 14 assertions)
exercises the static `render_sector_blueprint` seam in a real SceneTree/Node3D:
the real hub fixture renders all 289 tiles + 13 structures (302 children) and
reports matching counts with `OUTCOME_VALID`; the four named structure nodes
(`Structure_house_01`, `Structure_smithy_01`, `Structure_armor_shop_01`,
`Structure_inn_01`) are present; a corrupted blueprint (unsupported structure
kind) renders zero children with a non-valid outcome; and a blueprint missing
required top-level fields likewise renders nothing.

Known coverage note: the live end-to-end ENet round-trip (server
`rpc_id(...,"receive_sector_blueprint",...)` → client RPC handler → render) is
not exercised by a two-process networked test; the RPC entry point is a thin
adapter over the unit-tested static render seam plus the already-proven Slice
015 translator, so the untested surface is limited to `get_tree().current_scene`
resolution and the container node creation. Physical two-machine confirmation is
deferred to manual/LAN verification like prior networked slices.

## ADR decision

No new ADR. This slice adds a one-way, reliable, server→client replication of
already-server-validated, re-validated-on-receipt data into a presentational
scene container. It introduces no new authority boundary (the client still owns
no world state), no persistence, and no client-authored outcome beyond what
`CLAUDE.md` and ADR 0001/0002 already establish.

## Validation

- `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/integration
  -gselect=test_blueprint_replication -gexit`: PASS, 4/4 tests, 14 assertions,
  exit 0.
- `scripts/run_gut_validation.sh`: PASS, 100/100 tests, 287 assertions, exit 0;
  telemetry written to `build/validation/gut.xml` and
  `build/validation/validation-summary.json`. Prior Phase 8 suites (Slices 008,
  009, 014, 015, 016) pass unchanged, confirming no regression. (The
  "Parameter m is null" / "Parse JSON failed" lines are the pre-existing
  expected error-path output from malformed-JSON contract tests, not failures.)
- `godot --headless --check-only -s client/network_client.gd` and
  `... -s server/server_main.gd`: both exit 0 (clean parse/type check under
  strict GDScript 2.0 typing).

## Explicit non-goals and next boundary

This slice does not persist the hub (no SQLite/Canon), does not allocate
per-player houses (the 10-house pool renders for everyone; claiming is a future
slice), does not add facade `Area3D`/enter-exit interaction, adds no
monster/spawn content, and does not reconcile the existing `FlatPlane` against
the hub floor (both render; deduplication is a later concern). With the Starting
Town map now fully implemented end-to-end, the next boundaries are the map's
remaining future slices — facade enter/exit (ticket 04), player house allocation
(ticket 05) — and, independently, the Basic Monsters map.
