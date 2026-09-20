# Slice 095 — Canon entity GUIDs + mutation target-existence enforcement
GitHub issue: #95

Status: **delivered**

Phase: 9 (Canon persistence and world mutation), advancing
[P-013](../FEATURE-LIST.md#p-013-dynamic-world-mutation-tracking). This is the
second P-013 slice, building directly on the Slice 050 append-only mutation log
and the Slice 045 immutable Canon sectors.

## User outcome

When a player-driven change targets a specific thing in a canonical sector (a
particular building, the village hall, a spawn marker), the server addresses
that thing by a **stable identity that is the same every session** and refuses a
mutation aimed at a target that does not exist in that sector's Canon. A forged
or mistyped `target_guid` can no longer be recorded against the world.

## Scope and non-goals

In scope:

- A server-owned, deterministic, restart-stable GUID for every addressable
  entity in a canonical blueprint (its structures and spawn markers), derived
  purely from the sector id, the entity class, and the entity's own
  blueprint-unique id. Same blueprint → same GUIDs, forever, with no stored GUID
  column to drift.
- Enforcing the `CanonMutationEvent` rule "the server MUST verify the target
  exists" (`CLAUDE.md`): `CanonMutationRepository.apply_mutation` now rejects a
  mutation whose `target_guid` is not one of the target sector's canonical
  entity GUIDs, with a new `target_not_found` outcome, before any write.

Out of scope (later P-013 / other slices): proving the physical game event
actually occurred, gameplay authorization of the actor, the network DTO/RPC that
carries a mutation intent from a client to the server, mutation replay into live
scene state, and mutation telemetry. The immutable `canon_sectors` table
(Slice 045) and the append-only `canon_mutations` log (Slice 050) are unchanged
in shape; only the mutation admission check is tightened.

## Public seam

`shared/canon_entity_guid.gd` (`class_name CanonEntityGuid`) — a pure,
deterministic, dependency-free helper (no store, no HTTP, no async), so it is
unit-testable with plain Dictionaries and lives in `shared/` per `CLAUDE.md`:

- `derive(sector_id, entity_class, entity_id) -> String` — the stable GUID for
  one entity. Deterministic and version-independent: a SHA-256 digest of the
  canonical `(sector_id, entity_class, entity_id)` tuple, prefixed with the
  entity class for debuggability and bounded to a fixed length well under the
  mutation log's `MAX_ID_LENGTH`.
- `list_entities(blueprint) -> Array` — every addressable entity in a validated
  blueprint (`structures` keyed by `structure_id`, `spawn_points` keyed by
  `spawn_id`), each as `{guid, entity_class, entity_id, kind}`.
- `contains_guid(blueprint, guid) -> bool` — whether a GUID addresses a real
  entity in that blueprint.

`server/canon_mutation_repository.gd` — after confirming the target sector is
Canon, `apply_mutation` loads that sector's canonical blueprint and rejects the
event with `OUTCOME_TARGET_NOT_FOUND` when `target_guid` is not a canonical
entity GUID, before the idempotency, revision, and insert steps.

## Safety invariants

- **Stable:** `derive` is a pure function of the tuple only — no clock, no
  randomness, no stored column — so a GUID is identical across restarts and
  across re-derivation from the immutable blueprint. SHA-256 keeps it stable
  across Godot versions too (unlike the engine's `hash()`).
- **Fail-closed:** a mutation against a non-existent target is rejected
  (`target_not_found`) with no write; this composes with the existing
  `sector_not_canon`, `revision_mismatch`, `conflict`, and `invalid_event`
  guards.
- **Idempotent-preserving:** because blueprints are immutable, a genuine replay
  of a previously-applied mutation still resolves to the same existing target
  and remains `idempotent`.
- **Server-only enforcement, shared derivation:** the GUID *algorithm* is pure
  and shared (both processes must agree on identity), but the *admission check*
  and the store remain server-only; `shared/canon_entity_guid.gd` references no
  store, client, or server-only type.

## ADR rationale

No new ADR. Stable server-owned identity for world entities and the
"server MUST verify the target exists" rule are already normative in `CLAUDE.md`
(`CanonMutationEvent`, the `CANON -> MUTATION_VALIDATING -> CANON` lifecycle).
This slice implements the identity + existence check that Slice 050 explicitly
deferred.

## BDD / TDD

- `tests/unit/test_canon_entity_guid.gd` (written first, RED before the helper
  existed): determinism, per-entity distinctness, blueprint enumeration of
  structures and spawn points, `contains_guid` true/false, and bounded length.
- `tests/integration/test_canon_mutation_repository.gd` (extended): the
  canonical sector now carries a real `village_hall` structure; the happy-path
  event targets its derived GUID; a new case proves a mutation against an
  unknown `target_guid` is rejected with `target_not_found` and does not advance
  the revision.

## Validation

Run on the Linux host (GUT cannot run on the Windows dev box — missing sqlite /
wgnetstack native libs): `scripts/run_gut_validation.sh` full suite, exit 0,
plus `scripts/check_record_sync.sh` exit 0. Evidence recorded in the P-013
change history and in this record's Root-cause learning section if any surprise
occurs.

## Root-cause learning

- Symptom: first full host GUT run was 461/462 — `test_canon_mutation_repository`
  failed at "parameter binding stored the injection string as inert data"
  (expected 1 stored mutation, got 0).
- Public seam: `CanonMutationRepository.apply_mutation`.
- Hypothesis (confirmed): the pre-existing SQL-injection regression carried its
  hostile string in `target_guid`; the new target-existence check correctly
  rejected that non-entity guid with `target_not_found` before the INSERT, so
  nothing was stored — the new invariant, working as designed, invalidated the
  test's assumption rather than a code defect.
- Why existing tests missed it: the injection test predated the existence check
  and used `target_guid` (an un-validated free string at the time) as its
  carrier field.
- Countermeasure: moved the hostile string to `actor_player_id` (still reaches
  the INSERT) and kept a valid derived `target_guid`, preserving injection-safety
  coverage on an inserted column while honouring target existence.
- Regression evidence: full host `scripts/run_gut_validation.sh` green after the
  fix (see P-013 change history for counts) + `scripts/check_record_sync.sh`
  exit 0.
- Also noted (repo memory): GUT silently *skips* a test script whose `preload`
  target is missing (a warning, not a failure), so a new test file's presence
  must be confirmed by the script/test count increasing, not by "all passed".
