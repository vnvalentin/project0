# Slice 194 - Deterministic builder feasibility contract

GitHub issue: #528

Status: **delivered**

Phase: 19 (Semantic world pipeline)

Feature: [F-040](../FEATURE-LIST.md#f-040-server-only-normalized-world-directive-validation)

## Outcome

The deterministic World builder boundary checks selected POIs against bounded
slope, clearance, and placement constraints and returns an accepted feasibility
result or a whole-proposal fallback.

## Public seam

`server/world_builder_feasibility.gd::WorldBuilderFeasibility.evaluate` is pure
and server-owned. It does not generate geometry, mutate Canon, persist state,
or access runtime services.

## Validation

Focused GUT fixtures cover accepted feasibility, slope and clearance rejection,
malformed directives, and bounded metric rejection: 4/4 tests and 9 assertions.