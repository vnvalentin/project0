# Goal H Map: Scale and Bounded Simulation Expansion

Status: research-first
Governing issue: [#421](https://github.com/vnvalentin/project0/issues/421)
Research goal: [#204](https://github.com/vnvalentin/project0/issues/204)
Seed issue: [#205](https://github.com/vnvalentin/project0/issues/205)

## Destination

Determine whether measured runtime pressure requires multiple authoritative
simulation boundaries, and if so define ownership, Canon writes, generation
coordination, and Player handoff without weakening server authority.

## What Good Looks Like

- [ ] Measured telemetry identifies a capacity, isolation, or world-size need
  that one authoritative runtime cannot meet acceptably.
- [ ] Sector ownership, process boundaries, and Canon read/write authority are
  explicitly decided.
- [ ] JIT generation queue ownership, duplicate prevention, backpressure, and
  failure recovery are defined across boundaries.
- [ ] Player handoff transfers Character, Vessel, action, cooldown, temporary
  effect, and progression state atomically and idempotently.
- [ ] Time and tick semantics across simulation boundaries are defined.
- [ ] A researched decision and ADR exist before any implementation feature or
  slice is allocated.

## Existing questions

The seed research issue identifies generation ownership, the single scarce
inference resource, single-writer Canon constraints, atomic Player handoff, and
cross-process tick translation as unresolved.

## Non-goals

- No sharding implementation yet.
- No process split based on analogy alone.
- No storage migration or multi-writer Canon decision without evidence and a
  separate ADR.
