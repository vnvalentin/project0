# Slice 050 — Canon mutation persistence (dynamic world mutation tracking)
GitHub issue: #95

Status: **delivered**

Phase: 9 (Canon persistence and world mutation), advancing
[P-013](../FEATURE-LIST.md#p-013-dynamic-world-mutation-tracking). This is the
first P-013 slice and builds directly on the Slice 045 immutable Canon sectors
and the Slice 038 server-owned SQLite engine.

## User outcome

A player-driven change to an already-canonical sector (for example defeating a
faction leader) is recorded once, survives a server restart, and cannot be
duplicated, re-ordered, or forged against stale world state when the sector is
revisited.

## Scope and non-goals

In scope: a server-only `CanonMutationRepository` — an append-only mutation log
keyed by a server-owned `event_id`, an optimistic per-sector revision derived
from that log, strict fail-closed validation of the mutation event at the
persistence boundary, and structured outcomes for first apply, idempotent
replay, stale-revision rejection, non-canon-sector rejection, forged-idempotency
rejection, and restart recovery.

Out of scope (later P-013 / other slices): assigning stable GUIDs to every
blueprint entity, verifying that the physical game event actually occurred,
gameplay authorization of the actor, the network DTO/RPC that will carry a
mutation intent from a client, mutation replay into live scene state, and any
mutation telemetry beyond the structured result outcomes. The immutable
`canon_sectors` table (Slice 045) is never modified by this slice.

## Public seam

`server/canon_mutation_repository.gd` (`class_name CanonMutationRepository`),
constructed with the shared `SqliteStore` and the Slice 045 `CanonRepository`:

- `ensure_schema()` — creates the append-only `canon_mutations` table (with
  `event_id` as the idempotency primary key) and its `sector_id` index.
- `apply_mutation(event)` — validates the untrusted event dictionary, verifies
  the target sector is Canon, enforces optimistic `expected_revision`, and
  appends the mutation transactionally, deriving the new `applied_revision`.
- `get_sector_revision(sector_id)` — the current revision (0 when a canon
  sector has no mutations), derived as `MAX(applied_revision)` over the log.
- `list_mutations(sector_id)` — the ordered mutation history for replay/load.

The per-sector revision is **derived from the append-only log** (no mutable
revision row), so recovery after restart is a pure read and there is no
second source of truth to drift.

Bounded event contract (validated fail-closed, values outside bounds rejected
before any write): `schema_version` in the supported set, non-empty bounded
`event_id` / `sector_id` / `target_guid` / `actor_player_id`, `mutation_kind`
in a bounded set, non-negative bounded `server_tick` and `expected_revision`,
and a `payload` dictionary whose serialized length is bounded.

## Safety invariants

- **Idempotent:** replaying the same `event_id` with identical content returns
  the original result and never advances the revision or double-applies.
- **Optimistic and fail-closed:** an `expected_revision` that does not match the
  current revision is rejected (`revision_mismatch`); a mutation against a
  non-canon sector is rejected (`sector_not_canon`); a malformed event is
  rejected (`invalid_event`) before any storage.
- **Forgery guard:** reusing a server-owned `event_id` for different content is
  a `conflict`, not a silent overwrite.
- **Server-only:** the repository, the store handle, and the godot-sqlite
  extension are never referenced by `shared/` or `client/`.

## ADR rationale

No new ADR. Server authority, server-only persistence ownership, atomic commit,
idempotent and revision-checked mutation, and versioned provenance are already
normative in `CLAUDE.md` (`CanonMutationEvent`, the
`CANON -> MUTATION_VALIDATING -> CANON (new revision)` lifecycle) and the
accepted Canon persistence design ticket.

## BDD / TDD

`tests/integration/test_canon_mutation_repository.gd` (written first, RED before
the repository existed) covers: fresh canon sector at revision 0, first apply
bumping the revision, idempotent replay, stale-revision rejection, a valid
second mutation at the current revision, non-canon rejection, forged-idempotency
conflict, malformed/non-dictionary rejection with no storage, restart recovery
replaying the ordered history, and a hostile `target_guid` stored inertly as
parameter-bound data.

## Validation

- Focused: `godot --headless --path . -s addons/gut/gut_cmdln.gd
  -gdir=res://tests/integration -gtest=test_canon_mutation_repository
  -gdisable_colors -gexit` — the integration suite passed with the 11 new
  `test_canon_mutation_repository` cases included (94 → 105 tests, all passing).
- Server parse: `godot --headless --path . --check-only -s
  server/canon_mutation_repository.gd`, exit 0.
- Full gate: `scripts/run_gut_validation.sh` — **293/293 tests across 40/40
  scripts, exit 0** (`scripts_expected == scripts_ran`), up from 282/39 before
  this slice. `scripts/check_record_sync.sh` — exit 0 (0 errors, 6 pre-existing
  warnings).
