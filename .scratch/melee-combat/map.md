Governing issue: [#495](https://github.com/vnvalentin/project0/issues/495)

## Destination

Produce a validated, handoff-ready decision map for the first
server-authoritative melee-combat vertical slice. It starts with unarmed
strikes and a massive heavy weapon whose behavior is meaningfully distinct.

The map is complete when the core melee exchange, action authority and timing,
weapon-archetype model, target-and-hit rule, and first-slice acceptance
boundary are clear enough to create safe implementation tickets.

## What Good Looks Like

- [x] The first melee exchange is server-authoritative and scoped to a reversible public seam.
- [x] Action lifetime, timing, idempotency, and rejection rules are specified.
- [x] A bounded weapon archetype and target/hit rule are specified without inventing full combat content.
- [x] The first implementation slice has acceptance evidence and validation expectations.

## Notes

- Domain: Godot 4 multiplayer action-adventure, server-authoritative gameplay,
  GDScript 2.0 strict typing, 3D 3/4 isometric presentation.
- Consult the `grilling` and `domain-modeling` skills for each decision ticket.
- Existing language: a `Player` is the person-controlled in-world actor. Add
  combat vocabulary to `CONTEXT.md` only when a term is resolved.
- Standing safety constraint: clients may request an action and present local
  feedback, but only the server can accept, resolve, or replicate a combat
  outcome.
- Planning mode: chart decisions and implementation-ready handoffs only. This
  map creates no gameplay code, tests, delivery slices, or feature-status
  changes.
- Tracker: local Markdown issues under `.scratch/melee-combat/issues/`.

## Decisions so far

- [Define first melee exchange](issues/01-define-first-melee-exchange.md): Server validates action intents, transitions through windup/active/recovery, performs reach checks against a stationary Target Dummy, and replicates hit events without damage or health persistence.
- [Set melee action authority and lifetime](issues/02-set-melee-action-authority-and-lifetime.md): Monotonic sequence ordering with idempotent replay and explicit rejection codes; fixed 60Hz tick phase lifecycle (windup/active/recovery); server-enforced movement speed factor per phase; snapshot replication for state and discrete resolution events for hit/action outcomes.
- [Model melee weapon archetypes](issues/03-model-melee-weapon-archetypes.md): Simplified single generic sword archetype (`BASIC_SWORD`: 6-tick windup, 4-tick active, 10-tick recovery, 2.0m reach, 60° arc, 0.5 windup speed factor, 1 target max) defined as a typed data object in `shared/` without complex switching or inventory.
- [Choose first target and hit rule](issues/04-choose-first-target-and-hit-rule.md): Deterministic server-side geometric vector queries (distance <= 2.0m and angle within ±30°) against stationary server-owned target dummies; broadcast CombatEvent.HIT for client visual feedback without mutating persistent health or defeat state.
- [Set first melee slice boundary and evidence](issues/05-set-first-melee-slice-boundary-and-evidence.md): Bounded slice defining `ActionIntent`, 60Hz simulation state machine, generic sword parameters, vector reach/arc queries on stationary TargetDummy, and GUT suite validation (`scripts/run_gut_validation.sh`).

## Not yet specified

- The target's durable consequences of a resolved hit: health, defeat, armor,
  status effects, knockback, stagger, and recovery.
- Exact input bindings, client prediction/presentation, animation, sound, VFX,
  and camera feedback for melee actions.
- Collision/physics representation and world geometry needed for production hit
  detection.
- Equipment, inventory, loot, progression, balance, combos, stamina, blocking,
  parries, and weapon switching.
- Hostile NPC behavior, player-versus-player rules, and multi-target or
  multi-player combat resolution.

## Out of scope

- Ranged, magical, projectile, or AI-directed attacks; this map concerns melee
  only.
- Full combat content, final animation/art/audio production, balancing, and
  production anti-cheat policy.
- SQLite, Canon persistence, generated-sector content, quests, and world
  mutation.
- Container deployment, GPU/inference work, matchmaking, authentication, and
  internet exposure.
