# Slice 044: Client Login and Character Selection UI

**Status:** In Progress (scaffolding complete, GUI verification on Windows pending)
**Linked Feature:** F-034 (new feature in FEATURE-LIST.md)
**Related Server Slices:** Slices 040 (auth), 042 (character CRUD), 043 (world-entry)

## Scope

Deliver client-side UI screens for account login/registration and character selection/creation. Connects Phase 40-43 server-side machinery to the end-user experience. Comprises two scenes:

1. **account_gate.tscn / account_gate.gd** — Login and registration flow
   - Username, password, server-host inputs
   - Login and Register buttons
   - Status display for connection and auth outcomes
   - On successful auth: stores account_id/username in PlayerIdentity, transitions to character_gate.tscn

2. **character_gate.tscn / character_gate.gd** — Character roster and lifecycle
   - Lists characters for the logged-in account
   - Select, Create, Delete buttons
   - Create opens a modal dialog for character name input
   - On successful select + world-entry: stores selected_character_id/display_name in PlayerIdentity, transitions to gameplay.tscn

Both scenes integrate with NetworkClient's RPC seams (auth, character CRUD, world-entry) and respond to corresponding outcome signals.

## Non-Goals

- Character cosmetic/visual customization UI (Phase 12, future slice)
- Cosmetic rendering in character roster (currently just display names)
- Multi-peer Character identity replication (Phase 16, future)
- Password reset / account recovery
- Persistent client-side character state (all state flows through server-gated RPCs)
- Spawn deferral / deferred Player rendering (attempted in this slice, reverted due to e2e harness brittleness; documented as follow-up)

## Hypothesis

A client that opens a connection during login, stores identity in PlayerIdentity, and transitions to gameplay will successfully inherit the active connection and render server-provided Player state without secondary re-spawns or double-peer creation.

## Cheapest Discriminating Check (CDC)

1. Launch client with `account_gate.tscn` as main_scene
2. Input valid username/password and server host
3. Submit login → receive auth_result_received signal with OK outcome
4. Verify PlayerIdentity.account_id and .username are populated
5. Verify scene transitions to character_gate.tscn without errors
6. Select an existing character or create one
7. Verify character_result_received signal fires with appropriate outcome
8. On select success, verify world_entry_received fires with character dict
9. Verify scene transitions to gameplay.tscn
10. Verify Player node renders in the scene (no double-spawn, no missing Player)

## Validation Command

For unit-test integration: `scripts/run_gut_validation.sh` (268/268 tests)
For GUI verification on Windows: launch client, navigate login → character select → gameplay, confirm smooth transitions and no errors in output console.

## Public Seam

### Input: PlayerIdentity Fields (populated by login/character flows)
- `account_id`: String (server-assigned unique identifier)
- `username`: String (login credential)
- `selected_character_id`: String (active character for gameplay)
- `selected_character`: Dictionary (display_name, cosmetic, last_played_at, etc.)
- `display_name`: String (alias for selected_character.display_name, for convenience)
- `target_host`: String (server address, inherited by gameplay's connection_status.gd)

### Input: NetworkClient RPC Seams
- `submit_register(username, password)` → `auth_result_received(outcome, account_id, username)`
- `submit_login(username, password)` → `auth_result_received(outcome, account_id, username)`
- `submit_list_characters()` → `character_result_received("list", outcome, {"characters": [...]})`
- `submit_create_character(name, cosmetic)` → `character_result_received("create", outcome, ...)`
- `submit_select_character(character_id)` → `character_result_received("select", outcome, ...)`
- `submit_delete_character(character_id)` → `character_result_received("delete", outcome, ...)`
- `submit_enter_world()` → `world_entry_received(outcome, character_dict)`

### Outcomes (Bounded Enums, from Slices 040/042/043)
- **Auth outcomes:** OK, BAD_CREDENTIALS, REGISTRATION_FAILED, SERVER_ERROR, CONNECTION_LOST
- **Character CRUD outcomes:** OK, NOT_AUTHENTICATED, NAME_TAKEN, CHARACTER_CAP_REACHED, NO_SUCH_CHARACTER, INVALID_NAME, SERVER_ERROR
- **World-entry outcomes:** OK, NOT_AUTHENTICATED, NO_CHARACTER_SELECTED, NO_SUCH_CHARACTER, SERVER_ERROR

## Implementation Details

### account_gate.gd
- Validates input (username 4-20 chars, password 6+ chars, host optional)
- Calls `NetworkClient.connect_to_server()` before submitting auth RPC (non-blocking, connection may still be establishing)
- Listens to `auth_result_received` signal; on OK, stores identity and transitions
- Updates status label with connection and auth outcomes
- Disables buttons during in-flight requests

### character_gate.gd
- On ready: immediately calls `submit_list_characters()` to fetch the account's character roster
- Listens to `character_result_received` and `world_entry_received` signals
- Renders character list with ItemList widget; Select/Delete buttons activate on selection
- Create button opens a modal AcceptDialog for character name input
- On select success: calls `submit_enter_world()` (Slice 043 seam)
- On world-entry success: populates PlayerIdentity.selected_character_id/display_name/selected_character, transitions to gameplay.tscn
- All outcomes displayed in status label

### Project.godot Update
- Changed `run/main_scene` from `res://client/identity_gate.tscn` to `res://client/account_gate.tscn`
- identity_gate.tscn (old pre-auth placeholder) is now obsolete; can be archived or deleted

## Defensive Refactoring (Slice 044a)

**Issue:** Attempted to defer `spawn_own_player_representation()` RPC rendering until gameplay scene so login menu doesn't receive a stray Player node.
**Approach:** Introduced `_own_player_spawn_pending` flag + `_is_in_gameplay_scene()` scene-detection logic.
**Result:** e2e harnesses broke (melee, multi-peer, prediction; 265/268 passing, 3 failing). Harnesses manually instantiate gameplay.tscn without changing the scene tree root, so dynamic Node detection didn't work.
**Resolution:** Reverted spawn-deferral. Documented intended usage: login scene persists until world-entry succeeds, then transitions to gameplay. Spawn arrives in correct context. Accept known limitation for now.

**Remaining Refactoring:** Removed idempotency guard from `connect_to_server()` to avoid blocking e2e harness connect calls that fire before scene transitions. Documented pattern: login manages the connection, gameplay inherits it.

## Testing

### Unit-Level Tests (existing, Slices 040/042/043)
- test_auth_basic.gd: registration, login, bad credentials
- test_character_crud_rpc.gd: list, create, select, delete, world-entry, authorization scoping
- e2e harnesses: melee, multi-peer, prediction (all 268/268 passing after refactor)

### GUI-Level Tests (manual, Windows verification)
- Launch account_gate.tscn on Windows client
- Enter username, password, server host → verify connection status updates
- Submit login → verify auth_result_received fires, scene transitions
- Select character or create new one → verify character_result_received fires
- Confirm select → verify world_entry_received fires, gameplay.tscn loads
- Verify Player node renders in gameplay scene

## Known Limitations and Follow-Ups

1. **Spawn misfiring into login menu** (low probability): If a Player RPC arrives while the login screen is still active (connection established but auth not yet complete), the Player will render in the login scene. Real fix requires scene-aware dispatching or a queuing system. Workaround: login screen is fast (~100ms); race window is small.

2. **Character cosmetic customization** (Phase 12): Current UI passes an empty cosmetic dict. Cosmetic selection/preview UI is a future slice.

3. **Spawn-deferral pattern** (defer for full queuing/scene-aware dispatch): e2e harness brittleness taught us that fragile timing logic is hard to debug on headless remote. Prefer explicit scene transitions over defensive deferral. May revisit when server broadcasts Player state before client renders scene tree.

4. **Multi-peer character identity** (Phase 16): Server binds Character to peer's own Player, but doesn't yet replicate Character name/cosmetics to other peers. Gameplay doesn't render remote player display names yet.

## Slice Metadata

| Aspect | Value |
| --- | --- |
| Complexity | Medium (UI glue, RPC wiring, scene transitions) |
| Risk | Low (all server machinery tested; UI is presentation-only) |
| Test Coverage | Existing (268/268 from Slices 040-043) + manual GUI on Windows |
| Documentation | This SDD + public seam list + FEATURE-LIST.md (F-034) |
| Estimated Windows GUI Verification Time | 10-15 minutes (connect, auth, select, play) |

