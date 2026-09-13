# Slice 043 — Character world entry (server-side binding)

Status: **delivered** (server-side selected-Character resolution + binding; the
client login/character screens are a separate GUI-confirmed slice).

Phase: 14 (Player accounts and characters). New feature: **F-033**.

Design basis: [player-accounts spec](../../.scratch/player-accounts/spec.md)
Implementation Slice 6 ("Character → Player instantiation") and
[.scratch/player-accounts/handoff-043-pregameplay-auth-character-flow.md](../../.scratch/player-accounts/handoff-043-pregameplay-auth-character-flow.md)
(which scopes the coupled spec slices 5+6; this slice delivers the **server**
half — spec 6 — and the client screens/flow — spec 5 — follow as Slice 044,
which needs interactive-GUI confirmation on a machine with a display).

## User outcome

An authenticated peer that has selected a Character can **enter the world as
that Character**: the server resolves the selection from the session, binds the
Character's identity/cosmetic to the peer's authoritative Player, and confirms
it — server-authoritative and fail-closed.

## Scope

**In scope:**

- `server/server_player_state.gd` — additive `character_id` /
  `character_display_name` / `character_cosmetic` fields and `bind_character()`;
  identity/cosmetic only, no change to position/combat authority.
- `server/character_service.gd` — `get_selected_character(peer_id)`: derives the
  account + `selected_character_id` from the session (Slice 042 recorded it) and
  returns the live `CharacterRecord`, or `NOT_AUTHENTICATED` /
  `NO_CHARACTER_SELECTED` / `NO_SUCH_CHARACTER` fail-closed.
- `client/network_client.gd` — additive `submit_enter_world`,
  `receive_enter_world_request_on_server` (resolves via `CharacterService` and
  binds the peer's `ServerPlayerState`, both `/root` nodes),
  `receive_enter_world_result`, and `world_entry_received` — following the
  Slice 040/042 forwarding pattern; the reply never forwards the `detail` string.
- Test: `tests/integration/test_character_crud_rpc.gd` gains a world-entry
  scenario (unauthenticated → refused; authenticated but unselected → refused;
  selected → resolves the `CharacterRecord`).

**Out of scope:**

- **Client login/register/character-select/create screens** and the
  `PlayerIdentity` restructure (spec slice 5) — **Slice 044**, GUI-confirmed.
- The "no anonymous play / auth mandatory" hard-flip (removing the connect-time
  spawn). This slice is **additive**: the connect-time spawn is unchanged, so
  the e2e harnesses' no-auth path still works. Making auth mandatory is a
  documented follow-up (it cascades into the real-server e2e harnesses).
- Cross-peer replication of Character identity/cosmetic (others seeing your
  Character's name/look) — a later polish step.

## Authorization core

World entry requires an authenticated session **and** a server-recorded
`selected_character_id`; the client never names the account or the Character —
`CharacterService.get_selected_character` derives both from the session. An
`enter_world` from an unauthenticated or unselected peer is a bounded rejection
with no binding.

## Public seam

- `server/server_player_state.gd` (`bind_character`, `character_id`,
  `character_display_name`, `character_cosmetic`).
- `server/character_service.gd` (`get_selected_character`).
- `client/network_client.gd` (`submit_enter_world`, `world_entry_received`).

## BDD scenarios

1. `enter_world` from a connected-but-unauthenticated peer → `NOT_AUTHENTICATED`,
   no binding.
2. Authenticated peer with no selection → `NO_CHARACTER_SELECTED`.
3. Authenticated peer with a selected Character → the `CharacterRecord` resolves
   and the Player is bound to its identity/cosmetic.
4. A selected Character that was since deleted → `NO_SUCH_CHARACTER`.

## TDD

`tests/integration/test_character_crud_rpc.gd::test_get_selected_character_requires_auth_and_a_selection`
exercises the world-entry resolution logic (the authoritative half) directly
against `CharacterService`.

## Validation

```
godot --headless --import
scripts/run_gut_validation.sh
```

Result: **exit 0**, `"status": "passed"`, `"scripts_expected": 36 ==
"scripts_ran": 36`, **268 tests / 268 passing**; `scripts/check_record_sync.sh`
exit 0. The existing real-server e2e harnesses stay green (this slice is
additive to the connect-time spawn).

## Known limitations

- The client-visible flow (screens, entering gameplay as the Character) is
  Slice 044 and requires interactive-GUI confirmation.
- Character identity/cosmetic is bound server-side and returned to the owning
  client only; other peers do not yet render your Character's identity.

## Related work

[PROJECT-TRACKER.md](../PROJECT-TRACKER.md#phase-work-index),
[FEATURE-LIST.md](../FEATURE-LIST.md#f-033-character-world-entry-server-binding),
[Slice 042](042-character-crud-rpc.md) (the consumed CRUD/session seam),
[player-accounts spec](../../.scratch/player-accounts/spec.md).
