# Slice 042 — Character CRUD over the wire (server)
GitHub issue: #95

Status: **delivered** (server-only, session-gated Character CRUD; no client UI,
no world entry).

Phase: 14 (Player accounts and characters). New feature: **F-032**.

Design basis: [player-accounts spec](../../.scratch/player-accounts/spec.md)
Implementation Slice 4 ("Character CRUD (server)") + ticket 05, and
[.scratch/player-accounts/handoff-042-character-crud-rpc.md](../../.scratch/player-accounts/handoff-042-character-crud-rpc.md).
Consumes the Slice 039 repository
([F-030](../FEATURE-LIST.md#f-030-accounts-and-characters-persistence-repository),
`server/account_character_repository.gd`) and the Slice 040 auth/session seam
([F-031](../FEATURE-LIST.md#f-031-account-authentication-and-session-server),
`server/auth_service.gd` + `server/session_registry.gd`) — all consumed with
only the two additive changes noted below.

## User outcome

An authenticated peer can list, create, select, and soft-delete its own
Characters over the ENet link. The server scopes every operation to the peer's
session account, enforces the 5-Character cap, global live-name uniqueness, and
ownership, and returns typed `CharacterRecord` DTOs or a bounded rejection —
session-gated and fail-closed.

## Scope

**In scope:**

- `shared/character_record.gd` — additive pure, versioned `to_wire_dict()` and
  static fail-closed `from_wire_dict()` so a `CharacterRecord` crosses the RPC
  boundary as a client-safe DTO. No field/behavior change to the existing
  contract; no salt/hash/account-internal data beyond the record's own fields.
- `server/character_service.gd` (`class_name CharacterService`, a `/root` Node
  like `AuthService`): session-gated `list_characters` / `create_character` /
  `select_character` / `delete_character`. Each requires an authenticated
  session (else `NOT_AUTHENTICATED`, no side effect) and **derives `account_id`
  from the session** — the client never supplies it. `select_character` records
  the selection on the session (`selected_character_id`) for a future world-entry
  slice.
- `server/session_registry.gd` — additive `set_selected_character` /
  `get_selected_character` (cleared with the session on disconnect).
- `server/auth_service.gd` — additive `get_session_registry()` so
  `server_main.gd` shares the **same** `SessionRegistry` instance with
  `CharacterService`.
- `client/network_client.gd` — additive four C→S character request RPCs +
  `submit_*` helpers + a `receive_character_result` S→C RPC and
  `character_result_received` signal, mirroring the Slice 040 auth pattern; the
  reply never forwards the `detail` string (only the bounded outcome + wire
  dicts).
- `server/server_main.gd` — wires one `CharacterService` under `/root` sharing
  `AuthService`'s `SessionRegistry`. Additive; the connect/spawn path is
  unchanged.

**Out of scope (later slices):**

- Client character-select / character-create screens (spec slice 5).
- Character → Player instantiation / world entry (spec slice 6); `select` only
  records the selection here.
- Making authentication mandatory for connect / gating the spawn-on-connect
  flow.
- Character rename (not in v1).

## Authorization core

The non-negotiable safety invariant: the client never sends an `account_id`.
`CharacterService` resolves it from the caller's `SessionRegistry` session, so a
peer authenticated as account A cannot list, select, or delete a Character owned
by account B even when it knows B's `character_id` — the repository's ownership
check always runs against A's own session account. Proven by
`test_account_scoping_prevents_cross_account_select_and_delete`.

## Public seam

- `shared/character_record.gd` (`to_wire_dict`, `from_wire_dict`).
- `server/character_service.gd` (`CharacterService.list_characters`,
  `create_character`, `select_character`, `delete_character`).
- `server/session_registry.gd` (`set_selected_character`,
  `get_selected_character`).
- `client/network_client.gd` (`submit_list_characters`,
  `submit_create_character`, `submit_select_character`, `submit_delete_character`,
  `character_result_received`).

## BDD scenarios

1. Unauthenticated peer → `NOT_AUTHENTICATED` on every operation, no side effect.
2. Create persists under the session account; list returns exactly that
   account's live Characters.
3. Authorization core: account A cannot select/delete account B's Character even
   given B's `character_id` (`NOT_OWNER`/`NO_SUCH_CHARACTER`); B's Character is
   untouched.
4. The 5-cap (`CHARACTER_CAP_REACHED`), global live-name uniqueness
   (`NAME_TAKEN`), and charset validation (`NAME_INVALID`) are all surfaced over
   the service seam.
5. `select` records `selected_character_id` on the session and refreshes
   `last_played_at`.
6. `to_wire_dict()` round-trips all fields (incl. `cosmetic`, null
   `vessel_seam`) and carries no credential material; `from_wire_dict()` rejects
   a malformed wire dict fail-closed.
7. Soft-delete removes an owned Character from `list` and a repeat delete →
   `ALREADY_DELETED`; an unknown `character_id` → `NO_SUCH_CHARACTER`.

## TDD

`tests/integration/test_character_crud_rpc.gd` — exercises `CharacterService`
directly against a temporary `user://` SQLite database (per-test filename,
freed/cleaned in `after_each`), calling the service with a bare `peer_id` exactly
as `server_main.gd`'s RPC dispatch does after resolving
`multiplayer.get_remote_sender_id()`. Each scenario binds a **real** account
(via the repository, satisfying the `characters.account_id` foreign key) then
binds a session to its server-generated id.
`tests/unit/test_character_record.gd` — extended with `to_wire_dict`/
`from_wire_dict` round-trip and fail-closed parse coverage.

## Validation

All commands from the repository root (Godot `4.3.stable`, headless Linux).

```
godot --headless --import
scripts/run_gut_validation.sh
```

Result: **exit 0**, `build/validation/validation-summary.json`
`"status": "passed"`, `"scripts_expected": 36 == "scripts_ran": 36`
(DT-007 gate satisfied), **267 tests / 267 passing**.
`scripts/check_record_sync.sh` exits 0.

## Known limitations

- No client UI, no world entry, no mandatory-auth gate (explicit non-goals).
- Character RPCs are exercised through the `CharacterService` seam in tests (the
  in-process pattern the auth slice also uses); the live socket round-trip of
  the four character RPCs is not separately harnessed here (it reuses the
  Slice 040 forwarding pattern already proven over a real socket).

## Related work

[PROJECT-TRACKER.md](../PROJECT-TRACKER.md#phase-work-index),
[FEATURE-LIST.md](../FEATURE-LIST.md#f-032-character-crud-over-the-wire-server),
[player-accounts spec](../../.scratch/player-accounts/spec.md),
[Slice 040](040-account-auth-session.md) (the consumed auth/session seam),
[Slice 039](039-accounts-characters-repository.md) (the consumed repository).
