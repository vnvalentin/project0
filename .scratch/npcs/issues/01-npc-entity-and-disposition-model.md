Type: grilling
Status: unclaimed
Blocked by: None

## Question

Define the unified **NPC** model that generalizes today's always-aggressive
Monster (map Q2). This is the root ticket — movement (02), dynamics (03), and
spawn source (06) all build on it. Resolve with `domain-modeling` + `grilling`:

- **Contract shape.** Does `shared/monster_contracts.gd` get generalized/renamed
  to an NPC contract (e.g. `shared/npc_contracts.gd`), or does a thin NPC layer
  wrap it? What migrates, and how do the existing Monster references, tests, and
  the CONTEXT.md glossary move **without breaking the resolved Basic Monsters
  behavior** (the `IDLE → CHASE → WINDUP → ATTACK → RECOVERY` machine, spawning,
  respawn, the windup-fairness regression test)?
- **Disposition enum.** Exact values (`HOSTILE`, `PASSIVE`) and the default for
  an NPC that does not specify one. Where the enum lives (shared contract) and
  its bounds/rejection of unknown values.
- **Monster mapping.** Is "Monster" retired as a term (→ "hostile NPC"), kept as
  an alias, or kept as a subtype label? Whichever wins, the CONTEXT.md glossary
  entry is updated on resolution (domain-modeling), since the current entry
  defines Monster as a combat target and avoids "enemy/mob".
- **Server ownership + replication.** Where disposition lives on the server state
  (`server/server_monster_state.gd`) and how it replicates to the client so the
  client can later present it (fog ticket).

Recommended default: generalize `monster_contracts.gd` into an NPC contract that
owns a `disposition` enum (`HOSTILE`/`PASSIVE`, default `HOSTILE` to preserve
current behavior), keep the existing state machine and rename it to an NPC state,
and redefine "Monster" in the glossary as the `HOSTILE` disposition of an NPC
rather than a separate entity.

Output: the NPC/disposition contract (fields + enum + default + bounds), the
Monster-mapping + glossary decision, and the replication seam — enough for
tickets 02, 03, and 06 to consume.
