# Slice 191 - Normalized World directive validator

GitHub issue: #517

Status: **in progress**

Phase: 19 (Semantic world pipeline)

Feature: [F-040](../FEATURE-LIST.md#f-040-server-only-normalized-world-directive-validation)

## Outcome

The authoritative server validates raw World DM/LLM proposals into bounded,
version-pinned normalized directives or a deterministic fallback before a
deterministic builder can consume them.

## Public seam

`server/world_directive_validator.gd::WorldDirectiveValidator.validate`

The pure seam accepts a raw proposal and caller-owned fallback. It reads no
clock, filesystem, LLM, persistence, or runtime state and returns either an
accepted normalized directive or a whole-proposal fallback result.

## Scope and non-goals

In scope: schema/version pins, registered semantic vocabularies, bounded
density/threat bands, palette and atmosphere tags, narrative POI predicates,
narrative text, context references, and rejection reasons.

Out of scope: inference scheduling, deterministic building, Canon mutation,
persistence, arbitration, and frame-critical integration.

## Validation

- Validator parse check passed.
- Focused GUT: 4/4 tests, 10 assertions.
- Full repository GUT remains broader follow-up validation and is not used as
  slice evidence because it contains unrelated existing failures.

## Root-cause learning

No unexpected runtime failure occurred in this increment.