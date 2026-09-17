---
status: accepted
---

# Unified Character and NPC generalization

Phase 14 establishes one server-authoritative Character model for the player
and NPCs. It replaces the assumption that Monster is a separate product entity
with controller-driven behavior layered over shared state. The decision is
based on [#227](https://github.com/vnvalentin/project0/issues/227) and its
resolved decisions [#228](https://github.com/vnvalentin/project0/issues/228)
through [#235](https://github.com/vnvalentin/project0/issues/235), and builds
on [ADR 0006](0006-versioned-embodiment-mechanics-architecture.md).

## Decision

### One Character model

Player and NPC are controller modes of one Character entity. Controller type
does not determine alignment or disposition. The current playable character is
humanoid; non-humanoid types are NPC-only. Future humanoid races or playable
non-humanoids are additive possibilities, not Phase 14 scope.

### Baseline and organic development

Every Character starts with the same fixed, balanced six-node baseline:
Strength, Dexterity, Constitution, Intelligence, Wisdom, and Charisma. The
fixed-area vessel governs the creation baseline and its redistribution. A
separate organic-development vector grows continuously through meaningful
activities, can affect multiple nodes at weighted rates, has no hard
player-facing cap, and is shaped by opportunity cost and tuning. Effective
capability combines baseline, organic development, equipment, and active
effects. Numeric stats remain server-authoritative; the client presents a
numberless spider graph whose shape changes over time.

### Techniques and equipment

Techniques use multidimensional readiness rather than a linear skill tree.
Failure teaches. A technique has visible character-specific proficiency from
0% to 100%; pre-mastery proficiency decays without meaningful use, while 100%
makes the technique permanently known. Mastered Characters can teach any
willing learner, but teaching transfers knowledge of the practice sequence, not
stats or mastery. Discovery, hints, and emergent combinations are valid paths.
The client presents learned stat names, a primary-stat spider-graph location,
and a separate mind-map/flowchart of relationships without exposing numeric
stat values or hidden thresholds.

Mundane and magical items are included with fixed effects; magical evolution is
deferred. Equipment has fixed slots, free compatible swapping, default
tradeability, explicit quest/player binding only, and no degradation. Item and
item-class proficiency are separate 0-100 scales, with class knowledge slower
and transferable. Item effectiveness is proficiency-driven; the canonical
giant-sword example ranges from 50% effectiveness when unfamiliar to 150% at
item mastery, with class mastery allowing a 200% ceiling and improved proc.

### NPC simulation and combat

NPC activity is activity-driven with idle/patrol fallback. Distant activity is
simulated off-screen; relevant NPCs materialize through visible,
route-consistent arrival. Routines are interruptible and following is scoped to
a defined activity. NPCs use the same movement, progression, attack, damage,
health, defeat, and recovery contracts as players.

Status effects are explicit magical or impairment capabilities and may be
resisted or removed by cures, magic, or items. Ordinary damage does not create
an injury subsystem.

Spawning combines fixed anchors with activity-driven population. Recovery
preserves identity; delayed population-pressure replacement creates a new
identity. Named/story-critical losses do not automatically respawn. Ambient
replacements inherit broad community/faction context but not individual state,
and an ambient NPC may silently become significant and leave the replacement
pool.

## Consequences

Shared state removes player/NPC duplication and makes NPC progression and
combat subject to the same authority and balance rules. The presentation layer
must distinguish hidden numeric state from visible graph, proficiency, status,
and relationship knowledge. Off-screen simulation and role-based replacement
require durable identity and explicit relevance transitions. Phase 15 may add
its subsystems on top of the baseline without redefining Character.

## Non-goals and follow-up

Playable non-humanoids, race design, magical evolution, authored technique
invention, injury, reincarnation, and memory transfer remain future decisions.
Exact tuning curves, public RPC schemas, and subsystem algorithms belong in
their implementation slice records and must reference this ADR rather than
expanding it.