# Goal D Map: Party Campaign and Shared Encounters

Status: chartering
Governing issue: [#421](https://github.com/vnvalentin/project0/issues/421)
Existing design issue: [#319](https://github.com/vnvalentin/project0/issues/319)

## Destination

Define a persistent Party system in which one to five Characters can form a
consensual cooperative relationship, coordinate shared encounters, preserve
individual authority, and contribute to a long-lived campaign across connected
and asynchronous sessions.

## What Good Looks Like

- [ ] Party membership, presence, consent, leadership, succession, leave,
  removal, disconnect grace, and retirement are explicitly modeled.
- [ ] Shared encounter participation, proximity, contribution evidence, reward
  attribution, and reconnect behavior are decided.
- [ ] Party campaign memory, shared objectives, shared assets, and asynchronous
  downtime have clear ownership boundaries.
- [ ] Combined techniques, mentorship, formation, and Party HUD behavior are
  defined without forking Character or technique contracts.
- [ ] A fixture-backed two-Character prototype validates the public Party seam
  before implementation features or slices are allocated.
- [ ] A handoff-ready spec and ADR exist for any irreversible ownership or
  progression decision.

## Existing evidence

Research is recorded in `research/01-mmo-party-models.md`. Existing Character,
technique, progression, movement, Nakama presence, and authoritative action
seams are upstream inputs, not Party implementation.

## Decision questions

- Which decisions require all active members, leader consent, or no vote?
- How do Party membership and Party presence behave across sectors and sessions?
- What makes a Character an active participant in a shared Encounter?
- Which rewards are personal, Party-owned, or merely shared context?
- How does asynchronous downtime update the Party without silently resolving
  another Character's personal arc?
- How are combined techniques validated and attributed?

## Non-goals

- No Party feature ID or implementation slice yet.
- No conventional shared XP pool.
- No duplicate Character, Vessel, or technique progression model.
- No commitment to a transport, database, or Party DM implementation.
