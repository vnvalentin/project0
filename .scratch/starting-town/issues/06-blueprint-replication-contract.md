Type: grilling
Status: resolved

## Question

How does the server send a validated sector blueprint (today the hub fixture
held in `server/server_main.gd._starting_town_hub_blueprint`, a schema-v2
Dictionary) to a connecting client so the Slice 015
`client/sector_geometry_translator.gd` can render it — i.e. what is the
server-to-client blueprint replication contract?

This ticket graduated from the Starting Town map's "Not yet specified" fog
(surfaced while resolving ticket 02). It is the last dependency gating a
visible, end-to-end starting town.

Sub-questions to resolve:
- RPC shape: reuse the existing `@rpc("authority","call_remote","reliable")`
  pattern (server calls a new method on each client's `NetworkClient`
  autoload, as with `spawn_own_player_representation` /
  `spawn_remote_player_representation`)? What payload type — the raw
  Dictionary, or a bounded serialized form?
- When is it sent: to each peer on connect (before/after the existing
  player-spawn RPCs), once at connect only?
- Client-side trust: the client re-validates the received blueprint through
  `SectorBlueprintSchema.validate()` before translating, or trusts the
  server (which already validated it at boot)?
- Where the translation is invoked on the client, and into which scene
  parent, without disturbing the existing `Gameplay`/`FlatPlane` scene.
- Failure/partial-transfer handling (the map fog explicitly named
  partial-blueprint / mid-transfer disconnect as a concern).
- Telemetry + SDD/BDD/TDD per this map's standing Notes requirements.

## Answer

- **RPC shape & payload**: reuse the existing
  `@rpc("authority","call_remote","reliable")` pattern — the server calls a
  new method (e.g. `receive_sector_blueprint`) on each client's
  `NetworkClient` autoload, exactly like `spawn_own_player_representation`.
  Payload is the raw validated blueprint `Dictionary` sent directly (Godot
  ENet RPC serializes a bounded nested Dictionary/Array of ints/strings
  natively); no JSON-string round-trip, since the schema is already bounded
  (tiles <=512, small structures/spawn_points) and `schema_version` inside the
  Dictionary already provides versioning.
- **When**: once per peer, at the very start of `_on_peer_connected`, BEFORE
  the existing player-spawn RPCs. All are `reliable` so ordering holds; the
  world is built before its occupants, avoiding a flash of players in an empty
  scene.
- **Client-side trust**: the client RE-VALIDATES the received Dictionary
  through `SectorBlueprintSchema.validate()` before translating, upholding
  CLAUDE.md's "untrusted until validated at the boundary" rule (never
  instantiate scene geometry from an unvalidated network payload, regardless
  of source). On a non-`OUTCOME_VALID` result the client logs and renders
  nothing (keeps the existing flat plane), never partial geometry.
- **Where translated / scene parent**: the client invokes the Slice 015
  `client/sector_geometry_translator.gd` into a new dedicated `Node3D` child
  named `SectorGeometry` under the `Gameplay` scene root, leaving `FlatPlane`,
  `Player`, camera, and UI untouched. The existing `FlatPlane` stays for now;
  reconciling flat-plane vs. hub floor is a separate future concern.
- **Failure / partial-transfer**: because this is one bounded `reliable` RPC
  carrying one Dictionary (not a stream), "partial transfer" is not a real
  case — ENet reliable delivers the whole message or the peer disconnects, so
  there is no half-Dictionary. The map's original partial-blueprint fog was
  written before that was settled; it collapses to two clean cases: (a) client
  disconnected mid-connect -> no town (harmless), (b) received Dictionary
  fails re-validation -> log + render nothing. This supersedes the fog note.
- **Telemetry**: server-side structured record on send (peer_id, sector_id);
  client-side structured record on receipt (sector_id, outcome, tile/structure
  counts) — satisfies the map's telemetry-first standing requirement and makes
  replication observable.
- **Testing**: SDD/BDD/TDD per this map's standing Notes — a public-seam
  failing test first, plus a GUT integration test exercising the client's
  `receive_sector_blueprint` re-validate-then-translate path against the hub
  fixture Dictionary in a real SceneTree (asserting a `SectorGeometry` node
  with the expected child count appears), and a rejection test asserting an
  invalid payload renders nothing.
