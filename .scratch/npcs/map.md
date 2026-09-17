# Map: Nonplayer Characters

## Destination

Generalize today's always-aggressive Monster into a unified, server-authoritative
**NPC** entity that carries a **disposition** (`HOSTILE` | `PASSIVE`), **moves
when it has no combat target** (no longer static when idle), and shares a
**provisional stat block** (HP-first, a Phase-12 vessel placeholder) with the
Player — so an NPC has "the same stats as the player" by construction. The
destination is a handoff-ready set of decisions (SDD/BDD-shaped), delivered
afterward as bounded SDD/BDD/TDD slices. The map is complete when the disposition
model, non-combat movement, the shared stat block (including giving the Player an
HP pool for the first time), hostile-NPC→Player damage, and passive-NPC spawn
source are each decided well enough to become implementation slices. Generalizes
the resolved [Basic Monsters map](../basic-monsters/map.md) and reopens its "a
monster is always aggressive" assumption. See
[Project Tracker](../../docs/PROJECT-TRACKER.md) and [CLAUDE.md](../../CLAUDE.md).

## What Good Looks Like

- [ ] NPC disposition, including HOSTILE and PASSIVE behavior, is specified without duplicating the monster system.
- [ ] Non-combat movement for NPCs is specified at a server-authoritative public seam.
- [ ] A provisional shared stat block gives both Player and NPC compatible HP-first state without claiming the final vessel system.
- [ ] Hostile NPC damage to Player and passive NPC spawn source are scoped into safe implementation slices.

## Notes

- Domain: server-authoritative non-player behavior, extending the existing
  monster contracts + state machine (`shared/monster_contracts.gd`,
  `server/server_monster_state.gd`, `server/server_monster_manager.gd`) and the
  combat pattern (`shared/combat_contracts.gd`).
- Generalization (Q2): **NPC** is the umbrella entity; **disposition**
  (`HOSTILE` | `PASSIVE`) is the axis; today's Monster becomes the `HOSTILE`
  disposition. Prefer reusing/generalizing the existing state machine over a
  parallel "friendly NPC" system.
- Stats (Q3): a **provisional shared stat block**, HP-first, defined once in
  `shared/` and given to BOTH Player and NPC so "NPC stats == Player stats"
  holds by construction. Explicitly a placeholder for the Phase-12 six-node
  vessel (0% built) — this map does NOT build the vessel. The Player gains an HP
  pool for the first time here (it has none today), which also finally lets a
  hostile NPC's landed attack damage the Player — a gap
  `server/server_monster_state.gd` explicitly calls out.
- Standing constraints (carried from the sibling maps, user direction):
  telemetry-first — every disposition/movement/damage transition emits bounded
  structured telemetry, reusing CLAUDE.md's "Telemetry And Andon Signals" seam;
  every slice follows SDD/BDD/TDD (public-seam failing test first) with focused
  + full GUT validation; always-playable increments.
- Delivery workflow: Copilot owns grilling, domain decisions, scope, acceptance
  criteria, and the implementation handoff; Claude Code CLI owns the code edits
  and executable validation; Copilot reviews the result against the handoff
  before the next decision. No implementation slice starts until its ticket has
  a recorded decision, public seam, non-goals, safety invariants, validation
  command, and handoff brief.
- Godot headless lessons (carried): a new `class_name` script must be reached via
  a `preload` const + `Object` typing, never a bare type annotation; a `.tscn`
  `Transform3D` needs exactly 12 floats.
- Numbering: these are local wayfinder tickets (numbered from `01` in
  `issues/`); implementation slice/feature numbers are allocated later via the
  [SLICE-REGISTRY](../../docs/slices/SLICE-REGISTRY.md), not here.

## Decisions so far

<!-- empty: charting resolves nothing; each closed ticket appends one line here -->

## Not yet specified

- **Client presentation of disposition** — how the client visually distinguishes
  a `HOSTILE` from a `PASSIVE` NPC (nameplate, tint, animation) and how
  disposition replicates to the client. Fog until the disposition model
  (ticket 01) and dynamics (ticket 03) settle: the right cue depends on how many
  dispositions exist and whether they flip.
- **Player death / respawn design** — what happens when the Player's provisional
  HP reaches 0, beyond a bounded placeholder. A system in its own right (respawn
  point, penalty, telemetry); the hostile-damage ticket (05) only pins the
  minimum.
- **Movement fidelity beyond straight-line** — obstacle avoidance /
  `NavigationServer3D` pathfinding around town buildings for wander and chase.
  Fog until the non-combat movement model (ticket 02) picks its baseline; the
  existing chase is deliberately straight-line.
- **Richer disposition / faction model** — neutral-until-provoked tiers,
  factions, dialogue, trading. Beyond the binary `HOSTILE`/`PASSIVE` this map
  commits to; graduates only if a resolved ticket demands it.

## Out of scope

- The full six-node biological vessel (STR/DEX/CON/INT/WIS/CHA) and progression
  (CLAUDE.md Phase 12, 0% built) — this map uses a provisional HP-first stat
  block as a bounded stand-in, never the real vessel.
- A complete Player death / respawn / penalty system (only a bounded placeholder
  is in scope, via ticket 05).
- Loot, drops, rewards, currency, and any NPC "economy".
- NPC dialogue, quests, trading, and faction reputation.
- Multiple hostile archetypes beyond the one baseline monster being generalized.
