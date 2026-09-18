# Slice 143 - Phase 15 follow-on (P-016): durable vessel persistence

GitHub issue: #219 (Goal: embodiment — P-016 biological progression and kinetic combat systems); vessel-progression contract issue #223

Status: **delivered**

Phase: 15 (Biological progression and kinetic systems) — post-exit-gate follow-on wiring

Feature: [P-016](../FEATURE-LIST.md#p-016-biological-progression-and-kinetic-combat-systems)

Design source: [Slice 140](140-phase15-embodiment-progression-service.md) — its
"Out of scope" section defers "persistence of vessels to SQLite". This slice
delivers that second (and last) Slice 140 follow-on as a server-only repository
seam over the existing shared SQLite foundation. The vessel value shape and its
fail-closed load validation are the Slice 133 contract
([`shared/vessel_progression_state.gd`](../../shared/vessel_progression_state.gd)).
See [ADR 0006](../adr/0006-versioned-embodiment-mechanics-architecture.md).

## User outcome

A Character's earned vessel — the six-node biological build the player worked for
— now survives a server restart. The server can durably store a vessel and later
reload the exact earned state, so progression is no longer lost when the process
stops.

## Scope and non-goals

In scope: a server-only `VesselRepository` over the existing `SqliteStore` engine
seam that creates its table, upserts a Character's vessel by `character_id`, and
reloads it after restart revalidated against the current tuning; plus the
`VesselProgressionState.to_wire_dict()` serializer (the exact inverse of the
existing `from_wire_dict`).

Out of scope: wiring the repository into the live world-entry / progression-service
path (save-on-train, load-on-select). That integration first needs the
still-open design decision of where the authoritative shared progression service
lives and how it is handed a store — Slice 142's replication channel deliberately
used a per-Player service instance, which is correct for derivation but not for a
single shared persistent store. The repository delivered here is the concrete
persistence mechanism that integration will consume; inventing the ownership model
autonomously is out of scope. Also out of scope: persisting Meridian/Burnout
subsystem state (only the durable vessel is persisted here), and any client-facing
persistence surface (this is server-only).

## Public seam

- `shared/vessel_progression_state.gd`: `to_wire_dict()` — the durable form
  (`schema_version`, `tuning_version`, a copy of `base_nodes`).
- `server/vessel_repository.gd` (`VesselRepository`): `ensure_schema()`,
  `save_vessel(character_id, vessel)` (idempotent upsert by `character_id`),
  `load_vessel(character_id, tuning)` (revalidated fail-closed via
  `VesselProgressionState.from_wire_dict`, or `OUTCOME_NOT_FOUND`).

## Security / boundary

Server-only, exactly like `CanonRepository`/`AccountCharacterRepository`: `shared/`
and `client/` never reference it or the SQLite engine. Only durable, non-secret
value state is persisted (the earned base nodes + the pinned tuning version) —
never derived/effective numbers. A stored row is untrusted on load and revalidated
at the boundary against the current tuning (schema, structure, node bounds, and
the fixed budget), so a corrupt or mistuned row fails closed
(`OUTCOME_INVALID_VESSEL`) instead of resurrecting an invalid vessel. Every method
returns a bounded `{outcome, detail}` result and never raises.

## Validation

Command: `bash scripts/run_gut_validation.sh` on the Linux host (working-tree
overlay onto the deploy tree, since this depends on merged-but-undeployed Phase 15
files — `vessel_progression_state.gd`, `embodiment_tuning.gd`).

Result: **729/729 tests passing across 100/100 scripts, 2325 asserts, exit 0**
(from 723/99 on main: +1 script, +6 tests).

New test: `tests/integration/test_vessel_repository.gd` (6 tests, over a real
temporary `user://` SQLite database): a missing character returns not-found; a
saved vessel is recovered identically after a full store close/reopen; a real
trained gain (not the baseline) round-trips; re-saving upserts the same character
to the latest trained state; a budget-violating row corrupted out-of-band is
refused fail-closed on load; an empty `character_id` and a null vessel are refused
on save.

## Root-cause learning

No unexpected runtime failure, defect, or validation surprise arose during this
slice. The repository mirrors the proven `CanonRepository` pattern over the same
`SqliteStore` seam, and the round-trip/restart test passed on the first full-suite
run.

## Follow-on / debt

- Live integration (save-on-train, load-on-world-entry) is the remaining work and
  is gated on the shared-vs-per-Player progression-service ownership decision
  noted above — a small design step, not autonomous invention.
- Meridian/Burnout persistence, if later required, would extend this repository or
  add sibling repositories.
