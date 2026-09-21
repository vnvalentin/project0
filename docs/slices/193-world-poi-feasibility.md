# Slice 193 - Deterministic POI feasibility selection

GitHub issue: #525

Status: **delivered**

Phase: 19 (Semantic world pipeline)

Feature: [F-040](../FEATURE-LIST.md#f-040-server-only-normalized-world-directive-validation)

## Outcome

The deterministic World builder boundary evaluates registered POI predicates
against server-owned candidate terrain metadata and selects a stable feasible
candidate or returns an explicit no-feasible-candidate result.

## Public seam

`server/world_poi_selector.gd::WorldPoiSelector.select` is pure and consumes
only bounded candidate metadata. It does not accept model coordinates or mutate
geometry, Canon, persistence, or runtime state.

## Validation

Focused GUT fixtures cover peak, valley, flat-area feasibility, deterministic
ties, malformed candidates, and no-feasible fallback: 5/5 tests and 8
assertions.