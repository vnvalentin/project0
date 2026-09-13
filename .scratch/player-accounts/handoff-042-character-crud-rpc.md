# Handoff — Slice 042: Character CRUD over the wire (server)

Filled-in [handoff template](../../docs/templates/claude-code-handoff-template.md)
by Copilot (orchestration/review layer). Governing decision:
[player-accounts spec](spec.md) Implementation Slice 4 ("Character CRUD
(server)") + ticket 05. Foundation gate closed. Consumes the Slice 039
repository ([F-030](../../docs/FEATURE-LIST.md#f-030-accounts-and-characters-persistence-repository),
`server/account_character_repository.gd`) and the Slice 040 auth/session seam
([F-031](../../docs/FEATURE-LIST.md#f-031-account-authentication-and-session-server),
`server/auth_service.gd` + `server/session_registry.gd`).

> **Status: CLEARED FOR HANDOFF.** Slices 038/039 (`dae748f`) and 040/041
> (`bbe2b17`) are committed; the gate is green (251/251, 35/35 scripts,
> `check_record_sync.sh` exit 0). Start from that clean base. This slice was
> renumbered 041 → 042 because a concurrent DT-006 test-migration slice took
> 041 (see `docs/slices/SLICE-REGISTRY.md`).

## User outcome

An **authenticated** peer can **list**, **create**, **select**, and
**soft-delete** its own Characters over the ENet link. The server scopes every
operation to the peer's **session account** (the client never names an account),
enforces the 5-Character cap, global live-name uniqueness, and ownership, and
returns typed `CharacterRecord` DTOs or a **bounded rejection** — session-gated
and fail-closed.

## Scope

- **In scope:**
  1. **`shared/character_record.gd`** — add a pure, versioned
     `to_wire_dict() -> Dictionary` and static
     `from_wire_dict(d) -> CharacterRecord` (bounded, fail-closed; unknown/
     missing fields ⇒ reject/skip) so a `CharacterRecord` can cross the RPC
     boundary as a client-safe DTO. **Additive only** — no field/behavior
     change to the existing contract. `cosmetic` and the nullable `vessel_seam`
     serialize as-is; **no salt/hash/account-internal data** beyond the existing
     record fields.
  2. **`server/character_service.gd`** (`class_name CharacterService`),
     server-only: session-gated dispatch wrapping the repository and the shared
     `SessionRegistry`. Every method takes `peer_id`, **requires an
     authenticated session** (else a bounded `NOT_AUTHENTICATED` reason and no
     side effect), and **derives `account_id` from the session** — never from
     the client:
     - `list_characters(peer_id)` → session account → `repo.list_characters` →
       `CharacterRecord[]`.
     - `create_character(peer_id, name, cosmetic)` → session account →
       `repo.create_character` → `CharacterRecord` |
       `NAME_INVALID`/`NAME_TAKEN`/`CHARACTER_CAP_REACHED`.
     - `select_character(peer_id, character_id)` → session account →
       `repo.select_character` (ownership) → records the chosen id on the
       session (for the Slice 6 world-entry) → `CharacterRecord` |
       `NOT_OWNER`/`NO_SUCH_CHARACTER`.
     - `delete_character(peer_id, character_id)` → session account →
       `repo.soft_delete_character` (ownership) → ack |
       `NOT_OWNER`/`NO_SUCH_CHARACTER`/`ALREADY_DELETED`.
  3. **`server/session_registry.gd`** — additive extension: a nullable
     `selected_character_id` on the session plus
     `set_selected_character(peer_id, character_id)` /
     `get_selected_character(peer_id)`, cleared with the session. (Consumed by
     Slice 6; set here by `select_character`.)
  4. **RPC seam** on `client/network_client.gd` (mirror Slice 040's
     `receive_*_request_on_server` / `receive_auth_result` forwarding to a
     `/root` service): four C→S `@rpc("any_peer","call_remote","reliable")`
     receivers (`receive_list_characters_request_on_server`,
     `receive_create_character_request_on_server(name, cosmetic)`,
     `receive_select_character_request_on_server(character_id)`,
     `receive_delete_character_request_on_server(character_id)`), matching client
     `submit_*` helpers, and one S→C
     `receive_character_result(operation, outcome, payload)`
     `@rpc("authority","call_remote","reliable")` carrying the operation tag, the
     bounded outcome, and `to_wire_dict()` payload(s).
  5. **`server/server_main.gd`** — wire one `CharacterService` under `/root`
     (like `AuthService`), **sharing the same `SessionRegistry` instance** so
     auth and character ops see one session state (have `server_main` own the
     registry and inject it into both services, or expose the registry from
     `AuthService`). Additive; no change to the existing connect/spawn path.
  6. **Tests (test-first):**
     - `tests/unit/test_character_record.gd` (extend) —
       `to_wire_dict`/`from_wire_dict` round-trip, including `cosmetic` and a
       null `vessel_seam`, and fail-closed on a malformed wire dict.
     - `tests/integration/test_character_crud_rpc.gd` — unauthenticated request
       ⇒ `NOT_AUTHENTICATED` (no side effect); create/list/select/delete happy
       paths; **account scoping** (a peer authenticated as account A, given
       account B's `character_id`, gets `NOT_OWNER`/`NO_SUCH_CHARACTER` — the
       server uses the session account, never a client-supplied one); the 5-cap
       and `NAME_TAKEN` surfaced over the wire; `select` sets
       `selected_character_id` and refreshes `last_played_at`.
  7. **Delivery records** (see gates).

- **Out of scope (explicit non-goals):**
  - Client character-select / character-create **screens** — spec slice 5.
  - Character → Player **instantiation / world entry** (`start_for_peer` with the
    selected Character) — spec slice 6. `select_character` only records the
    selection on the session here.
  - Making authentication **mandatory** for connect / gating the existing
    spawn-on-connect flow — deferred (spec slice 5 / a later slice).
  - Character rename (not in v1).

## Repository context

- Governing ticket: [spec.md](spec.md) (Implementation Slice 4),
  [issue 05](issues/05-character-data-model-and-lifecycle.md).
- Primary phase / slice: **Phase 14** / **Slice 042** (reserve in
  [SLICE-REGISTRY.md](../../docs/slices/SLICE-REGISTRY.md)); **new feature
  F-032**.
- Files Claude may create/change: `shared/character_record.gd` (additive
  serialization), `server/character_service.gd` (new),
  `server/session_registry.gd` (additive selection state),
  `client/network_client.gd` (additive RPCs), `server/server_main.gd` (wire the
  service), `tests/unit/test_character_record.gd` (extend),
  `tests/integration/test_character_crud_rpc.gd` (new),
  `docs/slices/042-character-crud-rpc.md`, `docs/FEATURE-LIST.md`,
  `docs/PROJECT-TRACKER.md`, `docs/slices/SLICE-REGISTRY.md`.
- Files to preserve: `server/account_character_repository.gd`,
  `server/sqlite_store.gd`, `server/password_hasher.gd`,
  `server/auth_service.gd` (consume, do not change their behavior — reference
  the session registry, do not fork it); `shared/account_handle.gd`; the
  existing movement/spawn/monster/auth RPCs and connect lifecycle; the
  concurrent planning dirs `.scratch/client-auto-update/`, `.scratch/npcs/`.

## Public seam

`CharacterService` (server-only), the four character request RPCs + the
`character_result` RPC, and `CharacterRecord.to_wire_dict()/from_wire_dict()` —
exercised by GUT unit and integration tests. No UI, no world-entry change.

## Safety invariants

- **Authorization core:** the client **never** supplies an `account_id`. The
  server derives it from the authenticated session, so every character op is
  scoped to the session's account. Knowing or guessing another account's
  `character_id` cannot list, select, or delete it.
- **Session-gated:** every character RPC requires `is_authenticated(peer_id)`;
  otherwise a bounded `NOT_AUTHENTICATED` result with no side effect.
- **Server-only:** `CharacterService`, the repository, and the session registry
  never appear in `shared/` or `client/`; the additive
  `CharacterRecord.to_wire_dict` holds no DB handle or secret and serializes no
  account-internal credential data.
- **Fail-closed / atomic / parameter-bound:** inherited from the Slice 039
  repository (do not bypass it with raw SQL). Malformed input ⇒ bounded reason.
- **Non-breaking:** existing RPCs and the connect/spawn path are unchanged.
- **Bounded telemetry:** character op accepted/rejected with the reason, peer id,
  and account id — no secrets, no raw `cosmetic` dumps beyond what is bounded.

## Acceptance scenarios (write the failing tests first)

1. Given an **unauthenticated** peer, when it sends any character request, then
   `NOT_AUTHENTICATED` and no row is created/changed.
2. Given a peer authenticated as account A, when it creates a Character, then it
   is persisted under A and returned as a `CharacterRecord` DTO; `list` returns
   exactly A's live Characters.
3. Given accounts A and B each with a Character, when A (authenticated) sends
   B's `character_id` to `select`/`delete`, then `NOT_OWNER`/`NO_SUCH_CHARACTER`
   — never B's data — because the server scopes to A's session account.
4. Given account A at the 5-Character cap, when it creates a 6th, then
   `CHARACTER_CAP_REACHED`; when it requests a name another live Character holds,
   `NAME_TAKEN`; an invalid name ⇒ `NAME_INVALID`.
5. Given account A owns Character X, when A selects X, then `selected_character_id`
   is recorded on A's session and X's `last_played_at` is refreshed.
6. `CharacterRecord.to_wire_dict()` → `from_wire_dict()` round-trips all fields
   (including `cosmetic` and a null `vessel_seam`); a malformed wire dict is
   rejected fail-closed.

## Validation

1. `godot --headless --import` then the full GUT suite; confirm the new/extended
   suites (`test_character_record.gd`, `test_character_crud_rpc.gd`) are green.
2. `scripts/run_gut_validation.sh`.

### Known red baseline (read before interpreting a red gate)

At the time this slice is scoped, the full gate is **already red** for a reason
**unrelated to this slice**: a concurrent workstream added
`tests/integration/test_authoritative_melee_strike_socket_e2e.gd`, whose spawned
melee harness cannot walk its Player to the target dummy through the enlarged
town's collision map (Player stuck at a wall corner; 3 reach/HIT assertions
fail). **Do not fix that** — it is another workstream's regression. Your bar:
your two focused suites pass, and the **only** remaining full-suite failure is
that pre-existing melee e2e one. If any **new** failure appears, Jidoka-stop and
report it as yours. (If the melee regression has been resolved by the time you
run, expect a fully green gate with `scripts_expected == scripts_ran`.)

## Delivery gates (satisfy BEFORE implementation, verify AFTER)

1. Reserve **Slice 042** and **feature F-032** in
   [SLICE-REGISTRY.md](../../docs/slices/SLICE-REGISTRY.md).
2. Create `docs/slices/042-character-crud-rpc.md` (SDD, BDD, TDD, no-ADR
   rationale or an ADR, validation, related work) — mirror Slices 039/040.
3. Create the **F-032** feature record (In Progress) and **atomically sync all 4
   sections of `docs/PROJECT-TRACKER.md`** (Phase 14 work-index badge + progress
   %, Current slice → 042, slice index entry, Work queue).
4. **Test-first** (red → green → refactor). Do **not** `git commit`.
5. **Jidoka:** stop on any unexpected failure (see the red baseline note); if
   `server_main.gd`/`network_client.gd`/`session_registry.gd` show new
   concurrent edits at start, stop and report rather than clobbering.

## Return report

Files changed; exact commands + exit codes; behavior observed (suite counts,
sample accept/reject outcomes, the account-scoping proof); confirmation that the
only full-suite failure is the pre-existing melee e2e (or that the gate is fully
green); known limitations; and any scope deviation for Copilot review.
