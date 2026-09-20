# DM Guild and Semantic World Pipeline

Status: handoff-ready
Governing issue: [Revisit game vision and establish technology-neutral master delivery charter](https://github.com/vnvalentin/project0/issues/421)

## Destination

Define how World, Party, and Personal Dungeon Master roles provide bounded
semantic context and proposals while deterministic server systems validate and
execute all gameplay truth.

## Scope

This document is the technology-neutral handoff contract for the DM Guild and
semantic-world pipeline. It defines ownership, proposal normalization,
deterministic realization, Canon publication, mutation replay, arbitration, and
multiplayer handoff. It does not select an LLM runtime, model, storage product,
renderer, message bus, or live multi-agent topology.

The contract applies to semantic World blueprints and World directives. It does
not authorize a new runtime path by itself; each implementation capability must
arrive through a bounded slice with public-seam tests and validation evidence.

## Authority Model

The World DM, Party DM, and Personal DM are semantic proposal roles:

- The World DM proposes campaign-, faction-, regional-, and cross-Character
  context.
- The Party DM proposes shared Party objectives, history, relationships, and
  encounters.
- The Personal DM proposes Character-local stories, encounters, and relevant
  locations.

Each role receives least-privilege context for its scope. A proposal may contain
semantic intent, bounded constraints, narrative text, and references to known
entities. No DM may authorize physics, combat, inventory, progression,
persistence, multiplayer truth, or another role's private state.

The authoritative server owns event ordering, validation, deterministic
realization, Canon publication, mutation authorization, Character state,
replay, and peer replication. The client renders server-approved results and
never contacts the LLM or Canon store directly.

## Proposal Pipeline

Every proposal follows this boundary:

```text
raw proposal
  -> schema and invariant validation
  -> normalized, version-pinned directive
  -> deterministic World builder
  -> feasibility validation
  -> atomic Canon publication or bounded fallback
```

The builder never consumes raw LLM output. Invalid, unsupported,
non-finite, contradictory, stale, or out-of-range fields reject the entire
proposal. No partially accepted proposal may mutate gameplay state.

A normalized directive may contain only registered semantic values, including:

- biome or theme enums;
- palette and atmosphere tags;
- bounded density and threat bands;
- registered asset and archetype enums;
- narrative POI requirements and stable semantic IDs;
- bounded narrative text and context references.

The server derives or owns exact seeds, noise frequencies, mesh topology,
collision, navigation, placement coordinates, spawn authority, runtime state,
and mutation effects. A model-suggested physical value is ignored or rejected
unless the contract explicitly defines it as a bounded, versioned semantic
control.

Each accepted directive carries and is pinned to:

- `schema_version`;
- `directive_revision`;
- `builder_version`;
- `tuning_version`;
- `resource_set_version`.

A version mismatch prevents silent regeneration. The server either performs an
explicit, validated migration or keeps the existing Canon authoritative.

## Deterministic Evaluation

World directives are evaluated asynchronously at semantic boundaries such as
Sector entry, campaign milestones, quest milestones, and other authoritative
domain events. They never run in the frame-critical simulation loop.

The server orders candidates by canonical event sequence, explicit policy
priority, source scope, and stable directive ID. The chosen order is persisted
and is identical across restarts and peers. Procedural identity derives from
server-owned immutable inputs:

```text
world seed + canonical Sector coordinate + directive revision + event identity
```

A model-provided seed is only a bounded proposal input and cannot override the
server-owned identity.

Replay identity includes the directive ID, input snapshot hash, contract and
schema versions, builder/tuning/resource versions, canonical event position,
and resulting output hash. Mismatched inputs or versions fail closed.

## World Builder and POI Placement

A World blueprint is an intermediate semantic representation. A deterministic
World builder interprets it into geometry, collision, navigation, entities,
presentation, and runtime state while checking physical feasibility.

Narrative POI requirements compile into terrain predicates. For example,
`HIGHEST_PEAK`, `VALLEY`, and `FLAT_AREA` are deterministic queries over the
candidate Sector, not arbitrary coordinates supplied by a model. The builder
filters and ranks feasible candidates using the canonical seed and stable POI
identity, then selects the same result on replay.

The builder may perform bounded local adjustment, such as a radial flattening
or clearance mask, only within configured radius, slope, material, and safety
limits. If the constraints cannot be satisfied, it rejects the POI or uses a
server-owned fallback placement. It does not deform unrelated terrain or allow
a model to author geometry.

## Canon and Mutation Model

The accepted deterministic Sector base is immutable. Canon publication is an
atomic server-owned operation; a validated proposal is not Canon until that
operation succeeds.

Player and narrative changes are append-only, validated, and idempotent Canon
mutations keyed by Sector, stable entity or POI ID, mutation ID, and base
revision. The effective Sector is reconstructed by replaying mutations in
canonical order. Persisted meshes are never the source of truth.

A builder, tuning, resource, or schema version change does not silently
regenerate Canon or re-query the LLM. An explicit migration is required. Until
migration succeeds, the existing Canon remains authoritative and the mismatch
is observable as a bounded failure.

## Arbitration, Idempotency, and Handoff

One server-authoritative arbiter accepts, orders, or rejects directives. It uses
canonical event sequence, explicit policy priority, and stable directive ID.
An unresolved conflict is rejected for review; no model or client adjudicates.

Directive idempotency uses:

```text
(directive_id, input_snapshot_hash, target_sector, base_revision)
```

Repeating the same tuple returns the original result without a second mutation.
Reusing a directive ID with different inputs, target, or base revision is a
conflict and is rejected.

Accepted directives, event positions, base revisions, effective Canon
revisions, and output hashes are persisted. Restart and replay consume those
records and never call the LLM again.

The server publishes accepted Canon revisions and effective state to interested
peers. A late joiner receives an authoritative snapshot. A Sector transition
uses a server-issued handoff containing the target Sector coordinate, accepted
Canon revision, and relevant server-owned Character state. Clients do not
generate, replay, or arbitrate World state.

## Failure and Fallback Behavior

Inference is asynchronous and bounded. Timeout, unavailable inference, malformed
output, schema failure, unsupported vocabulary, physical infeasibility, stale
revision, and version mismatch are distinct observable outcomes.

For an existing Canon Sector, the last accepted directive and effective Canon
remain authoritative. For a new or unavailable Sector, the server uses a
versioned deterministic fixture or server-owned fallback directive. Fallback
never blocks the multiplayer simulation loop and never partially applies model
output.

Telemetry records outcome class, duration bucket, contract/version identity,
correlation ID, and rejection reason without storing prompts, credentials, or
unbounded narrative content.

## Delivery Handoff

The following implementation slices are intentionally separate:

1. normalized directive schema and validator;
2. deterministic directive identity and event ordering;
3. builder feasibility and deterministic POI candidate selection;
4. Canon mutation and replay integration;
5. directive arbitration and idempotency;
6. authoritative peer snapshot and Sector handoff;
7. fixture-backed end-to-end proofs for accepted, rejected, timed-out, replayed,
   and conflicting proposals.

Each slice must define its public seam, BDD scenarios, failure telemetry,
rollback boundary, and machine-readable validation evidence. No slice may make a
client, LLM, or rendered mesh authoritative.

## Explicit Non-goals

- No model, prompt, vector store, or inference runtime selection.
- No live multi-agent service or cloud dependency.
- No LLM-authored physics, collision, navigation, combat, inventory,
  progression, persistence, or multiplayer truth.
- No frame-critical inference call.
- No persisted terrain mesh as Canon.
- No full quest, dungeon, faction, or content implementation in this handoff.
