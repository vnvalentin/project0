# Slice 192 - Deterministic World directive ordering and replay identity

GitHub issue: #521

Status: **in progress**

Phase: 19 (Semantic world pipeline)

Feature: [F-040](../FEATURE-LIST.md#f-040-server-only-normalized-world-directive-validation)

## Outcome

The server deterministically orders accepted World directives and derives a
stable replay identity from server-owned world, sector, revision, event, and
version inputs.

## Public seam

`server/world_directive_ordering.gd::WorldDirectiveOrdering.order` and
`replay_identity` are pure server-side contracts. They consume normalized
directive dictionaries from Slice 191 and do not access persistence, clocks,
LLM services, builders, or runtime state.

## Validation

Focused GUT coverage proves event/priority/scope/ID tie-breaking, stable replay
identity, and rejection of missing identity inputs.