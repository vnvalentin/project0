Type: grilling
Status: unclaimed
Blocked by: None

## Question

Define the **provisional stat block** that BOTH the Player and every NPC carry
(map Q3), so "NPC stats == Player stats" holds today without building the
Phase-12 vessel. Resolve with `domain-modeling` + `grilling`:

- **Contents.** HP-first: just an HP pool, or HP + move speed + reach? Keep to
  the smallest set with real gameplay meaning **now** — extra fields are
  speculative structure until the vessel exists.
- **Where it lives.** A new `shared/` contract shape. Does it reuse the
  Character's existing nullable `vessel_seam` (`shared/character_record.gd`,
  which deliberately holds no Phase-12 values), or is it a separate runtime
  concept layered over both Player and NPC? Note: the Player currently has **no
  HP at all** — this ticket is what first gives the Player an HP pool.
- **Defaults.** A single shared default seed applied identically to Player and
  NPC. The Monster's existing `MonsterContracts.MAX_HP = 30` is the obvious
  candidate. Explicitly flag the whole block as a Phase-12 vessel placeholder
  (mirroring how `monster_contracts.gd` already documents its flat pool as
  provisional).
- **Server ownership + replication.** The server owns the block; how it
  replicates so the client can display HP.

Output: the stat-block contract (fields + bounds + default + version) and the
mechanism by which the Player acquires HP — enough for ticket 05
(hostile-NPC → Player damage) to consume.
