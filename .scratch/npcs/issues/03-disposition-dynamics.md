Type: grilling
Status: unclaimed
Blocked by: 01

## Question

Is an NPC's disposition **fixed for life**, or can it **change at runtime**?
Resolve with `grilling`:

- **Passive when struck.** When a `PASSIVE` NPC is hit by the Player, does it
  stay passive, **flee**, or **retaliate** (flip to `HOSTILE`)? If it flips, is
  the flip permanent for that NPC's life or does it cool down?
- **Hostile de-aggro.** Does a `HOSTILE` NPC ever return to wander/idle when the
  player leaves its detection radius for a bounded time, or does it chase
  forever once aggroed?
- **State-machine fold-in.** How these rules attach to the existing
  `IDLE → CHASE → WINDUP → ATTACK → RECOVERY` machine
  (`server/server_monster_state.gd`). A `PASSIVE` NPC presumably has no `CHASE`
  path until provoked; a de-aggro adds a `CHASE → IDLE` return. Preserve the
  telegraph/windup-fairness invariant either way (CLAUDE.md Combat Reading).
- **Telemetry.** Disposition-change and aggro/de-aggro transitions must emit
  bounded structured telemetry.

Recommended default: a `PASSIVE` NPC **retaliates** (flips to `HOSTILE`) when
struck — the simplest readable rule and it reuses the whole existing chase/attack
path; a `HOSTILE` NPC **de-aggros** back to wander after a bounded lost-sight
timer. Flee/permanent-vs-cooldown nuances decided here.
