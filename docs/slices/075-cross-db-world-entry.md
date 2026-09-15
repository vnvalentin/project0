# Slice 075 — Cross-DB world entry: bind Player from the assertion snapshot

Status: **delivered**

Phase: 10 (Authoritative runtime and action input), advancing
[P-014](../FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)
and the [login-boundary decision](../../.scratch/container-platform/issues/02-account-login-service-boundary.md).
Twenty-first delivery of the [container-platform map](../../.scratch/container-platform/map.md);
it completes the cross-DB Character-data handoff started in
[Slice 074](074-assertion-character-snapshot.md): the game server now binds a
Player at **world entry** from the signed Character snapshot in the assertion,
so a client that logged in on the separate login process can actually enter the
world — without the game server's DB holding the Character record.

## User outcome

After the login→game assertion handoff, a client can enter the world as its
selected Character on the game server — the Player is bound with the Character's
`display_name` and `cosmetic` carried in the tamper-proof assertion, even though
the game server never read the accounts database.

## Scope and non-goals

In scope:
- `server/session_registry.gd`: store/read a selected-Character snapshot
  (`character_id`, `display_name`, `cosmetic`) on the session.
- `server/login_gateway.gd`: `issue_character_assertion` includes the selected
  Character's `display_name`/`cosmetic` (loaded from the login-side DB);
  `establish_session_from_assertion` stores the snapshot from the claims.
- `server/character_service.gd`: `get_selected_character` returns a
  snapshot-backed `CharacterRecord` when the session carries one (the assertion
  path), falling back to the DB lookup otherwise (the in-process login path).
- The e2e harness proves world entry succeeds cross-process.

Out of scope (later slices): durable game-world persistence of the Character
(position, vessel progression); dropping the game server's in-process
register/login; the DB split on disk; login-screen scene rewiring. This slice
binds a Player at entry from the signed snapshot; durable world state is separate.

## Public seam

- `server/session_registry.gd` (`set_selected_character_snapshot`,
  `get_selected_character_snapshot`).
- `server/login_gateway.gd` (`issue_character_assertion`,
  `establish_session_from_assertion`).
- `server/character_service.gd` (`get_selected_character`).

## Safety invariant

The snapshot the game binds from was HMAC-signed by the login authority
(validated before establish), so it is authoritative and tamper-proof — the game
never trusts client-supplied Character data. The snapshot lives only in the
in-memory session (cleared on disconnect), never persisted. The in-process login
path is unchanged: with no snapshot, `get_selected_character` still resolves via
the DB, so the existing single-process flow and its tests keep passing.

## ADR rationale

No new ADR. Binding a Player from the signed snapshot is the intended use of the
Slice 074 assertion claims, keeping the game server DB-free for accounts/characters
per the login-boundary decision.

## BDD / TDD

`tests/integration/test_login_assertion_handoff.gd` gains a case: two
`LoginRuntime`s on different DBs sharing one secret — the login side issues a
selected-Character assertion carrying the snapshot; the game side establishes the
session and `get_selected_character` returns a record with the asserted
`display_name`/`cosmetic`, **without the game DB holding the account**. The e2e
harness (`scripts/test_login_handoff_e2e.gd`) asserts world entry now returns
`ok` and binds the expected Character name across the two real processes. Existing
CharacterService/CRUD tests prove the in-process DB path is unchanged.

## Validation

- Focused + full suite: `scripts/run_gut_validation.sh` on the Linux host —
  **passed, 55/55 scripts, exit 0** (the handoff integration test gains a case
  proving the game side resolves the selected Character from the snapshot across
  two DBs; existing CharacterService/CRUD tests prove the in-process DB path is
  unchanged).
- Runtime (Linux): `godot --headless --path . -s scripts/test_login_handoff_e2e.gd`
  printed **`ALL PASS`** including `world_entry == ok` and the bound Player named
  `Handoff Hero` across the two real processes (import cache built first in the
  fresh worktree).
- `scripts/check_record_sync.sh` exit 0 (6 pre-existing WARN).

## Root-cause learning

None yet.
