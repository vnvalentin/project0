# Goal F Map: Player-Shaped World

Status: chartering
Governing issue: [#421](https://github.com/vnvalentin/project0/issues/421)

## Destination

Define how Players and Parties claim, build, modify, share, repair, abandon,
and govern persistent homes, structures, settlements, and towns without losing
Canon integrity or generated-world continuity.

## What Good Looks Like

- [ ] Home, Structure, settlement, and town ownership and permission models are
  explicit for Characters, Parties, factions, and public spaces.
- [ ] Construction placement, occupancy, spatial validation, access, navigation,
  collision, and revision behavior are defined.
- [ ] Materials, crafting, workshops, Party facilities, costs, failure, repair,
  abandonment, and rollback have clear ownership rules.
- [ ] Generated content and player construction compose without later generation
  overwriting accepted player history.
- [ ] NPCs, services, factions, quests, trade, and settlement growth responses
  are bounded and observable.
- [ ] A fixture-backed construction prototype validates one persistent player or
  Party place before implementation features or slices are allocated.
- [ ] A handoff-ready spec and ADR exist for irreversible ownership and Canon
  decisions.

## Dependencies

This map depends on Goal C item/material/crafting contracts, Goal D Party
ownership and shared facilities, Goal E semantic world proposals, existing
Canon mutation and revision rules, and a resolved spatial indexing contract.

## Decision questions

- Is a place owned by a Character, Party, faction, or explicit public trust?
- Which construction changes are personal, regional, or global World events?
- How are conflicts, permissions, demolition, abandonment, and recovery handled?
- What minimum builder representation persists independently of the renderer?
- When does a home become a settlement or town with NPC and faction effects?

## Non-goals

- No construction feature ID or implementation slice yet.
- No editor, renderer, asset pack, database, or networking technology choice.
- No town economy, governance, or full settlement simulation before the domain
  contract is resolved.
