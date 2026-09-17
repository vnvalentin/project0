# Slice 029: Authoritative monster melee damage and death broadcast
GitHub issue: #95

Tracker context: Phase 12 — Authoritative runtime and action input; advances
[IP-023](../FEATURE-LIST.md#ip-023-basic-monster-combat). Fourth Basic
Monsters slice; the server-authoritative half of the two-slice boundary
recorded in
[Slice 022's "next boundary"](022-monster-spawning-and-respawn.md#explicit-non-goals-and-next-boundary)
(making monsters visible to and fightable by players). Client rendering is the
separate follow-up, Slice 030 — out of scope here.

## SDD

Goal: wire a player's already-accepted authoritative ACTIVE-phase melee hit to
monster damage and death, reusing the existing `CombatEvent` broadcast channel
so a later client-rendering slice can react, without letting `ServerPlayerState`
mutate monster state directly.

Public seams:

- `server/server_monster_manager.gd` — two additions:
  - `living_targets() -> Dictionary`: every currently living monster keyed by
    `spawn_id`, rebuilt fresh on every call (never cached), so a dead/respawning
    monster is never returned and therefore never targetable.
  - `receive_player_hit(target_id: String, attacker_peer_id: int, server_tick: int) -> bool`:
    the sole seam that applies a player's accepted hit to a monster, via the
    monster's own existing `receive_damage`. Returns `true` only on the tick
    this hit defeats a still-living monster; a no-op (returns `false`) for an
    unknown `target_id` or an already-dead/respawning monster. This keeps
    monster mutation single-owned by `ServerMonsterManager`, per `CLAUDE.md`'s
    "server owns outcomes" rule.
- `server/server_player_state.gd`:
  - `_target_dummies` and the new `_monster_manager` (set via
    `set_monster_manager(monster_manager)`) are both consulted by
    `_perform_hit_test()`. The hit test's target type is generalized from a
    strict `Node3D` to `Object` (duck-typed on `.position`), since a living
    monster is a `RefCounted` `ServerMonsterState`, not a `Node3D`. Each ACTIVE
    tick, the test merges the dummy dictionary with a fresh
    `_monster_manager.living_targets()` snapshot before running the existing
    reach/arc/dedup/max_targets logic unchanged — so a dead monster (absent
    from that snapshot) is invisible to the test.
  - `ServerPlayerState` still never applies damage or decides death; it only
    resolves geometry and emits the existing `COMBAT_EVENT_HIT`
    `combat_event_emitted` signal, exactly as it already does for dummies.
- `server/server_main.gd` — `_on_peer_connected` now also calls
  `player_state.set_monster_manager(_monster_manager)` alongside the existing
  `set_target_dummies` call. `_on_player_state_combat_event_emitted` (the
  existing HIT-broadcast handler) is extended: after broadcasting the HIT it
  received, if the event's `kind` is `COMBAT_EVENT_HIT` and a monster manager
  exists, it calls `_monster_manager.receive_player_hit(...)`; if that returns
  `true`, it constructs and broadcasts a second, attacker-attributed
  `COMBAT_EVENT_DEATH` over the exact same `receive_combat_event` RPC path (via
  a new small `_broadcast_combat_event` helper factored out of the existing
  broadcast loop, so HIT and DEATH share one implementation instead of a
  parallel channel).

Implementation decisions:

- **Injection over polling, snapshot over cache**: rather than push a
  per-frame monster-position dictionary into `ServerPlayerState` (which would
  require `server_main.gd` to rebuild and re-inject it every physics frame),
  `ServerPlayerState` holds a reference to the manager itself and asks for
  `living_targets()` only when it actually runs the ACTIVE-phase hit test. This
  is simpler than a push model and cannot go stale, because a manager query is
  the source of truth at the instant of the swing.
- **Duck-typed hit test, no proxy nodes**: rather than create a `Node3D` proxy
  per monster (extra bookkeeping to keep a proxy's position synced with the
  authoritative `ServerMonsterState.position` every tick, plus a second place a
  monster's identity could drift from its authoritative state), the hit test's
  type annotation was loosened from `Node3D` to `Object`. `CombatContracts.is_within_reach_and_arc`
  already only reads `.position` off the target's *value* (not off the
  parameter, which was always the resolved `Vector3`, not the node) — the
  actual per-target field ServerPlayerState reads is `target.position`, which
  both `Node3D` and `ServerMonsterState` expose identically. No shared base
  class or interface was needed.
- **Damage application stays in `ServerMonsterManager`, routed by `server_main.gd`,
  never in `ServerPlayerState`**: this preserves CLAUDE.md's single-owner rule
  for monster mutation. `ServerPlayerState` is the geometry/timing authority for
  a swing; `ServerMonsterManager` is the sole authority for monster HP/death.
  `server_main.gd`'s existing `combat_event_emitted` → `receive_combat_event`
  relay is the natural seam to bridge the two without a new signal or a new
  cross-reference between the two state owners.
- **Exactly-once death via the existing `apply_damage` 0-HP-transition
  contract**: `MonsterContracts.MonsterCombatState.apply_damage` (Slice 020)
  already returns `true` only on the transition to 0 HP, and
  `ServerMonsterState.receive_damage` (Slice 021) already no-ops on a `DEAD`
  monster and emits `died` exactly once. `receive_player_hit` reuses both
  unchanged; it does not reimplement HP or death logic, it only routes to it
  and reports the outcome via its own return value (checking `is_dead()` before
  and after the call, since `receive_damage` itself does not return a value).
- **No double-apply within one ACTIVE swing**: unchanged from Slice 012 — the
  per-swing `_hit_target_ids_this_swing` dedup and `max_targets` bound already
  guarantee a given `target_id` (monster or dummy) is hit at most once per
  swing; Slice 029 adds no new dedup logic because none was needed.

## BDD

### A landed hit damages a living monster

Given a living monster within an accepted swing's reach and arc
When the ACTIVE-phase hit test runs
Then the server emits one `COMBAT_EVENT_HIT` naming the monster's `target_id`
and applies exactly `MonsterContracts.DAMAGE_PER_HIT` to it.

### Three hits defeat a monster with one attributed death

Given a full-HP monster hit three separate times by the same attacking peer
When the third hit lands
Then the monster transitions to dead exactly once, and exactly one
attacker-attributed `COMBAT_EVENT_DEATH` is broadcast alongside that hit's
`COMBAT_EVENT_HIT`.

### A dead or respawning monster is not targetable

Given a monster that has already died and not yet respawned
When a player's swing would otherwise reach its last known position
Then the hit test finds no target there (it is absent from
`living_targets()`) and no event or damage occurs.

### One ACTIVE swing cannot double-apply damage

Given a monster within reach/arc for an entire multi-tick ACTIVE window
When the swing's ACTIVE phase advances across all of its ticks
Then only one `COMBAT_EVENT_HIT` is emitted and only one `DAMAGE_PER_HIT` is
applied for that swing.

### Target dummies are unaffected

Given a target dummy and a monster manager both registered on the same
`ServerPlayerState`
When a swing lands on the dummy
Then the dummy is hit exactly as before Slice 029, regardless of the monster
manager's presence or the monster's distance.

## TDD evidence

- `tests/unit/test_server_monster_manager.gd` (4 new tests, 11 total):
  `living_targets` includes a living monster and excludes one that has died and
  been cleared from its slot; `receive_player_hit` applies `DAMAGE_PER_HIT` and
  reports no death on hits 1–2 but `true` on hit 3; a hit on an already-dead
  monster is a no-op; a hit on an unknown or respawning (slotted-null)
  `target_id` is a no-op.
- `tests/integration/test_authoritative_melee_strike.gd` (5 new tests, 9
  total): a landed hit within reach/arc damages a living monster injected via
  `set_monster_manager` exactly as `server_main.gd` wires it; three swings
  defeat a monster with exactly one attacker-attributed `COMBAT_EVENT_DEATH`;
  a dead/respawning monster is invisible to a later swing; one multi-tick
  ACTIVE window does not double-apply damage to a monster; and the pre-existing
  target-dummy hit behavior is unchanged with a monster manager also present
  (regression coverage for the generalized hit test).

## ADR decision

No new ADR. This slice wires an existing authoritative hit-test seam
(Slice 012) to an existing monster damage/death seam (Slice 020/021) through
the existing combat-event broadcast channel (Slice 012); it introduces no new
authority boundary, network message shape, or persistence concern beyond what
[ADR 0002](../adr/0002-authoritative-mechanics-and-progression.md) already
covers.

## Validation

- `godot --headless --path . --check-only -s res://server/server_player_state.gd`: exit 0.
- `godot --headless --path . --check-only -s res://server/server_monster_manager.gd`: exit 0.
- `godot --headless --path . --check-only -s res://server/server_main.gd`: exit 0.
- `godot --headless --path . --check-only -s res://tests/unit/test_server_monster_manager.gd`: exit 0.
- `godot --headless --path . --check-only -s res://tests/integration/test_authoritative_melee_strike.gd`: exit 0.
- `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gselect=test_server_monster_manager -gexit`:
  PASS, 11/11 tests, 148 asserts, exit 0.
- `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/integration -gselect=test_authoritative_melee_strike -gexit`:
  PASS, 9/9 tests, 28 asserts, exit 0.
- `scripts/run_gut_validation.sh`: PASS, 177/177 tests, 22 scripts, 736
  asserts, exit 0 (includes substantial unrelated concurrent work already in
  the tree — organic-village, wireguard, ci/ — plus this slice's additions; no
  silently skipped script).

## Explicit non-goals and next boundary

This slice does not render monsters, their damage reactions, or their death on
the client — that is Slice 030 in full. It adds no monster-to-player damage,
no player HP, no loot, no pathfinding, no destructible spawner, and no new
monster archetype. `ServerPlayerState` still cannot name a target or decide an
outcome; it only resolves geometry and reports what the server observed. With
this slice, a player's authoritative hit can defeat a monster end-to-end on the
server and the outcome is already broadcast over the existing combat-event
channel — Slice 030's remaining work is purely client-side: rendering the
monster, and reacting to the `HIT`/`DEATH` events this slice now produces for
it.
