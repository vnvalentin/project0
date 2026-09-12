# Slice 019: Player house allocation

Tracker context: Phase 8 — JIT world generation and local inference; advances
[F-022](../FEATURE-LIST.md#f-022-player-house-allocation).
Planning tickets: [Starting Town map](../../.scratch/starting-town/map.md),
[issue 05 — Player house allocation](../../.scratch/starting-town/issues/05-player-house-allocation.md)
(resolved). This is the last Starting Town map slice.

## SDD

Goal: Assign each connecting peer a unique house from the starting town's fixed
10-house pool, server-authoritatively, freeing the slot immediately on
disconnect; surface the owning peer's assigned house in its HUD. No persistence,
no reconnect reservation, and no change to where the player spawns.

Public seams:

- `server/house_allocator.gd` (`RefCounted`) — the pure allocator.
  `house_ids_from_blueprint(blueprint)` extracts the ordered `house` structure
  ids from a validated hub blueprint. `assign(peer_id)` returns a unique house id
  (first-available, idempotent per peer, `""` when the pool is exhausted).
  `release(peer_id)` frees the slot immediately. `assigned_house`,
  `available_count`, `pool_size` are read accessors. Independent of the
  SceneTree, so fully unit-testable.
- `server/server_main.gd` — builds the allocator from the validated hub
  blueprint at boot; on connect, assigns the peer a house, logs telemetry, and
  RPCs `receive_assigned_house` to that owning client only; on disconnect,
  releases the slot and logs. `get_assigned_house(peer_id)` exposes the current
  assignment.
- `client/network_client.gd` — `receive_assigned_house(house_id)` reliable
  authority RPC that relays via the `assigned_house_received` signal.
- `client/assigned_house_label.gd` + `client/gameplay.tscn` `HouseLabel` — a HUD
  `Label` that shows "Your house: <id>" when the signal fires.

Design decisions:

- **Pool from the fixture**: the 10 houses come straight from the Slice 016 hub
  blueprint (structures with `kind == "house"`), so the pool size and the
  server's `MAX_REPLICATED_PEERS` (10) are the same source-of-truth count.
- **First-available + idempotent**: `assign` returns the first pool id not
  currently held; a peer that already holds a house gets the same one back
  (never a second slot). Exhaustion returns `""`, a fail-closed signal the
  server logs — unreachable in steady state because pool size == max peers, but
  defended anyway per the resolved ticket.
- **Immediate release, no reservation**: on disconnect the slot frees at once
  and the next connecting peer may reuse it. There is no identity/save system to
  recognize a returning player, so reserving would only leak slots as players
  churn (resolves the map's earlier reconnect fog).
- **Scope guard — spawn position unchanged**: this slice does NOT rebind the
  player's spawn/camera to the allocated house position. Doing so would alter
  `_start_position_for_slot` behavior that the movement, prediction, and
  hand-rolled multi-peer smoke scripts depend on; binding spawn-at-house is a
  clean, separately-testable follow-up. The house is authoritatively owned and
  surfaced in the HUD now; relocating the player to it is deferred.
- **Typing note**: `_house_allocator` and the test locals are typed `Object` and
  accessed dynamically, matching this repo's existing script-backed-state
  pattern (`player_state: Node`, `resolution: Object`). A bare `HouseAllocator`
  type annotation fails to resolve under headless class-cache runs, so it is
  avoided; the script is always reached through its preloaded `*Script` const.

## BDD

### Each connecting peer gets a unique house

Given the server has built the house pool from the hub fixture
When peers connect
Then each is assigned a distinct house id, the owning client is told its house
via `receive_assigned_house`, and the assignment is logged.

### A disconnect frees the slot for reuse

Given all houses are assigned
When a peer disconnects
Then its house frees immediately and the next connecting peer may be assigned
that same house (first-available), with no reservation window.

### Allocation is idempotent and fail-closed

Given a peer already holds a house
When it is assigned again
Then it receives the same house and no second slot is consumed; and when the
pool is exhausted, `assign` returns `""` (logged as a defensive error), never a
duplicate or a crash.

### The owning client sees its house

Given the server assigns a house to a peer
When the client receives `receive_assigned_house`
Then its HUD shows "Your house: <id>".

## TDD evidence

- `tests/unit/test_house_allocator.gd` (7 tests, 17 assertions): the hub
  fixture yields exactly 10 unique house ids; distinct peers get distinct
  houses; assign is idempotent per peer (no double-consume); pool exhaustion
  returns `""` and reports zero available; release frees exactly one slot and
  the next assign reuses it (first-available); releasing an unassigned peer is a
  no-op; and `assigned_house` lookup returns the current house or `""`.
- `tests/unit/test_assigned_house_label.gd` (1 test, 2 assertions): the HUD
  handler shows "Your house: <id>" and becomes visible on receipt (tested in
  isolation so its `_ready` autoload wiring, a single signal connection, does
  not run; the wiring itself is covered by the full-suite scene load).

Known coverage note: the live ENet round-trip (server assign → `rpc_id` →
client signal → HUD) is not exercised by a two-process networked test, matching
prior networked slices; the server assign/release logic and the HUD handler are
unit-tested, and the RPC/signal relays are thin.

## ADR decision

No new ADR. Server-authoritative, in-memory, session-scoped allocation over the
existing hub fixture. No persistence, no new authority boundary beyond
`CLAUDE.md`/ADR 0002.

## Validation

- `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit
  -gselect=test_house_allocator -gexit`: PASS, 7/7, 17 assertions, exit 0.
- `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit
  -gselect=test_assigned_house_label -gexit`: PASS, 1/1, 2 assertions, exit 0.
- `scripts/run_gut_validation.sh`: PASS, 117/117 tests, 327 assertions, exit 0.
- `godot --headless --check-only -s server/server_main.gd`,
  `... server/house_allocator.gd`, `... client/network_client.gd`,
  `... client/assigned_house_label.gd`: all exit 0.
- Regression caught and fixed mid-development (Jidoka): an initial bare
  `HouseAllocator` type annotation in `server_main.gd` and the allocator test
  failed to resolve under the headless class cache
  (`Could not find type "HouseAllocator"`), which cascaded into `test_lan_config`
  failures. Corrected to `Object` dynamic access (the repo's established
  pattern); the full suite then returned to green.

## Explicit non-goals and next boundary

This slice does not persist allocations (session-only), does not reserve a house
across reconnects, does not move the player's spawn/camera to the allocated
house (a deferred follow-up), does not mark a player's own house visually
distinct in the world, and adds no economy/inventory. With Starting Town ticket
05 delivered, the entire Starting Town map is implemented end-to-end. The
remaining planned work is the Basic Monsters map (three resolved tickets:
HP/damage/death, monster AI with telegraph, and spawn points) and the optional
spawn-at-house follow-up.
