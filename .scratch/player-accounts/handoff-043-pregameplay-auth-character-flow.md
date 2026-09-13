# Handoff — Slice 043: Pre-gameplay auth + character flow (client + server world entry)

Filled-in [handoff template](../../docs/templates/claude-code-handoff-template.md)
by Copilot. Governing decision: [player-accounts spec](spec.md) Implementation
Slices **5 and 6** (they are tightly coupled — the client screens and the
server-side world-entry binding cannot be exercised independently). Consumes the
Slice 040 auth/session RPCs and the Slice 042 Character-CRUD RPCs (all delivered).
Reserve **Slice 043** + feature **F-033** (verify free at implementation time).

> **Status: SCOPED — approach decision pending.** This is the first Phase 14
> slice whose core deliverable is **client UI + a pre-gameplay flow change** that
> **cannot be visually validated on the current headless SSH remote**. Per the
> repo's established pattern, every prior client slice (identity gate, movement,
> prediction, multi-peer, monster rendering) was **verified by the user in an
> interactive GUI**. Headless GUT can validate the controller/flow *logic* and
> the server world-entry binding, but not that the screens render or that the
> real login→select→enter round-trip works on-screen.

## User outcome

A person launches the client, sees a **login/register** screen, authenticates
over the ENet link, sees their **Character roster** (create up to 5 / select /
delete), and **enters the world as the selected Character** — replacing the
display-name identity gate as the entire pre-gameplay flow. Server-authoritative
and fail-closed.

## The coupling / key design decisions (need alignment)

1. **When does the client connect?** Auth RPCs travel over ENet, so the client
   must **connect at the login screen** (not in `gameplay.tscn`). `NetworkClient`
   is an autoload, so the connection persists across the scene change into
   gameplay. **Recommendation:** connect on the login screen; show connection
   errors there.
2. **Server stops auto-spawning on connect (the mandatory-auth flip).** Today
   `server_main.gd::_on_peer_connected` immediately sends the blueprint, spawns
   the Player, assigns a house, and replicates. With a login screen, a peer is
   connected but not yet a Character, so that must **defer** to an explicit
   world-entry step. **Recommendation:** on connect, send only what a
   pre-gameplay client needs (nothing, or just an ack); spawn/replicate the
   Player **only** when an authenticated peer with a selected Character sends a
   new `enter_world` request. This is the spec-6 "start_for_peer binds the
   selected Character" step.
3. **Player identity source.** `start_for_peer` currently takes a raw position;
   the Player's on-screen identity was the display name. Now it binds the
   **selected Character** (display name + cosmetic from the `CharacterRecord`).
   `PlayerIdentity` holds the `AccountHandle` + selected `CharacterRecord` instead
   of a display name.
4. **This is a deliberate replacement of the always-playable identity-gate flow**
   — not a regression, but the planned Phase 14 evolution. The old
   `identity_gate.tscn` is retired.

## Scope

- **In scope:**
  - **Client screens** (new `.tscn` + scripts), replacing `identity_gate.tscn`
    as `run/main_scene`:
    - Login/Register: username + password + server host; calls
      `NetworkClient.connect_to_server` then `submit_register`/`submit_login`;
      listens to `auth_result_received`; on success → character-select.
    - Character select: lists via `submit_list_characters` /
      `character_result_received`; buttons to create (→ create screen), select
      (→ enter world), delete (`submit_delete_character`); enforces the 5-slot cap
      visually from the roster.
    - Character create: name + minimal cosmetic; `submit_create_character`; on
      success → back to select (or straight to enter world).
  - `client/player_identity.gd`: hold `AccountHandle` (account_id + username) and
    the selected `CharacterRecord` (from `from_wire_dict`), replacing
    `display_name`.
  - **Server world entry (spec 6):** a new `receive_enter_world_request_on_server`
    RPC; the server verifies the peer is authenticated and has a
    `selected_character_id`, loads that `CharacterRecord`, and spawns/binds the
    authoritative Player **as that Character** (identity/cosmetic), then runs the
    existing blueprint/house/replication steps. Remove the auto-spawn from
    `_on_peer_connected`.
  - `server/server_player_state.gd` `start_for_peer`: accept the Character
    identity/cosmetic (additive) so the Player is the selected Character.
  - **Tests (headless, logic-level):** a client-flow controller test (state
    transitions given `auth_result_received`/`character_result_received` signals,
    without rendering) and a server world-entry integration test (unauthenticated
    or no-selection → refused; authenticated + selected → spawns the Player bound
    to the Character; existing movement/combat unchanged afterward).
  - Delivery records (slice doc, F-033, tracker sync, `check_record_sync`).

- **Out of scope:**
  - Cosmetic depth beyond a minimal placeholder (Phase 12 vessel visuals).
  - Reconnect-resume of a selected Character (reconnect = full re-auth per spec).
  - Any change to movement/combat/monster/collision authority.

## Safety invariants

- Server-authoritative: world entry requires an authenticated session **and** a
  server-recorded `selected_character_id`; the client never asserts which
  Character it is — the server reads it from the session (Slice 042 recorded it).
- Passwords only travel client→server over the (WireGuard-gated) ENet link and
  are never stored client-side or logged.
- Fail-closed: an `enter_world` from an unauthenticated or unselected peer is a
  bounded rejection with no spawn.
- No credential material client-side beyond what the user typed transiently.

## Acceptance scenarios

1. Fresh client → login screen; register a new account → character-select (empty
   roster).
2. Create a Character → it appears in the roster; creating a 6th is prevented.
3. Select a Character → enter the world; the authoritative Player is that
   Character (name/cosmetic), and movement/combat work as before.
4. `enter_world` from a connected-but-unauthenticated peer → refused, no spawn.
5. Delete a Character → it leaves the roster.
6. (GUI, user-verified) The three screens render and the on-screen
   login→select→enter round-trip works end-to-end over a real socket.

## Validation

- Headless: `godot --headless --import`; `scripts/run_gut_validation.sh` (exit 0,
  `scripts_expected == scripts_ran`); `scripts/check_record_sync.sh` exit 0.
- **GUI (required, user):** run the client, register/login, create+select a
  Character, and confirm world entry — the same interactive-GUI confirmation
  every prior client slice received.

## Delivery gates

Reserve Slice 043 + F-033; slice doc `docs/slices/043-*.md`; F-033 (In Progress);
sync all 4 `PROJECT-TRACKER.md` sections; `check_record_sync.sh` exit 0;
test-first for the logic-level tests; preserve the concurrent uncommitted
`dashboard/*` and `.scratch/` planning work; do not commit until reviewed.
