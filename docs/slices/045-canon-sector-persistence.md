# Slice 045 — Canon sector persistence and one-time blueprint canonicalization

Status: **delivered**

Phase: 9 (Canon persistence and world mutation), advancing P-011 and P-012.
This is the first Wave 5 Canon slice and consumes the delivered Slice 038
server-owned SQLite engine.

## User outcome

The server can durably store a validated sector blueprint once, recover it
after a restart, and refuse a conflicting regeneration for the same world
coordinate without replacing historical Canon.

## Scope and non-goals

In scope: a server-only `CanonRepository`, an idempotent coordinate-unique
sector table, strict revalidation at the persistence boundary, and structured
outcomes for first write, same-content replay, conflicting replay, lookup, and
transaction failure.

Out of scope: sector-boundary detection, Ollama orchestration changes, client
code, geometry translation, mutable world events, progression, and SQLite
migrations beyond the existing engine user-version gate.

## Public seam

`server/canon_repository.gd` exposes `ensure_schema()`,
`canonicalize_blueprint(blueprint)`, and `get_canonical_sector(sector_id)`.
The repository accepts only a blueprint that passes
`SectorBlueprintSchema.validate()`, stores the validated blueprint as JSON, and
derives the coordinate uniqueness key from the validated sector id.

Canonicalization is transactional. A same-coordinate replay with identical
validated JSON returns the existing row as an idempotent success. A replay with
different content returns a bounded conflict and leaves the existing row
unchanged.

## BDD / TDD

`tests/integration/test_canon_repository.gd` covers fresh schema creation,
first-write persistence, close/reopen recovery, same-content idempotency,
conflicting regeneration rejection, malformed blueprint rejection, and a
parameter-bound hostile JSON value round trip.

## Safety invariant

No provisional or conflicting result can replace an existing Canon row. The
client and shared contract code never receive a database handle.

## ADR rationale

No new ADR. The authority, server-only ownership, atomicity, immutable first
write, and version provenance are already normative in `CLAUDE.md` and the
accepted Canon design ticket.

## Validation

Focused validation: `godot --headless --path . -s addons/gut/gut_cmdln.gd
-gdir=res://tests/integration -gtest=test_canon_repository -gdisable_colors
-gexit` passed 94/94 integration tests and 375 assertions, exit 0.
Server parse validation: `godot --headless --path . --check-only -s
server/server_main.gd`, exit 0.
Full validation: `scripts/run_gut_validation.sh` passed 268/268 tests across
36/36 scripts, exit 0. Record sync passed with 0 errors and 6 pre-existing
warnings.