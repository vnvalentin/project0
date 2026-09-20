---
status: accepted
---

# DM Guild semantic world pipeline

## Context

Project0 uses World, Party, and Personal Dungeon Master roles to propose
semantic context and world changes. The project also requires deterministic
world realization, server-owned Canon, replayable mutations, and multiplayer
consistency. An unconstrained LLM-to-world path would make terrain,
progression, persistence, and peer state nondeterministic and would violate the
server-authority contract.

The DM Guild decision map resolved the missing boundary across [World Director
Tick and Deterministic Ordering](https://github.com/vnvalentin/project0/issues/432),
[Seeded World Directive Contract](https://github.com/vnvalentin/project0/issues/433),
[Narrative POI Anchoring and Persistent Deltas](https://github.com/vnvalentin/project0/issues/434),
and [World Directive Arbitration and Multiplayer Handoff](https://github.com/vnvalentin/project0/issues/435).
The governing planning issue is [Revisit game vision and establish
technology-neutral master delivery charter](https://github.com/vnvalentin/project0/issues/495).

## Decision

Use a deterministic-generative sandwich:

```text
DM proposal -> validation -> normalized directive -> deterministic builder -> Canon
```

DMs may propose bounded semantic values, narrative context, and POI
requirements. The server validates and normalizes those proposals. The
World builder owns exact procedural identity, terrain, collision, navigation,
entity placement, and runtime state. The server owns Canon publication,
mutations, arbitration, replay, and peer handoff.

Directives are evaluated asynchronously at semantic boundaries, ordered by
canonical event sequence, explicit policy priority, and stable directive ID.
Procedural identity derives from server-owned world, Sector, revision, and event
inputs. Replay uses persisted accepted records and version/output hashes; it
never re-queries the LLM.

POIs resolve through deterministic terrain predicates with bounded local
adjustment. Sector bases remain immutable, while validated idempotent mutations
form an append-only Canon history. Conflicts, stale revisions, invalid output,
and version mismatches fail closed. Existing Canon remains authoritative; new or
unavailable content uses a versioned server-owned fixture or fallback.

Peers receive server-issued Canon snapshots and Sector handoffs. Clients and
LLMs never generate, replay, or arbitrate authoritative world state.

## Consequences

- Semantic narrative can vary without changing physical or multiplayer truth.
- The same accepted directive and versions reproduce the same world result.
- Canon can be reconstructed from a compact base plus ordered mutation history.
- Inference failure remains bounded and does not block frame-critical gameplay.
- Every future slice must define schema/version validation, idempotency,
  rejection telemetry, replay behavior, and a machine-readable public-seam
  validation.
- Fixture-backed proofs and implementation slices remain required before this
  design is considered a delivered product capability.
- Model, runtime, storage, renderer, and live multi-agent choices remain open
  and must be decided separately if they become necessary.
