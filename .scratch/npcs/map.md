# Map: Unified Character and NPC Generalization

## Destination

Generalize the current Monster into a server-authoritative NPC while making
Player and NPC two controller modes of the same `Character` entity. Every
Character uses the same six-node vessel, organic development, equipment,
techniques, movement, combat, and persistence contracts. The player is
humanoid in the current game; non-humanoid types are NPC-only. This map is the
Phase 14 foundation for the later Phase 15 biological subsystems.

## What Good Looks Like

- [x] Player and NPC share one Character state model; controller type is
      separate from alignment and decision-time disposition.
- [x] A humanoid player starts from the same fixed balanced six-node baseline
      as every Character, with uncapped organic development layered above it.
- [x] Practice, techniques, equipment, and status effects use explicit,
      server-authoritative contracts without exposing hidden numeric stats.
- [x] NPC activities, off-screen simulation, relevance transitions, and
      route-consistent arrivals preserve Character continuity.
- [x] Hostile NPC combat uses the same damage, health, defeat, and recovery
      rules as player combat; no generic injury subsystem is introduced.
- [x] Fixed anchors, population pressure, delayed replacement, and emergent
      NPC significance produce a persistent-feeling world without recycling
      identities silently.

## Resolved Decisions

The following frontier decisions were charted through the Phase 14 wayfinder
issue [#227](https://github.com/vnvalentin/project0/issues/227):

- [#228](https://github.com/vnvalentin/project0/issues/228) — disposition uses
  continuous morality/chaos axes, narrative labels may deceive, relationships
  and context drive decision-time disposition, and hidden details remain
  server-authoritative.
- [#235](https://github.com/vnvalentin/project0/issues/235) — the player is
  humanoid; non-humanoid types are NPC-only; future playable races are out of
  current scope.
- [#230](https://github.com/vnvalentin/project0/issues/230) — fixed balanced
  six-node baseline plus uncapped organic development; weighted continuous
  activity growth; multidimensional techniques; persistent skills; visible
  technique percentages; spider graph and technique relationship map.
- [#233](https://github.com/vnvalentin/project0/issues/233) — mundane and
  magical fixed-effect items, fixed equipment slots, free swapping, default
  tradeability, no degradation, and separate item/class proficiency scales.
- [#234](https://github.com/vnvalentin/project0/issues/234) — techniques are
  taught, discovered, practiced, and combined; failure teaches; pre-mastery
  proficiency decays; 100% mastery makes knowledge permanent; mastered
  Characters can teach willing learners.
- [#229](https://github.com/vnvalentin/project0/issues/229) — activity-driven
  NPC movement with idle/patrol fallback, off-screen simulation, visible
  route-consistent arrival, interruptible routines, and activity-scoped
  following.
- [#231](https://github.com/vnvalentin/project0/issues/231) — shared attack,
  damage, health, defeat, and recovery rules; deliberate magical or impairment
  status effects are resistible/removable; ordinary hits do not cause injury.
- [#232](https://github.com/vnvalentin/project0/issues/232) — fixed anchors and
  activity-driven population, delayed pressure-based replacement, new
  identities, contextual generation, and silent promotion of ambient NPCs.

## Dependencies

- Existing Character account/world-entry records and server-authoritative
  combat/movement seams.
- [ADR 0006](../../docs/adr/0006-versioned-embodiment-mechanics-architecture.md)
  for versioned tuning, baseline vessel derivation, and future Phase 15
  subsystem layering.
- Phase 14 must establish the shared Character/progression seam before Phase
  15 implements kinetic, friction, Meridian, Burnout, and magic layers.

## Explicit Non-Goals

- Playing as a non-humanoid character or implementing a humanoid race catalog.
- Magical item evolution, awakening, or transformation.
- Player-authored technique invention; Phase 14 supports discovery and mastery
  of defined combinations only.
- A generic injury system caused by ordinary damage.
- Automatic respawn of named or story-critical NPCs, reincarnation, or memory
  transfer.
- Replacing the authoritative server with client-authored outcomes.

## Implementation Handoff Requirements

Every implementation slice must name its public server seam, falsifiable
hypothesis, SDD/BDD/TDD acceptance criteria, non-goals, safety invariants,
validation command, telemetry evidence, and review outcome. Slices must reuse
the unified Character model, remain always-playable, preserve hidden server
state, and update the Feature List, Project Tracker, and technical-debt record
when scope or status changes. No slice is complete from passing code alone.

## Status

The design map is charted. Implementation begins with the records-first
handoff in [Slice 116](../../docs/slices/116-phase14-character-foundation-handoff.md)
under [F-036](../../docs/FEATURE-LIST.md#f-036-phase-14-unified-character-and-npc-generalization).
