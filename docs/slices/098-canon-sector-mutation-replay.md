# Slice 098 — Canon sector mutation replay: server replicates the effective blueprint

Status: **in-progress**

Phase: 9 (Canon persistence and world mutation), completing the
[P-013](../FEATURE-LIST.md#p-013-dynamic-world-mutation-tracking) code path.
Fifth and final P-013 slice: it makes a loaded or revisited sector reflect its
durable mutation history, building on the Slice 050 log, the Slice 095 entity
GUIDs, and the Slice 096/097 intent path.

## User outcome

When a player enters (or re-enters) a canonical sector that has been changed —
for example a structure was destroyed — the sector they see reflects that
change, because the server replays the sector's durable mutation log and
replicates the **effective** sector, not the pristine original blueprint.

## Scope and non-goals

In scope:

- `shared/canon_sector_resolver.gd` (`CanonSectorResolver`) — a pure,
  deterministic replay of an ordered mutation list onto a validated canonical
  blueprint, producing the **effective blueprint**. The geometry-affecting kind
  today is `destroy_structure`: the resolver removes any structure whose derived
  `CanonEntityGuid` matches a `destroy_structure` mutation's `target_guid`. The
  result stays schema-valid (structures are optional). Order-independent and
  idempotent for removal.
- `server/server_main.gd` — both sector-replication points (initial connect and
  `_on_canonical_sector_ready`) now send the resolver's effective blueprint,
  derived from `CanonMutationRepository.list_mutations(sector_id)`, so clients
  render live world state with no client change and no RPC signature change.

Out of scope: mutation kinds that do not (yet) map to rendered geometry
(`loot`, `defeat_leader`, `clear_camp`) are structurally inert here — they
remain in the durable log and can drive NPC/loot state in a later slice; the
client renderer, the `receive_sector_blueprint` RPC shape, gameplay
authorization, and telemetry are unchanged.

## Public seam

- `CanonSectorResolver.resolve_effective_blueprint(blueprint, mutations) -> Dictionary`
  — returns a duplicated blueprint with destroyed structures removed; a non-dict
  blueprint or empty mutation list returns the blueprint unchanged.
- `server_main._effective_blueprint_for(sector_id, blueprint) -> Dictionary` —
  lists the sector's mutations and applies the resolver before replication.

## Safety invariants

- **Server authority:** replay happens on the server; the client keeps rendering
  whatever validated blueprint it is sent, so it never needs the raw mutation
  log or any replay logic.
- **Pure and deterministic:** `resolve_effective_blueprint` is a function of its
  inputs only (no clock, no store); the same log always yields the same
  effective blueprint, and re-applying a `destroy_structure` is idempotent.
- **Schema-valid output:** removing optional structures keeps the effective
  blueprint valid, so the client's existing re-validation on receive still passes.
- **Fail-safe:** if the mutation repository is unavailable or lists nothing, the
  original blueprint is replicated unchanged.

## ADR rationale

No new ADR. Server-owned world state, deterministic replay, and the immutable
Canon + append-only mutation model are already normative in `CLAUDE.md`.

## BDD / TDD

- `tests/unit/test_canon_sector_resolver.gd` (written first): no-mutations
  passthrough, `destroy_structure` removes the matching structure, non-matching
  target leaves all structures, multiple destroys, non-geometry kinds are inert,
  and non-dict inputs are safe.
- `tests/integration/test_canon_sector_replay.gd` (written first): over a real
  SQLite-backed canonical sector, applying a `destroy_structure` mutation through
  `CanonMutationRepository` and resolving the effective blueprint yields a sector
  without that structure — the end-to-end replay path, no RPC/auth needed.

## Validation

Linux host: full `scripts/run_gut_validation.sh` exit 0 (script/test counts must
rise for the two new files) + `scripts/check_record_sync.sh` exit 0.

## Root-cause learning

None yet.
