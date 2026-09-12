---
status: accepted
---

# Authoritative mechanics and progression ownership

## Context

Project0 combines responsive action combat, an interconnected biological
progression graph, temporary kinetic states, magic tradeoffs, and persistent
generated world Canon. Without one ownership rule, individual slices could
accidentally let clients award progression, overwrite base stats with temporary
effects, gate puzzle reasoning, or persist untrusted LLM output.

## Decision

The headless server is authoritative for action acceptance and resolution,
progression evidence, vessel redistribution, derived modifiers, Meridian
unlocks, Burnout, magic channel outcomes, and Canon mutations. Clients may
predict presentation and reversible motion but never commit outcomes.

The six persistent vessel attributes are STR, DEX, CON, INT, WIS, and CHA.
`MET` is derived Metabolism, not a seventh vessel attribute. Mental Focus is a
separate derived value. Neither INT, WIS, Perception, Metabolism, nor Mental
Focus may determine puzzle correctness; they may only modify physical
affordances, authored sensory presentation, and execution timing after a valid
solution or action has been identified.

Human observation, enemy-telegraph recognition, positioning, and deduction are
the Mind domain. Character attributes govern the Tool domain: server-computed
physical execution profiles and bounded presentation modifiers. In combat,
DEX/Metabolism may alter invulnerability frames and slide distance after dodge
input, but no stat decides whether the human recognized an attack or may submit
the action.

Persistent base/progression state is distinct from effective runtime state.
Temporary effects such as Burnout modify derivation output and expiry state,
never the earned base record. All tuning and schema interpretation is versioned
and server-owned.

Ollama output is untrusted provisional data. It becomes Canon only after strict
server validation and a successful atomic write to the server-owned SQLite
store. Later Canon changes require validated physical player-event mutations.

## Consequences

- Every gameplay slice needs an intent-to-authoritative-result seam with
  ownership, ordering, validation, idempotency, and rejection telemetry.
- Clients can remain responsive through prediction, but reconciliation is
  mandatory and predicted outcomes are disposable.
- Balance formulas can evolve in versioned tuning resources without changing
  the stable state ownership contract.
- Progression, combat, magic, persistence, and generated-world slices must test
  their public server seams rather than private calculations.
- The existing `.scratch/melee-combat/` tickets remain unresolved; their future
  decisions must conform to this ADR.
