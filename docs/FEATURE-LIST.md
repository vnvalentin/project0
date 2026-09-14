# Project0 Feature List

Status: active
Last reviewed: 2026-09-12
Owner: valentin.vn@gmail.com

## Rule

This record owns product capabilities. Each capability moves through the
delivery lifecycle defined in `DEVELOPMENT-WORKFLOW.md`: `Planned` → `Ready` →
`In Progress` (Active) → `Implemented` (Done). A capability is `Ready` only when
every originating implementation (`task`) issue under its `.scratch/<goal>/` map
is `resolved`; it becomes `Implemented` only after focused validation passes. Do
not describe planned, ready, or unvalidated work as implemented.

Stable identifiers: a feature keeps ONE identifier for life and carries its
stage in the `Status:` field. The legacy `P-`/`IP-`/`F-` prefixes are frozen,
opaque history and no longer signal status — never rename an item when its
status changes. New features take the next unused number as `F-<n>`.

Each feature identifies the user capability, problem solved, current status,
linked phase, implementation slices, public seam, and validation evidence. On
every behavior change, update the feature and append a change record stating
what changed, why, when, related work, and validation evidence.

Keep this list synchronized with `PROJECT-TRACKER.md`: update the phase work
index and its status badge whenever a feature's status or scope changes.

Delivery rule: prefer small, independently observable slices delivered
frequently over large feature batches. Every Matt Pocock, Wayfinder, or other
agent-created slice must name the feature IDs it advances, check for an
existing matching feature before adding one, and update this list and the
Project Tracker together. A slice is not complete without its SDD, BDD, TDD,
telemetry, validation, and review evidence.

Mandatory sync rule: a feature may not remain `In Progress` or `Planned` after
its public seam is live and validated. If a live implementation exists but the
status record is outdated, treat it as a process defect and correct the record in
the same change set. Document the root cause in the change history for the
feature so future drift is easier to detect.

## Planned Features

### P-005: Remote-SSH server workspace

- Status: `Planned`
- Feature: VS Code on Windows can operate the repository, Git state, database configuration, and Claude CLI on the Linux development server through Remote-SSH.
- Problem solved: The visual workstation and the authoritative development/runtime environment need a defined boundary.
- Phase: 7. Delivery workflow capabilities
- Public seam: Remote-SSH workspace configuration and documented server-side command path.
- Validation: A future operations slice must prove repository edits, Git inspection, and bounded command execution occur on the Linux host.

### P-006: Token-efficient asset quarantine

- Status: `Planned`
- Feature: Repository ignore rules quarantine heavy binary assets, including 3D meshes, textures, and music, from normal AI context and repository scans without adding service cost.
- Problem solved: Large binary assets consume model context and obscure the source files needed for reasoning.
- Phase: 7. Delivery workflow capabilities
- Public seam: `.gitignore`, scan configuration, and a documented asset validation command.
- Validation: A future slice must prove source scans exclude quarantined assets while the game/runtime asset path remains explicit and usable.

### P-009: Hardware-accelerated local inference

- Status: `Implemented`
- Feature: Server-side Ollama inference uses the local Tesla P100 and a configured Llama model for generation without external cloud inference costs. Configuration is environment-driven with safe defaults, and every request outcome is classified into bounded, non-sensitive telemetry.
- Problem solved: World generation needs an on-premise inference path with predictable ownership, no cloud token dependency, and observable request outcomes without leaking prompt content.
- Phase: 8. JIT world generation and local inference
- Public seam: `shared/local_llm_client.gd` (`resolve_config()`, `configure_from_env()`, `request_outcome_reported` signal, and bounded `outcome`/`duration_ms` result fields), `PROJECT0_OLLAMA_HOST`/`PROJECT0_OLLAMA_MODEL`/`PROJECT0_OLLAMA_TIMEOUT_SEC` environment configuration, and `tests/integration/test_client_never_contacts_ollama.gd`.
- Implementation slices: [Slice 051](slices/051-p009-hardware-accelerated-local-inference.md)
- Validation: Slice 051 covers configured-model success, HTTP error, malformed envelope, invalid inner JSON, and timeout outcomes against a hermetic fake Ollama harness, plus env-config resolution/precedence and a structural scan proving no `client/` file references Ollama. GUT validation passed 304/304 tests across 43/43 scripts and 1182 assertions, exit 0. Record sync passed with 0 errors. A live probe against the running Ollama instance (`llama3:latest` on the Tesla P100) returned a successful parsed JSON response, confirmed 2026-09-14.
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index)
- Change history:
  - Date: 2026-09-14
    What changed: Implemented Slice 051's environment-driven `LocalLLMClient`
    configuration resolver and bounded request-outcome telemetry
    (`success`/`http_error`/`malformed_envelope`/`invalid_json`/`transport_error`/`timeout`),
    with a structural test proving the client process never references Ollama.
    Why: Close the P-009 hardware-accelerated local inference contract with
    observable, non-sensitive request telemetry before boot-wiring JIT
    generation in a later slice.
    Related work: [Slice 051](slices/051-p009-hardware-accelerated-local-inference.md)

### IP-004: Structured sector blueprint translation

- Status: `Implemented`
- Feature: LLM output is validated as strict versioned JSON describing a bounded sector coordinate and floor/wall/corridor tile blueprint before server use.
- Problem solved: Free-form model output cannot safely drive authoritative world state.
- Phase: 8. JIT world generation and local inference
- Public seam: `shared/sector_blueprint_schema.gd`, `server/sector_blueprint_service.gd`, and `tests/integration/test_sector_blueprint_contract.gd`.
- Implementation slices: [Slice 008](slices/008-sector-blueprint-contract.md)
- Validation: Slice 008 covers valid, malformed, incomplete, unsupported-kind, wrong-version, out-of-bounds, HTTP failure, timeout, non-blocking, and correlation outcomes. GUT integration validation passes with 7/7 tests and 38 assertions; geometry and persistence remain future work.
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index), [Sector blueprint contract](../.scratch/game-vision/issues/15-sector-blueprint-contract.md)
- Change history:
  - Date: 2026-09-12
    What changed: Implemented Slice 008's bounded version-one blueprint
    validator and asynchronous server-side request service. Added explicit
    rejection for origin/tile coordinates beyond the contract bound, while
    preserving transport, timeout, correlation, and non-blocking behavior.
    Why: Close the structured sector blueprint translation contract before
    any geometry or persistence work.
    Related work: [Slice 008](slices/008-sector-blueprint-contract.md),
    [DT-006](TECHNICAL-DEBT-TRACKER.md#dt-006-remaining-hand-rolled-smoke-tests-not-yet-migrated-to-gut)
    (resolved by [Slice 041](slices/041-dt-006-remaining-smoke-test-gut-migration.md))
    Validation: `godot --headless -s addons/gut/gut_cmdln.gd
    -gdir=res://tests/integration -gexit` passed 7/7 tests, 24 assertions,
    exit 0; the full configured GUT suite (`scripts/run_gut_validation.sh`)
    passed 14/14 tests, 38 assertions, exit 0.

### IP-008: Just-in-time sector generation

- Status: `Implemented`
- Feature: The authoritative server detects when a Player enters a new sector and requests an unseen sector blueprint without blocking the multiplayer loop.
- Problem solved: Provisional generation existed, but nothing connected it to authoritative world movement or prevented repeated requests for the same peer/sector.
- Phase: 8. JIT world generation and local inference
- Public seam: `server/sector_boundary_detector.gd`, `server/provisional_sector_generator.gd`, and the Canon lookup boundary.
- Implementation slices: [Slice 009](slices/009-provisional-sector-generation.md), [Slice 046](slices/046-sector-boundary-detection.md), [Slice 047](slices/047-jit-result-canonicalization-replication.md)
- Validation: Slice 046 proves floor-based X/Z sector mapping, per-peer transition detection, Canon suppression, duplicate-request suppression, and live server wiring. Slice 047 closed the remaining async follow-up: valid generation results are canonicalized and only the stored Canon blueprint is reliably replicated to connected peers.
- Change history:
  - Date: 2026-09-14
    What changed: Marked IP-008 Implemented — Slice 047 delivered the async
    canonicalization/replication follow-up that Slice 046 named as remaining,
    closing the boundary→generate→canonicalize→replicate loop.
    Why: The tracker phase-8 index already badged IP-008 done; this syncs the
    feature record to that reality and to the delivered Slice 047 evidence.
    Related work: [Slice 047](slices/047-jit-result-canonicalization-replication.md)
    Validation: Full GUT 282/282 across 39/39 scripts, 1073 assertions, exit 0;
    `scripts/check_record_sync.sh` exit 0.
  - Date: 2026-09-14
    What changed: Added the authoritative sector-boundary detector that requests only unseen sectors.
    Why: Close the remaining trigger gap between validated provisional generation and live authoritative movement.
    Related work: [Slice 046](slices/046-sector-boundary-detection.md), [Slice 045](slices/045-canon-sector-persistence.md)
    Validation: Unit GUT passed 184/184 tests across 22 scripts, exit 0; server parse check passed, exit 0; full GUT passed 278/278 tests across 38/38 scripts and 1063 assertions, exit 0.

### P-011: Canonical history archive

- Status: `Implemented`
- Feature: The headless server persists validated sector history in a server-owned SQLite database.
- Problem solved: Generated world content must survive process restarts and be shared consistently by multiplayer sessions.
- Phase: 9. Canon persistence and world mutation
- Public seam: SQLite repository, schema migrations, transaction boundary, and persistence telemetry.
- Validation: Slice 045 proves restart recovery, atomic first-write handling, duplicate-coordinate behavior, server-only database ownership, and boot-time canonicalization; mutation replay remains future work.
- Implementation slices: [Slice 045](slices/045-canon-sector-persistence.md)
- Change history:
  - Date: 2026-09-14
    What changed: Started the first Canon persistence slice on the delivered server-owned SQLite foundation.
    Why: Establish durable sector history before wiring boundary-triggered JIT generation or mutable world events.
    Related work: [Slice 045](slices/045-canon-sector-persistence.md), [game-vision issue 05](../.scratch/game-vision/issues/05-define-canon-persistence.md)
    Validation: Focused integration validation passed 94/94 tests and 375 assertions, exit 0; full GUT passed 268/268 tests across 36/36 scripts, exit 0; server parse check passed, exit 0.

### P-012: One-time blueprint canonicalization

- Status: `Implemented`
- Feature: The first validated blueprint for a world coordinate is stored once and becomes immutable Canon for that coordinate.
- Problem solved: Regenerating the same coordinate could produce contradictory maps across sessions.
- Phase: 9. Canon persistence and world mutation
- Public seam: Coordinate uniqueness constraint, canonicalization transaction, and duplicate-generation outcome telemetry.
- Validation: Slice 045 proves first-write success, same-coordinate idempotency, conflicting regeneration rejection, and no partial Canon replacement.
- Implementation slices: [Slice 045](slices/045-canon-sector-persistence.md)
- Change history:
  - Date: 2026-09-14
    What changed: Started the coordinate-unique canonicalization seam.
    Why: Prevent regenerated provisional blueprints from replacing historical Canon.
    Related work: [Slice 045](slices/045-canon-sector-persistence.md)
    Validation: Focused integration validation passed 94/94 tests and 375 assertions, exit 0; full GUT passed 268/268 tests across 36/36 scripts, exit 0; server parse check passed, exit 0.

### P-013: Dynamic world mutation tracking

- Status: `In Progress`
- Feature: Generated assets and mutable entities receive stable GUIDs, and direct player-driven changes such as looting or defeating a leader persist across sessions.
- Problem solved: Mutable world state must not reset or duplicate when a sector is revisited.
- Phase: 9. Canon persistence and world mutation
- Public seam: GUID assignment, mutation event/state store, replay/load path, and mutation telemetry.
- Validation: A future slice must prove stable identity, idempotent mutation application, and rejection of unauthorized world-state changes.
- Implementation slices: [Slice 050](slices/050-canon-mutation-persistence.md)
- Change history:
  - Date: 2026-09-14
    What changed: Started the first P-013 slice — a server-only append-only Canon mutation log (`server/canon_mutation_repository.gd`) on the Slice 045 immutable sectors, keyed by a server-owned `event_id`, with an optimistic per-sector revision derived from the log.
    Why: Player-driven world changes must persist idempotently across restarts and be rejected when stale, forged, or aimed at a non-canon sector, without touching immutable sector Canon.
    Related work: [Slice 050](slices/050-canon-mutation-persistence.md), [Slice 045](slices/045-canon-sector-persistence.md), [game-vision issue 05](../.scratch/game-vision/issues/05-define-canon-persistence.md)
    Validation: Focused integration validation passed with the 11 new `test_canon_mutation_repository` cases (94 → 105 integration tests, all passing); full `scripts/run_gut_validation.sh` passed 293/293 tests across 40/40 scripts, exit 0 (`scripts_expected == scripts_ran`); server parse check passed, exit 0; record sync exit 0.

### P-014: Containerized fixed-tick authoritative server runtime

- Status: `Planned`
- Feature: The authoritative Godot server runs in an isolated Docker container with a bounded 20–30 Hz simulation tick and server-owned physics/state.
- Problem solved: Multiplayer behavior needs a reproducible Linux runtime boundary and predictable simulation cadence.
- Phase: 10. Authoritative runtime and action input
- Public seam: Server container entrypoint, tick loop, health output, and runtime telemetry.
- Validation: A future slice must prove container startup, tick-rate bounds, clean shutdown, and no client-side authority over server state.

### P-016: Biological progression and kinetic combat systems

- Status: `Planned`
- Feature: Players develop a fixed-budget six-attribute biological vessel,
  derived kinetic capabilities, permanent Meridian pathways, temporary
  Burnout, and equilibrium-bound magic through server-validated play.
- Problem solved: Combat and progression need one coherent opportunity-cost
  model that rewards embodied play without stat-gating player reasoning.
- Phase: 12. Biological progression and kinetic systems (also constrains Phase 10)
- Public seam: Future versioned shared contracts, server-owned progression and
  action-resolution services, replicated effective state, and client
  presentation/prediction adapters defined by `CLAUDE.md` and ADR 0002.
- Validation: Future slices must prove fixed-budget redistribution, trusted
  progression evidence, friction penalties, Meridian idempotency, Burnout
  expiry without base-state mutation, magic equilibrium rejection, and client
  reconciliation at public server seams.
- Related work: [Slice 010](slices/010-core-mechanics-architecture.md),
  [Slice 011](slices/011-mind-tool-architecture-refinement.md),
  [ADR 0002](adr/0002-authoritative-mechanics-and-progression.md)

The remaining scope of server-authoritative networked
multiplayer (movement synchronization, prediction, and world-state
replication) is completed in Slices 002, 004, 005, and 007.

## Ready Features

Design-complete capabilities whose originating issues are all `resolved`, ready
for a developer to pick up. No implementation has started.

## In Progress Features

### F-033: Character world entry (server binding)

- Status: `In Progress`
- Feature: An authenticated peer that has selected a Character can enter the
  world as that Character. The server resolves the selection from the session
  (the client names neither the account nor the character) and binds the
  Character's identity/cosmetic to the peer's authoritative Player, fail-closed.
- Problem solved: [F-032](#f-032-character-crud-over-the-wire-server) lets a peer
  select a Character, but nothing instantiated the in-world Player *as* that
  Character — selection had no in-world effect.
- How it solves the problem: Slice 043 adds
  `server/character_service.gd::get_selected_character(peer_id)` (derives the
  account + `selected_character_id` from the session and returns the live
  `CharacterRecord`, else `NOT_AUTHENTICATED`/`NO_CHARACTER_SELECTED`/
  `NO_SUCH_CHARACTER`), `server/server_player_state.gd::bind_character()`
  (identity/cosmetic only — position/combat authority unchanged), and additive
  `submit_enter_world`/`receive_enter_world_request_on_server`/
  `receive_enter_world_result`/`world_entry_received` on
  `client/network_client.gd`, following the Slice 040/042 forwarding pattern.
  The RPC receiver resolves the Character via `CharacterService` and binds it to
  the peer's `ServerPlayerState` (both `/root` nodes). Additive: the connect-time
  anonymous spawn is unchanged, so the real-server e2e harnesses stay green.
  **Slice 044 adds client login/register and character select/create UI screens**
  (account_gate.tscn, character_gate.tscn, updated project.godot main_scene).
  The server portion of F-033 is complete; GUI confirmation on Windows pending.
- Phase: 14. Player accounts and characters
- Implementation slices: [Slice 043](slices/043-character-world-entry.md),
  [Slice 044](slices/044-client-login-character-ui.md) (GUI scaffolding, Windows verification pending).
- Public seam: `server/character_service.gd` (`get_selected_character`);
  `server/server_player_state.gd` (`bind_character`, `character_id`,
  `character_display_name`, `character_cosmetic`); `client/network_client.gd`
  (`submit_enter_world`, `world_entry_received`); `client/player_identity.gd`
  (account_id, username, selected_character_id, selected_character, display_name,
  target_host); `account_gate.tscn`/`account_gate.gd` (login/register UI);
  `character_gate.tscn`/`character_gate.gd` (character select/create UI).
- Validation: `tests/integration/test_character_crud_rpc.gd`'s world-entry
  scenario (unauthenticated / unselected refused; selected resolves). Full suite
  `scripts/run_gut_validation.sh` 268/268 across 36 scripts, exit 0
  (`scripts_expected == scripts_ran == 36`); `scripts/check_record_sync.sh` exit 0.
  GUI visual validation on Windows: login → character select → gameplay flow.
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index),
  [player-accounts spec](../.scratch/player-accounts/spec.md),
  [F-032](#f-032-character-crud-over-the-wire-server) (the consumed CRUD/session seam),
  [Slice 044 SDD](slices/044-client-login-character-ui.md).
- Change history:
  - Date: 2026-09-13
    What changed: Opened F-033 via Slice 043 — added `get_selected_character`,
    `bind_character`, and the additive `enter_world` RPCs; validated at 268/268.
    Client screens (spec slice 5) scaffolded in Slice 044; GUI verification pending.
  - Date: 2026-09-13
    What changed: Slice 044 scaffolding complete — client login/register
    (account_gate) and character select/create (character_gate) UI scenes and
    controllers added; project.godot main_scene updated to account_gate.tscn;
    all 268/268 tests still passing.
    Why: Prepare client UI for Windows GUI verification before full Phase 14
    completion.
    Related work: [Slice 044](slices/044-client-login-character-ui.md)
    Validation: `scripts/run_gut_validation.sh` 268/268, exit 0.

### F-034: Client login and character selection screens

- Status: `In Progress`
- Feature: Client-side UI for account login/registration and character
  selection/creation, wired to Phase 40-43 server-side authentication, character
  CRUD, and world-entry machinery.
- Problem solved: Phase 40-43 delivers server-side identity binding and
  character management, but has no client GUI — all RPC testing occurs in
  headless integration harnesses. End-to-end gameplay requires visual login and
  character screens.
- How it solves the problem: Slice 044 scaffolds two scenes:
  - `account_gate.tscn`/`account_gate.gd`: username/password/host inputs,
    login/register buttons, status display. Validates input (username 4-20 chars,
    password 6+ chars), opens connection, submits auth RPC, listens to
    `auth_result_received` signal, stores account_id/username in `PlayerIdentity`,
    transitions to character_gate.tscn on success.
  - `character_gate.tscn`/`character_gate.gd`: character roster ItemList,
    select/create/delete buttons, status display. On ready: fetches character
    list via `submit_list_characters()`. Select/create/delete operations dispatch
    appropriate RPC and listen to `character_result_received`. On select success:
    calls `submit_enter_world()` (Slice 043 seam). On world-entry success:
    stores selected_character_id/display_name/selected_character in PlayerIdentity,
    transitions to gameplay.tscn.
  - `project.godot`: main_scene changed from `identity_gate.tscn` (old placeholder)
    to `account_gate.tscn`.
  - `connection_status.gd`: updated to call `connect_to_server()` safely
    (no second peer if already connected; intended pattern is login manages the
    connection, gameplay inherits it).
  - `player_identity.gd`: restructured to hold account_id, username,
    selected_character_id, selected_character dict, display_name, target_host
    (was: only display_name + target_host).
- Phase: 14. Player accounts and characters
- Implementation slices: [Slice 044](slices/044-client-login-character-ui.md)
- Public seam: `account_gate.tscn`/`account_gate.gd`;
  `character_gate.tscn`/`character_gate.gd`; `player_identity.gd` new fields;
  `project.godot` run/main_scene.
- Validation: Unit tests remain green (268/268, Slices 040-043). GUI validation:
  Windows client launch → login with valid credentials → character select →
  enter world → gameplay.tscn renders Player without errors.
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index),
  [F-033](#f-033-character-world-entry-server-binding) (consumed server seams),
  [Slice 044 SDD](slices/044-client-login-character-ui.md).
- Change history:
  - Date: 2026-09-13
    What changed: Opened F-034 via Slice 044 — scaffolded account_gate and
    character_gate UI scenes + controllers, updated project.godot main_scene,
    restructured PlayerIdentity, refined connect_to_server() documentation.
    Why: Enable Windows GUI verification of login → character select → world-entry
    flow before Phase 14 completion.
    Validation: `scripts/run_gut_validation.sh` 268/268, exit 0.
    Known limitation: spawn-deferral abandoned after e2e harness brittleness;
    login scene persists until world-entry succeeds, then transitions to
    gameplay — intended pattern to avoid misrouted Player spawns.


### F-032: Character CRUD over the wire (server)

- Status: `In Progress`
- Feature: An authenticated peer can list, create, select, and soft-delete its
  own Characters over the ENet link. The server scopes every operation to the
  peer's session account — the client never supplies an `account_id` — and
  enforces the 5-Character cap, global live-name uniqueness, and ownership,
  returning typed `CharacterRecord` DTOs or a bounded rejection, session-gated
  and fail-closed.
- Problem solved: [F-030](#f-030-accounts-and-characters-persistence-repository)'s
  repository can create/select/delete Characters and
  [F-031](#f-031-account-authentication-and-session-server) can authenticate a
  peer, but nothing connected the two over the wire: a logged-in peer had no
  way to manage its roster, and no seam enforced that a peer can only touch its
  own account's Characters.
- How it solves the problem: Slice 042 adds `server/character_service.gd`
  (`class_name CharacterService`, a `/root` Node like `AuthService`) with
  session-gated `list_characters`/`create_character`/`select_character`/
  `delete_character`. Each method requires an authenticated session (else a
  bounded `NOT_AUTHENTICATED` with no side effect) and derives `account_id`
  from the caller's `SessionRegistry` session — never from the client — so a
  peer authenticated as account A cannot list/select/delete account B's
  Character even when it knows B's `character_id`. `shared/character_record.gd`
  gains additive pure `to_wire_dict()`/`from_wire_dict()` so a `CharacterRecord`
  crosses the RPC boundary as a client-safe DTO (fail-closed parse; no
  credential material). `client/network_client.gd` gains four additive C→S
  character request RPCs, matching `submit_*` helpers, and a
  `receive_character_result` S→C RPC (bounded outcome + wire dicts only — never
  the `detail` string), following the Slice 040 auth-RPC pattern.
  `server/session_registry.gd` gains an additive `selected_character_id` (set
  by `select`, for the future world-entry slice), and
  `server/auth_service.gd` gains a `get_session_registry()` getter so
  `server_main.gd` shares one `SessionRegistry` instance between auth and
  character CRUD.
- Phase: 14. Player accounts and characters
- Implementation slices: [Slice 042](slices/042-character-crud-rpc.md)
- Public seam: `server/character_service.gd` (`CharacterService.list_characters`,
  `create_character`, `select_character`, `delete_character`);
  `shared/character_record.gd` (`to_wire_dict`, `from_wire_dict`);
  `server/session_registry.gd` (`set_selected_character`,
  `get_selected_character`); `client/network_client.gd`
  (`submit_list_characters`, `submit_create_character`, `submit_select_character`,
  `submit_delete_character`, `character_result_received`).
- Validation: `tests/integration/test_character_crud_rpc.gd` (session-gating,
  the account-scoping authorization proof, cap/name-taken/name-invalid, select
  records the selection + refreshes `last_played_at`, soft-delete) and the
  extended `tests/unit/test_character_record.gd` wire round-trip. Full suite
  `scripts/run_gut_validation.sh` 267/267 across 36 scripts, exit 0
  (`scripts_expected == scripts_ran == 36`); `scripts/check_record_sync.sh`
  exit 0.
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index),
  [player-accounts spec](../.scratch/player-accounts/spec.md),
  [F-031](#f-031-account-authentication-and-session-server) (the consumed
  auth/session seam), [F-030](#f-030-accounts-and-characters-persistence-repository)
  (the consumed repository).
- Change history:
  - Date: 2026-09-13
    What changed: Opened F-032 via Slice 042 — added `CharacterService`, the
    additive `CharacterRecord` wire serialization, the session
    `selected_character_id`, the `AuthService` session-registry getter, and the
    four character CRUD RPCs; validated at 267/267.

### F-031: Account authentication and session (server)

- Status: `In Progress`
- Feature: A connected peer can register a new Account or log in to an
  existing one over the ENet link; the server verifies credentials with
  PBKDF2-HMAC-SHA256 off the main thread, binds an opaque in-memory session to
  the peer on success, and returns an `AccountHandle` or a bounded rejection —
  all server-authoritative and fail-closed. Auth is additive: the existing
  connect → (blueprint, spawn, house, replication) lifecycle is unchanged and
  the world stays always-playable with no login required yet.
- Problem solved: [F-030](#f-030-accounts-and-characters-persistence-repository)'s
  repository can durably store credential bytes but has no RPC, no hashing,
  and no session concept — nothing in the running server actually computes or
  verifies a PBKDF2 hash, and no peer can be told "you are Account X" for the
  lifetime of a connection.
- How it solves the problem: Slice 040 adds `server/password_hasher.gd`
  (`class_name PasswordHasher`) — a from-scratch RFC 8018 PBKDF2-HMAC-SHA256
  block construction on top of Godot `Crypto.hmac_digest` (Godot has no native
  PBKDF2), 16-byte CSPRNG salt, 32-byte key, `constant_time_compare`
  verification — and `server/session_registry.gd` (`class_name
  SessionRegistry`), an in-memory `peer_id -> session` binding that is never
  persisted and is cleared on disconnect. `server/auth_service.gd`
  (`class_name AuthService`) wires both to the F-030 repository: `register`
  auto-authenticates on success; `login` verifies and binds a session;
  unknown-username and wrong-password both reject with the identical
  `BAD_CREDENTIALS` reason (no user enumeration), and the unknown-username
  path still pays the full hashing cost so the timing is indistinguishable
  too. `client/network_client.gd` gains additive
  `receive_register_request_on_server`/`receive_login_request_on_server`
  C→S RPCs and a `receive_auth_result` S→C RPC (`AccountHandle` fields only —
  never salt/hash), following the existing
  `receive_input_intent_on_server`/`receive_authoritative_position` pattern.
  `server/server_main.gd` now opens a real `SqliteStore` and calls
  `AccountCharacterRepository.ensure_schema()` at boot — the first runtime
  consumer of the F-029/F-030 persistence stack — and fails closed (refuses to
  start) if either step fails, matching the existing hub-fixture check.
- Threading: PBKDF2 at a real iteration count is deliberately slow (~1s CPU on
  this host at 100000 iterations). `AuthService.register`/`login` dispatch the
  hash/verify call to a `WorkerThreadPool` task and `await` a
  `process_frame` poll loop for its completion, so the authoritative
  simulation tick and every other connected peer's movement/combat processing
  never stall while a hash runs — see
  [Slice 040](slices/040-account-auth-session.md#threading) for detail.
- Phase: 14. Player accounts and characters
- Implementation slices: [Slice 040](slices/040-account-auth-session.md)
- Public seam: `server/password_hasher.gd` (`PasswordHasher.hash_password`,
  `verify_password`); `server/session_registry.gd` (`SessionRegistry.bind`,
  `is_authenticated`, `get_session`, `clear`); `server/auth_service.gd`
  (`AuthService.register`, `login`, `is_authenticated`, `clear_session`);
  `client/network_client.gd` (`submit_register`, `submit_login`,
  `auth_result_received`).
- Validation: Focused `tests/unit/test_password_hasher.gd` 7/7 (including a
  published PBKDF2-HMAC-SHA256 known-answer vector) and
  `tests/integration/test_account_auth_session.gd` 8/8. Full suite
  `scripts/run_gut_validation.sh` 248/248 across 32 scripts, exit 0
  (`scripts_expected == scripts_ran == 32`). Manual runtime boot smoke
  confirmed the accounts DB opens/ensures schema and the server still reaches
  `Server listening` with the existing connect lifecycle unchanged.
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index),
  [player-accounts spec](../.scratch/player-accounts/spec.md),
  [F-030](#f-030-accounts-and-characters-persistence-repository) (the
  consumed repository), [F-029](#f-029-shared-server-owned-sqlite-persistence-foundation)
  (the consumed SQLite engine foundation).
- Change history:
  - Date: 2026-09-13
    What changed: Opened F-031 via Slice 040 — added `PasswordHasher`,
    `SessionRegistry`, `AuthService`, the additive register/login/auth_result
    RPC seam, and `server_main.gd` boot wiring that opens the accounts SQLite
    store and ensures its schema for the first time at runtime.
    Why: Phase 14's spec needs real credential verification and a session
    concept before Character CRUD (slice 4) or client screens (slice 5) can be
    built; this is the next unblocked slice now that F-030's repository is
    delivered.
    Validation: Focused suites 7/7 and 8/8; full GUT suite 248/248 across 32
    scripts, exit 0.

### F-035: Secure Windows tunnel enrollment and credential storage

- Status: `In Progress`
- Feature: A Windows client provisions its own WireGuard peer from a single-use
  invite, stores the private key with Windows DPAPI, starts the in-process
  tunnel without a batch file, and supports operator revocation without
  distributing a shared tester key.
- Problem solved: The current WAN verifier embeds a disposable private key in
  a one-click executable. That is convenient for validation but recoverable by
  anyone who receives the executable and cannot scale to multiple testers.
- How it solves the problem: Slice 054 generates the client keypair
  locally, redeem the existing enrollment service using only the public key,
  protect the private key with a user-scoped Windows DPAPI wrapper, and load
  the resulting peer configuration at application startup. The existing
  `wgnetstack` tunnel seam remains the transport adapter; the key never enters
  Git, telemetry, HTTP requests, or a distributable binary.
- Deployment boundary: the Linux host builds and runs the independent
  `infra/enrollment` FastAPI service behind `enroll.valentin.vip`; the Windows
  client only calls its `/redeem` endpoint and never owns the enrollment
  service, OPNsense credentials, or allocation database.
- Phase: 13. Public game access
- Implementation slices: [Slice 054](slices/054-secure-windows-tunnel-enrollment.md)
- Public seam: Windows bootstrapper/enrollment client, `POST /redeem`, DPAPI
  credential store, and the existing `NetworkClient` tunnel startup seam.
- Validation: Future Slice 054 evidence must cover fresh enrollment, persisted
  restart, malformed/expired invite rejection, DPAPI access scoping, revoked
  peer rejection, and a one-launch WAN gameplay run. The current embedded-key
  verifier remains a temporary validation artifact until then.
- Related work: [P-024](#p-024-public-game-access-via-opnsense-native-wireguard),
  [Slice 048](slices/048-wireguard-enrollment-service.md),
  [Slice 049](slices/049-wireguard-revocation-lifecycle.md),
  [Slice 054](slices/054-secure-windows-tunnel-enrollment.md).
- Change history:
  - Date: 2026-09-14
    What changed: Started Slice 054 implementation with a Windows one-click
    launcher that generates an X25519 keypair, redeems only the public key,
    protects the private key with DPAPI, and reuses the protected peer state.
    Validation: Windows launcher tests and release build pass; live enrollment
    service deployment and fresh-invite WAN proof remain pending.
  - Date: 2026-09-14
    What changed: Queued F-035 after user-confirmed WAN connectivity using the
    temporary embedded-key launcher.
    Why: Replace recoverable shared tester credentials with per-client
    enrollment and OS-protected private-key storage without interrupting the
    verified WAN path.

### P-024: Public game access via OPNsense-native WireGuard

- Status: `In Progress`
- Feature: Remote players reach the home-hosted authoritative server over a
  split-tunnel WireGuard connection — an in-process userspace netstack
  GDExtension in the Godot client, an invite-code enrollment service, and
  OPNsense-managed peers — without a VPS, OS admin rights, or exposing the LAN.
- Problem solved: The server is only reachable on the LAN today; public play
  needs secure remote access that neither routes through a cloud relay nor
  grants tunnel clients broader reach than the single game host.
- How it solves the problem so far: Slice 028 opens the first implementation
  slice against the design-complete basis — a dedicated, isolated OPNsense
  WireGuard instance (`wg0`, UDP 51900, `10.77.0.0/24`) split-tunneled to
  `192.168.1.254:9999` only, server-side firewall isolation
  (pass WG→game-host, default-deny WG→LAN), a host-side firewall lockdown on
  `192.168.1.254` (accept UDP 9999 only from `10.77.0.0/24`), and one
  hand-enrolled Windows tester peer. This is a records-first handoff: the SDD/
  BDD/validation plan is recorded now; `infra/opnsense/setup_wireguard_game_tunnel.py`,
  `ci/host-firewall-helper.sh`, and live execution evidence are owned by
  Copilot in a follow-up. The existing admin WireGuard server (UDP 51820 /
  `10.14.0.0/24`) is untouched. [Slice 032](slices/032-wgnetstack-netstack-bridge-linux-prototype.md)
  then proves the S2 in-client `wgnetstack` bridge itself: a `native/wgnetstack/`
  Go module embeds `wireguard-go` netstack (real loopback UDP socket, real
  WireGuard handshake against the live OPNsense endpoint, real netstack UDP
  dial to the live game host) with no OS TUN device and no admin rights. The
  existing Godot client's ENet connection was proven to complete through the
  bridge on Linux and reach the full `connected: player spawned` state against
  the live, restarted game server. An earlier run had shown `status: connected`
  without the player-spawned transition and a `receive_monster_position`
  convert error; re-running against a freshly restarted server (and an
  identical direct, no-bridge run against that same server) reproduced neither
  symptom, confirming the gap was a stale server process still executing
  pre-Slice-033 `network_client.gd` (an RPC method-table mismatch), not a
  bridge defect or a genuine type bug in Slice 033's monster-replication code.
  [Slice 034](slices/034-wgnetstack-godot-gdextension-tunnel-integration-linux.md)
  delivers S3a: `native/wgnetstack/gdext/`, a godot-cpp GDExtension that
  registers a `WgNetstack` class (`start(config: Dictionary) -> int`,
  `stop() -> void`) linking a new `cmd/cgoarchive` static build of the same
  bridge logic, plus a `client/network_client.gd` tunnel-mode code path
  (`PROJECT0_TUNNEL`, default off) so the client opens the tunnel in-process
  with no separate probe process.
  [Slice 035](slices/035-wgnetstack-windows-dll-client-repackage.md) delivers
  S3b: the GDExtension cross-compiled to a PE32+ Windows DLL (mingw) and bundled
  in the portable Windows client (`dist/Project0-client-windows-x64-0.7.0-tunnel.zip`),
  so a tester runs one executable with the tunnel available. Slice 035's
  Windows *runtime* spawn-through-tunnel proof is now user-confirmed
  (2026-09-14): a remote Windows tester ran the packaged in-process tunnel
  client and reached the in-world state against the home-hosted authoritative
  server over the public WAN split-tunnel.
  [Slice 048](slices/048-wireguard-enrollment-service.md) delivers the
  invite-code enrollment service's logic (issue 04): a FastAPI service under
  `infra/enrollment/` with single-use CSPRNG invite codes, strict
  client-public-key validation (the private key is never transmitted), `/32`
  allocation from `10.77.0.0/24`, and OPNsense `client/addClient` +
  `service/reconfigure` registration behind an injectable client interface so
  tests never make a live call — fail-closed, so an upstream OPNsense failure
  rolls back with no local allocation and no invite marked redeemed.
  [Slice 049](slices/049-wireguard-revocation-lifecycle.md) delivers the
  revocation/ban lifecycle's logic (issue 06): `RevocationService.revoke()`
  looks up a peer by its public key, calls OPNsense `client/delClient/<uuid>`
  then `service/reconfigure` through the same injectable client interface,
  and only then releases the local `/32` allocation so it re-enters the free
  pool — fail-closed, so an upstream delete/reconfigure failure leaves the
  peer's allocation and OPNsense registration untouched for an operator
  retry, and revoking an unknown or already-revoked key is an idempotent
  no-op. Both slices are service logic proven by automated tests; live
  deployment behind `enroll.valentin.vip`, the real ~25s tunnel-teardown
  timing, and idempotent re-enrollment (reusing an existing peer UUID) remain
  open.
- Ready basis: all six `.scratch/wan-wireguard/` issues are `resolved`
  (SDD-GAME-WG-001).
- Phase: 13. Public game access
- Public seam: `infra/opnsense/setup_wireguard_game_tunnel.py` and
  `ci/host-firewall-helper.sh` (Slice 028); `native/wgnetstack/` producing
  `libwgnetstack.so`/`wgnetstack.dll` with C-exported `wgnetstack_start`/
  `wgnetstack_stop` (Slice 032); `infra/enrollment/service.py`'s
  `EnrollmentService.redeem()`, exposed over HTTP as `POST /redeem` by
  `infra/enrollment/app.py` and over a CLI by `infra/enrollment/cli.py`
  (Slice 048); `infra/enrollment/service.py`'s `RevocationService.revoke()`,
  exposed only over the operator CLI as
  `infra/enrollment/cli.py revoke-peer <public_key>`, deliberately with no
  HTTP admin route (Slice 049). The Godot `.gdextension` binding is
  separately scoped; the enrollment service's live nginx/TLS deployment
  remains a follow-up ops step.
- Validation: Slice 028's acceptance evidence is an external WireGuard peer
  handshake, split-tunnel isolation proof (game host reachable, LAN
  default-denied) from inside the tunnel, the host firewall dropping
  untunneled direct hits to 9999, and one Windows peer connecting the Godot
  client. Slice 032's acceptance evidence is the same Godot client connecting
  through the in-process `wgnetstack` loopback bridge instead; the ENet
  connection handshake through the tunnel is proven on Linux, and the full
  `connected: player spawned` string is observed end to end against the live,
  restarted game server, with an identical direct (no-bridge) run against the
  same server confirming the earlier gap was a stale-server RPC method-table
  mismatch rather than a bridge or monster-replication defect. The Windows DLL
  cross-compile and `.gdextension` packaging (Slice 035) are delivered, and the
  remote-Windows WAN runtime is now user-confirmed (2026-09-14). Slice 048's
  acceptance evidence is `python3 -m pytest infra/enrollment/tests -q`, 39
  passed, exit 0, covering normal redemption, single-use re-redeem rejection,
  pool exhaustion, invalid/expired codes, malformed public keys, and an
  OPNsense-failure rollback that leaves no partial durable state — all against
  a fake OPNsense client and a temp sqlite DB, never a live call. Slice 049's
  acceptance evidence is `python3 -m pytest infra/enrollment/tests -q`, 54
  passed, exit 0 (39 pre-existing plus 15 new), covering revoking an active
  peer (frees its `/32` for reuse), an idempotent no-op on an unknown/already-
  revoked key, and fail-closed rejection on both `delClient` and
  `reconfigure` upstream failures (no local release, retry succeeds once
  healthy) — again all against a fake OPNsense client and a temp sqlite DB.
  Future slices still owe live OPNsense wiring behind `enroll.valentin.vip`,
  the real tunnel-teardown timing within one keepalive interval, and
  idempotent re-enrollment.
- Change history:
  - Date: 2026-09-14
    What changed: Delivered Slice 048, the invite-code enrollment service's
    logic and full automated test coverage (39/39 passing), against issue 04's
    resolved design. Single-use invites, strict public-key validation, `/32`
    pool allocation, and an injectable OPNsense client keep every rejection
    path (bad/expired/redeemed code, malformed key, exhausted pool, upstream
    failure) side-effect-free.
    Why: Growing Phase 13 beyond the single hand-enrolled Slice 028 tester
    peer requires a self-serve, single-use, auditable enrollment path with no
    partial state on failure, per issue 04's resolved design.
    Related work: [Slice 048](slices/048-wireguard-enrollment-service.md)
    Validation: `python3 -m pytest infra/enrollment/tests -q` passed 39/39,
    exit 0; `scripts/check_record_sync.sh` passed with 0 errors and 6
    pre-existing warnings, exit 0. No `.gd` files changed, so the GUT suite
    was not run.
  - Date: 2026-09-14
    What changed: Recorded the user-confirmed WAN runtime proof — a remote
    Windows tester ran the packaged in-process tunnel client and reached the
    in-world state over the public WAN split-tunnel, closing Slice 035's
    tester-owned open item.
    Why: WAN connectivity is the core Phase 13 milestone; the record must
    reflect the confirmed runtime evidence (same basis as DT-003/DT-004
    user-confirmed GUI/LAN runs). Invite enrollment (issue 04) and revocation
    (issue 06) remain the open Phase 13 gate items.
    Related work: [Slice 035](slices/035-wgnetstack-windows-dll-client-repackage.md)
    Validation: User-confirmed remote-Windows WAN run (2026-09-14); no automated
    GUT seam covers a live WAN hop.
  - Date: 2026-09-14
    What changed: Delivered Slice 049, the peer revocation/ban lifecycle's
    logic and full automated test coverage, against issue 06's resolved
    design. `RevocationService.revoke()` deletes the peer on OPNsense
    (`delClient` + `reconfigure`) before releasing its local `/32`
    allocation, keyed on the peer's public key; every rejection path
    (`UPSTREAM_DELETE_FAILED`) is fail-closed with no local mutation, and
    revoking an unknown or already-revoked key is an idempotent
    `ALREADY_ABSENT` no-op. Revocation is CLI/operator-only
    (`infra/enrollment/cli.py revoke-peer`); no HTTP admin route was added.
    Idempotent re-enrollment (reusing an existing peer UUID) was deliberately
    deferred as a documented follow-up.
    Why: A ban must actually revoke tunnel access — an enrollment path with
    no matching revocation path lets a banned player keep working WireGuard
    access and leaks `/32` addresses forever, per issue 06's resolved design.
    Related work: [Slice 049](slices/049-wireguard-revocation-lifecycle.md)
    Validation: `python3 -m pytest infra/enrollment/tests -q` passed 54/54
    (39 pre-existing, 15 new), exit 0; `scripts/check_record_sync.sh` passed
    with 0 errors and 6 pre-existing warnings, exit 0. No `.gd` files
    changed, so the GUT suite was not run.
- Related work: [Public Game Access via WireGuard map](../.scratch/wan-wireguard/map.md),
  [ENet netstack bridging](../.scratch/wan-wireguard/issues/01-enet-transport-netstack-bridging.md),
  [GDExtension netstack prototype](../.scratch/wan-wireguard/issues/02-godot-gdextension-wireguard-netstack.md),
  [OPNsense infra automation](../.scratch/wan-wireguard/issues/03-opnsense-wireguard-infra-automation.md),
  [enrollment invite service](../.scratch/wan-wireguard/issues/04-enrollment-service-invite-system.md),
  [host firewall lockdown](../.scratch/wan-wireguard/issues/05-host-firewall-lockdown-script.md),
  [revocation and ban lifecycle](../.scratch/wan-wireguard/issues/06-revocation-and-ban-lifecycle.md),
  [Slice 028](slices/028-wireguard-remote-access-infrastructure-foundation.md)

### IP-023: Basic monster combat

- Status: `Implemented`
- Feature: Server-authoritative "basic monsters" the player can fight — a flat
  HP/damage/death model now, with a detect/chase/attack AI and spawning to
  follow.
- Problem solved: The world has a stationary target dummy but no actual enemy
  with health that can be defeated; the starting area needs something to fight.
- How it solves the problem so far: Slice 020 adds `shared/monster_contracts.gd`
  (`MonsterContracts`) — a provisional flat `MonsterCombatState`
  (`current_hp`/`max_hp`/`target_id`, `apply_damage` clamped at 0 and reporting
  the death transition exactly once, `is_dead`) with fixed `MAX_HP`/`DAMAGE_PER_HIT`
  constants (a deterministic 3 hits to defeat) — and a new `COMBAT_EVENT_DEATH`
  kind on `shared/combat_contracts.gd` reusing the existing `CombatEvent` shape.
  Slice 021 adds `server/server_monster_state.gd`, the authoritative
  detect → chase → windup → attack → recovery state machine with a dodge-able
  telegraph, reuse of the shared reach/arc hit test, and per-transition/attack/
  death telemetry. Slice 022 adds `server/server_monster_manager.gd`, which
  spawns one monster per town spawn point (authored outside the town wall),
  drives them each server frame against the nearest player, and respawns
  defeated monsters after a cooldown at a position clamped to stay outside the
  town. Slice 029 wires a player's already-accepted authoritative melee hit to
  monster damage and death: `ServerPlayerState`'s ACTIVE-phase hit test is
  generalized to also check every currently-living monster (injected via
  `set_monster_manager`, duck-typed on `.position` alongside the existing
  target dummies) and still only emits the existing `COMBAT_EVENT_HIT`;
  `ServerMonsterManager.receive_player_hit` is the sole seam that applies
  `DAMAGE_PER_HIT` and reports a defeat, and `server_main.gd` routes that HIT
  to it and broadcasts an attacker-attributed `COMBAT_EVENT_DEATH` over the
  same existing channel when it lands the killing blow. Monsters are now fully
  fightable and defeatable server-side. Slice 033 closes the remaining
  implementation gap: `client/monster.gd`/`client/monster.tscn` is a purely
  cosmetic per-living-monster node — spawned, positioned, and despawned only in
  reaction to server broadcasts, and reacting visually to the existing
  `COMBAT_EVENT_HIT`/`COMBAT_EVENT_DEATH` events — so monsters are now visible
  to and fightable by players, not just authoritatively simulated. It decides
  nothing itself: no damage, hit, death, or respawn logic runs on the client.
  With Slice 033 in place the feature is complete: headless GUT coverage and a
  headless `connected: player spawned` connect proof pass, and interactive GUI
  visual/fight confirmation was obtained on 2026-09-13 — a human ran the
  graphical client against the live server and saw the monster render, chase,
  flash on each hit, die on the third hit, and respawn. IP-023 is
  `Implemented`.
- Phase: 10. Authoritative runtime and action input
- Implementation slices: [Slice 020](slices/020-monster-hp-damage-death.md), [Slice 021](slices/021-monster-ai-state-machine.md), [Slice 022](slices/022-monster-spawning-and-respawn.md), [Slice 029](slices/029-authoritative-monster-melee-damage.md), [Slice 033](slices/033-client-monster-replication-and-rendering.md)
- Public seam: `shared/monster_contracts.gd`
  (`MAX_HP`, `DAMAGE_PER_HIT`, `WINDUP_TICKS`, `ATTACK_ACTIVE_TICKS`,
  `RECOVERY_TICKS`, `DETECTION_RADIUS_YARDS`, `CHASE_SPEED_YARDS_PER_SEC`,
  `MONSTER_REACH_YARDS`, `MONSTER_ARC_DEGREES`, `PHASE_*`, `MonsterCombatState`,
  `default_monster`, `monster_attack_archetype`), `shared/combat_contracts.gd`
  (`COMBAT_EVENT_DEATH`), `server/server_monster_state.gd`
  (`advance`, `receive_damage`, `phase_changed`, `attack_resolved`, `died`),
  `server/server_monster_manager.gd` (`advance_all`, `monster_at`,
  `monster_count`, `living_count`, `living_targets`, `receive_player_hit`,
  `monster_died`, `monster_respawned`),
  `server/server_player_state.gd` (`set_monster_manager`, its generalized
  `_perform_hit_test`), `server/starting_town_hub_fixture.gd` (spawn points
  outside the town wall), `client/monster.gd`/`client/monster.tscn`
  (`spawn_monster_representation`, `receive_monster_position`,
  `despawn_monster_representation`, hit/death reaction), `client/network_client.gd`
  (monster replication RPCs), `server/server_main.gd` (monster broadcast
  wiring).
- Validation: See [Slice 020](slices/020-monster-hp-damage-death.md),
  [Slice 021](slices/021-monster-ai-state-machine.md),
  [Slice 022](slices/022-monster-spawning-and-respawn.md),
  [Slice 029](slices/029-authoritative-monster-melee-damage.md), and
  [Slice 033](slices/033-client-monster-replication-and-rendering.md) for exact
  commands and results (Slice 029: 11/11 manager + 9/9 authoritative-melee
  focused tests, 177/177 full suite, exit 0; Slice 033: 4/4 unit +
  7/7 integration focused tests, full gate `scripts/run_gut_validation.sh`
  26/26 scripts, 199/199 tests, 793 asserts, exit 0, plus a headless
  `connected: player spawned` connect proof and a clean monster-broadcast
  runtime run with zero RPC errors; interactive GUI visual/fight confirmation
  was obtained 2026-09-13, human-confirmed).
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index),
  [Basic Monsters map](../.scratch/basic-monsters/map.md),
  [issue 01](../.scratch/basic-monsters/issues/01-hp-damage-death-model.md),
  [issue 02](../.scratch/basic-monsters/issues/02-monster-state-machine-with-telegraph.md),
  [issue 03](../.scratch/basic-monsters/issues/03-monster-spawn-points-from-town-schema.md)
- Change history:
  - Date: 2026-09-12
    What changed: Implemented Slice 020 — the provisional flat monster
    HP/damage/death contract and the shared `COMBAT_EVENT_DEATH` kind, the first
    Basic Monsters slice.
    Why: Give the detect/chase/attack monster AI (next slice) a validated,
    bounded combat contract to build on before any runtime or spawning.
    Related work: [Slice 020](slices/020-monster-hp-damage-death.md)
    Validation: See Slice 020 validation section.
  - Date: 2026-09-12
    What changed: Implemented Slice 021 — the authoritative detect → chase →
    windup → attack → recovery state machine (`server/server_monster_state.gd`)
    with a dodge-able attack telegraph, reuse of the shared reach/arc hit test,
    per-transition/attack/death telemetry signals, and a binding
    `WINDUP_TICKS >= player windup` fairness regression test.
    Why: Give the monster real, readable authoritative behavior before wiring
    spawning and the server tick loop.
    Related work: [Slice 021](slices/021-monster-ai-state-machine.md)
    Validation: See Slice 021 validation section.
  - Date: 2026-09-12
    What changed: Implemented Slice 022 — `server/server_monster_manager.gd`,
    which spawns one monster per town spawn point (authored outside the town
    wall in the hub fixture), drives their AI each server frame against the
    nearest player, and respawns defeated monsters after a cooldown at a
    position clamped to stay outside the town, wired into the server's
    `physics_frame` loop with death/respawn telemetry.
    Why: Complete the Basic Monsters map's spawning/respawn ticket server-side,
    honoring the caveat that monsters spawn outside the town boundary.
    Related work: [Slice 022](slices/022-monster-spawning-and-respawn.md)
    Validation: See Slice 022 validation section.
  - Date: 2026-09-13
    What changed: Implemented Slice 029 — wired a player's accepted
    authoritative melee hit to monster damage and death. Generalized
    `ServerPlayerState`'s ACTIVE-phase hit test to also check every
    currently-living monster (via a new `ServerMonsterManager.living_targets()`
    snapshot, duck-typed on `.position` alongside the existing target dummies),
    added `ServerMonsterManager.receive_player_hit` as the sole seam that
    applies `DAMAGE_PER_HIT` and reports a defeat, and extended
    `server_main.gd`'s existing HIT-broadcast routing to also broadcast an
    attacker-attributed `COMBAT_EVENT_DEATH` over the same channel when a hit
    lands the killing blow. Monster mutation stays single-owned by
    `ServerMonsterManager`; `ServerPlayerState` still only resolves geometry.
    Why: Complete the server-authoritative half of the "make monsters visible
    to and fightable by players" boundary recorded in Slice 022's next
    boundary, so monsters are now genuinely damageable and defeatable in the
    live server loop; client rendering follows as a later slice.
    Related work: [Slice 029](slices/029-authoritative-monster-melee-damage.md)
    Validation: See Slice 029 validation section.
  - Date: 2026-09-13
    What changed: Implemented Slice 033 — client-side monster replication and
    rendering. Added `client/monster.gd`/`client/monster.tscn`, a purely
    cosmetic node per living monster, spawned/positioned/despawned only by
    server broadcasts and reacting visually to the existing
    `COMBAT_EVENT_HIT`/`COMBAT_EVENT_DEATH` events, plus the corresponding
    monster-replication RPCs on `client/network_client.gd` and broadcast wiring
    on `server/server_main.gd`. The client decides nothing: no damage, hit,
    death, or respawn logic runs outside the server.
    Why: Close the "make monsters visible to and fightable by players" boundary
    left open by Slice 029, so the server-authoritative monster lifecycle
    (Slices 020-022, 029) finally has a visible, fightable client presentation.
    Related work: [Slice 033](slices/033-client-monster-replication-and-rendering.md)
    Validation: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit
    -gselect=test_monster_node -gexit` passed 4/4 tests, 4 asserts, exit 0;
    `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/integration
    -gselect=test_monster_replication -gexit` passed 7/7 tests, 12 asserts,
    exit 0; the full configured GUT suite (`scripts/run_gut_validation.sh`)
    passed 26/26 scripts, 199/199 tests, 793 asserts, exit 0. Separately, a
    headless client run reached `connected: player spawned` and observed 4
    spawned monsters with zero `Cannot convert argument .. int to String`
    monster-position RPC errors against a freshly restarted server on current
    code. Interactive GUI visual/fight confirmation (a human seeing the
    monster render, hitting it three times to kill it, and watching it
    respawn) was obtained on 2026-09-13 (human-confirmed), completing the
    slice's runtime evidence.
  - Date: 2026-09-13
    What changed: IP-023 moved to `Implemented`. The Slice 033 interactive GUI
    visual/fight confirmation was obtained — a human ran the graphical client
    against the live server and saw the dark-red monster render, chase, flash
    on each melee hit, die on the third hit, and respawn — completing the
    "visible to and fightable by players" boundary on top of the green headless
    suite (26/26 scripts, 199/199 tests, 793 asserts, exit 0).
    Why: Final acceptance evidence for the feature was captured, so its status
    reflects delivered reality.
    Related work: [Slice 033](slices/033-client-monster-replication-and-rendering.md)
    Validation: Full gate green (199/199) plus the human GUI confirmation above.

### IP-008: Just-in-time sector generation

- Status: `Implemented`
- Feature: When a player reaches an ungenerated sector boundary, the server requests sector content asynchronously without blocking the live multiplayer loop.
- Problem solved: The game needs expandable world content without a synchronous generation pause.
- How it solves the problem: Slice 009 adds `server/provisional_sector_generator.gd`, Slice 046 connects authoritative sector transitions to that non-blocking request seam, and Slice 047 canonicalizes successful results before reliable replication. World mutation is a separate P-013 capability.
- Phase: 8. JIT world generation and local inference
- Implementation slices: [Slice 009](slices/009-provisional-sector-generation.md), [Slice 046](slices/046-sector-boundary-detection.md), [Slice 047](slices/047-jit-result-canonicalization-replication.md)
- Public seam: `server/provisional_sector_generator.gd` (`request_provisional_sector`, `get_status`, `get_correlation_id`, `get_provisional_result`, `provisional_sector_ready`).
- Validation: Slices 046-047 focused validation passed; the full configured GUT suite passed 282/282 tests across 39/39 scripts and 1073 assertions, exit 0.
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index), [Provisional sector generation](../.scratch/game-vision/issues/16-provisional-sector-generation.md)
- Change history:
  - Date: 2026-09-12
    What changed: Implemented Slice 009 — a request-acceptance and in-memory
    provisional-outcome seam in front of the unchanged Slice 008
    `SectorBlueprintService`. Renamed from `P-008` to `IP-008` because a live,
    validated public seam now exists, even though boundary detection remains
    unbuilt.
    Why: Close the non-blocking request-orchestration half of just-in-time
    sector generation before boundary detection or Canon persistence work.
    Related work: [Slice 009](slices/009-provisional-sector-generation.md)
    Validation: `godot --headless -s addons/gut/gut_cmdln.gd
    -gdir=res://tests/integration -gselect=test_provisional_sector_generation
    -gexit` passed 9/9 tests, 32 assertions, exit 0; the full configured GUT
    suite (`scripts/run_gut_validation.sh`) passed 23/23 tests, 70 assertions,
    exit 0.
  - Date: 2026-09-14
    What changed: Added the finalization boundary that canonicalizes successful
    provisional results and replicates only stored Canon to connected clients.
    Why: Prevent provisional or conflicting LLM output from becoming visible
    world state.
    Related work: [Slice 047](slices/047-jit-result-canonicalization-replication.md), [Slice 045](slices/045-canon-sector-persistence.md)
    Validation: Coordinator test ran after forced import; unit suite passed 188/188 tests, exit 0; server check-only passed, exit 0; full GUT telemetry passed 282/282 tests across 39/39 scripts and 1073 assertions, exit 0.

### IP-015: Authoritative action input

- Status: `In Progress`
- Feature: Client action input, including sword slashing, is validated and resolved by the authoritative server while the client presents responsive feedback.
- Problem solved: Action gameplay must remain responsive without allowing clients to decide combat outcomes.
- How it solves the problem so far: Slice 012 adds the first authoritative action: a bounded melee `ActionIntent`/`ActionResolution`/`CombatEvent` contract (`shared/combat_contracts.gd`), a per-peer fixed-60Hz-tick `WINDUP -> ACTIVE -> RECOVERY -> IDLE` state machine with monotonic sequence validation, idempotent replay, and bounded rejection codes (`server/server_player_state.gd`), authoritative locomotion throttling during WINDUP/RECOVERY, and a deterministic vector reach/arc hit test against a server-owned stationary `TargetDummy` that broadcasts a replicated `CombatEvent.HIT` (`server/server_main.gd`). The client captures attack input, predicts the disposable windup/recovery locomotion slowdown, and reconciles on rejection (`client/player.gd`); a client-side target dummy renders a flash/wobble reaction to the authoritative hit (`client/target_dummy.gd`). Slice 013 adds a purely cosmetic strike-line telegraph (`client/melee_strike_visual.gd`): the attacker's own client shows it during its disposable predicted `ACTIVE` window (hiding immediately on rejection), and a new server-broadcast `melee_swing_started` signal (`server/server_player_state.gd`, relayed by `server/server_main.gd`) lets every other connected peer's `RemotePlayer` mirror an equivalent timed line, all without any client asserting a hit or altering reach/arc truth. Only melee strikes against one stationary dummy exist so far — no damage/HP, other action kinds, moving targets, or PvP — so the feature remains `In Progress` rather than `Implemented`.
- Phase: 10. Authoritative runtime and action input
- Implementation slices: [Slice 012](slices/012-authoritative-melee-strike.md), [Slice 013](slices/013-melee-strike-visual-indicator.md)
- Public seam: `shared/combat_contracts.gd`, `server/server_player_state.gd` (`apply_action_intent`, `set_target_dummies`, `action_resolved`, `combat_event_emitted`, `melee_swing_started`), `server/server_main.gd` (target dummy spawn and RPC relay, `melee_swing_started` relay), `client/network_client.gd` (`submit_action_intent`, `receive_action_resolution`, `receive_combat_event`, `receive_melee_swing_started`), `client/player.gd`, `client/target_dummy.gd`, `client/remote_player.gd`, `client/melee_strike_visual.gd`.
- Validation: See [Slice 012](slices/012-authoritative-melee-strike.md) and [Slice 013](slices/013-melee-strike-visual-indicator.md) for exact commands and results (Slice 012: 21/21 focused unit tests, 4/4 focused integration tests, a real two-process ENet smoke test, and 48/48 full suite, exit 0; Slice 013: 9/9 focused unit tests, 23 assertions, and 57/57 full suite, 161 assertions, exit 0).
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index), [melee-combat map](../.scratch/melee-combat/map.md), [issue 01](../.scratch/melee-combat/issues/01-define-first-melee-exchange.md), [issue 02](../.scratch/melee-combat/issues/02-set-melee-action-authority-and-lifetime.md), [issue 03](../.scratch/melee-combat/issues/03-model-melee-weapon-archetypes.md), [issue 04](../.scratch/melee-combat/issues/04-choose-first-target-and-hit-rule.md), [issue 05](../.scratch/melee-combat/issues/05-set-first-melee-slice-boundary-and-evidence.md)
- Change history:
  - Date: 2026-09-12
    What changed: Implemented Slice 012 — the first authoritative melee-strike action, its shared contracts, server state machine, client prediction/reconciliation, and target dummy. Renamed from `P-015` to `IP-015` because a live, validated public seam now exists, even though only one action kind and one stationary target exist so far.
    Why: Close the melee-combat decision map's (`.scratch/melee-combat/`) first implementation slice before any damage, progression, or additional action kinds.
    Related work: [Slice 012](slices/012-authoritative-melee-strike.md)
    Validation: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gselect=test_melee_combat_contracts -gexit` passed 21/21 tests, 54 assertions, exit 0; `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/integration -gselect=test_authoritative_melee_strike -gexit` passed 4/4 tests, 14 assertions, exit 0; `godot --headless -s scripts/test_authoritative_melee_strike_e2e.gd` (real two-process ENet) printed `ALL PASS`, exit 0; the full configured GUT suite (`scripts/run_gut_validation.sh`) passed 48/48 tests, 138 assertions, exit 0.
  - Date: 2026-09-12
    What changed: Implemented Slice 013 — a purely cosmetic melee strike-line visual indicator for both the attacking client (timed from its existing disposable predicted phase) and every remote observer (timed from a new server-broadcast `melee_swing_started` signal). Added no new authoritative state, `ActionIntent`/`ActionResolution` fields, or hit-test logic.
    Why: Slice 012 proved authoritative hit registration but gave neither the attacker nor observers any visible read on the swing window; this closes that presentation gap without touching combat authority.
    Related work: [Slice 013](slices/013-melee-strike-visual-indicator.md)
    Validation: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gselect=test_melee_strike_visual_indicator -gexit` passed 9/9 tests, 23 assertions, exit 0; the full configured GUT suite (`scripts/run_gut_validation.sh`) passed 57/57 tests, 161 assertions, exit 0.

### IP-001: Server-authoritative networked multiplayer

- Status: `Implemented`
- Feature: Multiple players see and affect each other's Player nodes in the
  same world in real time.
- Problem solved: The first playable slice is single-player/local only, but
  the product goal is a networked multiplayer game.
- How it solves the problem: Adopt Godot 4's High-Level Multiplayer API with
  the server as the authority for Player position and world state; client
  sends input, server simulates and reconciles prediction.
- Phase: 2. Network connection proof (also advances Phase 4, Phase 5, and Phase 11)
- Implementation slices: [Slice 002](slices/002-client-connects-to-server.md),
  [Slice 004](slices/004-authoritative-player-movement.md),
  [Slice 005](slices/005-prediction-reconciliation.md),
  [Slice 007](slices/007-multi-peer-player-replication.md)
- Public seam: `server/server_main.gd` (`_start_server`,
  `_on_peer_connected`), `server/server_player_state.gd`
  (`start_for_peer`, `apply_input_intent`), `client/network_client.gd`
  (`connect_to_server`, `status`, `spawn_local_player_representation`,
  `submit_input_intent`, `receive_authoritative_position`), and (Slice 005)
  `client/player.gd` (`_on_authoritative_position_received`) and
  `client/networked_player_input.gd` (`_on_authoritative_position_received`).
- Validation: See [Slice 002](slices/002-client-connects-to-server.md),
  [Slice 004](slices/004-authoritative-player-movement.md), and
  [Slice 005](slices/005-prediction-reconciliation.md) for the exact headless
  commands and results.
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index),
  [game-vision issue 03](../.scratch/game-vision/issues/03-define-authority-model.md),
  [game-vision issue 07](../.scratch/game-vision/issues/07-connect-client-to-server.md),
  [game-vision issue 09](../.scratch/game-vision/issues/09-authoritative-player-movement.md),
  [game-vision issue 11](../.scratch/game-vision/issues/11-prediction-reconciliation.md)
- Change history:
  - Date: 2026-09-12
    What changed: Implemented Slice 005 — the red local Player now tags each
    locally sent input intent with a monotonically increasing sequence
    number while still moving immediately from local input every tick with
    no wait on the network; the server acknowledges the latest processed
    sequence in its authoritative snapshots; the red Player reconciles by
    discarding acknowledged pending inputs, snapping to the authoritative
    position, and replaying only the still-unacknowledged inputs; and the
    blue NetworkedPlayer now smooths toward each authoritative snapshot at a
    bounded speed instead of snapping to it, only snapping directly for an
    extreme (post-spawn-scale) delta. Server authority over the resulting
    position is unchanged.
    Why: User-directed Phase 5 prediction/reconciliation proof, recorded in
    `.scratch/game-vision/issues/11-prediction-reconciliation.md`.
    Related work: [Slice 005](slices/005-prediction-reconciliation.md),
    [DT-002](TECHNICAL-DEBT-TRACKER.md#dt-002-no-automated-gdscript-test-framework),
    [DT-003](TECHNICAL-DEBT-TRACKER.md#dt-003-no-interactive-gui-confirmation-of-slice-002s-visual-result),
    [DT-004](TECHNICAL-DEBT-TRACKER.md#dt-004-no-physical-two-machine-windowslinux-lan-run-of-slice-003)
    Validation: See Slice 005 validation section.
  - Date: 2026-09-11
    What changed: Implemented Slice 004 — the client's blue `NetworkedPlayer`
    now reports directional WASD input intent to the server every physics
    tick; the server owns a `ServerPlayerState` node per connected Player,
    integrates its position at a fixed speed on its own tick, and RPCs the
    resulting authoritative position back to the owning client, which
    applies it directly with no prediction or interpolation. The existing
    red local Player and its client-side movement are unchanged.
    Why: User-directed Phase 4 authoritative movement proof, recorded in
    `.scratch/game-vision/issues/09-authoritative-player-movement.md`.
    Related work: [Slice 004](slices/004-authoritative-player-movement.md),
    [DT-002](TECHNICAL-DEBT-TRACKER.md#dt-002-no-automated-gdscript-test-framework),
    [DT-003](TECHNICAL-DEBT-TRACKER.md#dt-003-no-interactive-gui-confirmation-of-slice-002s-visual-result),
    [DT-004](TECHNICAL-DEBT-TRACKER.md#dt-004-no-physical-two-machine-windowslinux-lan-run-of-slice-003)
    Validation: See Slice 004 validation section.
  - Date: 2026-09-11
    What changed: Implemented Slice 002 — a headless ENet server entry path,
    a client connection path with visible status, and a visible networked
    Player representation spawned on successful connection. Status moved
    from `Planned` (P-001) to `In Progress` (IP-001) because the connection
    seam is now live and validated, but movement synchronization and
    authority handoff are still unbuilt.
    Why: User-directed Phase 2 network connection proof, recorded in
    `.scratch/game-vision/issues/07-connect-client-to-server.md`.
    Related work: [Slice 002](slices/002-client-connects-to-server.md),
    [DT-002](TECHNICAL-DEBT-TRACKER.md#dt-002-no-automated-gdscript-test-framework),
    [DT-003](TECHNICAL-DEBT-TRACKER.md#dt-003-no-interactive-gui-confirmation-of-slice-002s-visual-result)
    Validation: See Slice 002 validation section.

## Implemented Features

### F-026: Organic districted starting city

- Status: `Implemented`
- Feature: The starting town is a large, organic, districted, walled city (on
  the scale/feel of EverQuest's Qeynos or FF7's Midgar) whose layout is
  ultimately LLM-generated but always validated so the required structures
  (10-house pool, Smithy, Armor Shop, Inn) exist — replacing the small Slice 016
  square hub.
- Problem solved: The Slice 016 hub is far too small and too square to feel like
  a town; the world needs a believably large, non-grid starting city with
  gates, districts, and roads, while still guaranteeing the fixed set of
  buildings every run.
- How it solves the problem: Slice 023 enlarges the hand-authored hub
  fixture into an organic octagon town (a ±16 square with corners clipped along
  `|x| + |y| <= 22`) enclosed by a wall with a southern gate, radial corridor
  avenues, and a central plaza, with the 13 structures re-placed into a northern
  residential district and a southern trade quarter. It renders through the
  existing per-tile geometry pipeline (`MAX_TILE_COUNT` raised to 2048 to fit
  the ~869-tile town), and the monster exclusion + ground plane grow with it so
  monsters stay in the fields outside the bigger walls. Slice 024 then replaced
  the per-tile geometry with a merged scalable pass (one merged `ArrayMesh` per
  ground kind, one merged `Walls` body) so town size is no longer bounded by the
  physics body count (resolving DT-008). Slice 025 added the schema-v3 organic
  vocabulary (gate/plaza/path/grass/water tiles + church/tavern/item_shop/well)
  and enriched the hub to use it, and Slice 026 added the `TownLayoutProvider`
  guarantee — the LLM proposes a town, the server validates it and requires the
  fixed structures, else falls back to the fixture (never an unusable town).
  Slice 031 grew the village to ~3x area (radius 30) and added 10 villager
  homes (`npc_house`) plus the village leader's hall (`village_hall`) for a
  rural-village feel. Slice 052 wired LLM generation on at boot behind a
  default-off `PROJECT0_LLM_TOWN_AT_BOOT` flag — when set, the server awaits
  `TownLayoutProvider.request_town()` before opening its socket and falls back
  to the fixture on any failure; unset boots exactly as before. Slice 053
  replaced the hard-coded monster exclusion constant with
  `ServerMonsterManager.town_exclusion_half_extent()`, a pure derivation from
  the validated blueprint's actual tile bounds (plus a fixed margin), wired at
  boot in `server_main.gd` — so any town size keeps monsters just outside its
  walls automatically. No items remain; the feature is fully `Implemented`.
- Phase: 8. JIT world generation and local inference
- Implementation slices: [Slice 023](slices/023-organic-districted-town.md), [Slice 024](slices/024-scalable-geometry-pass.md), [Slice 025](slices/025-organic-vocabulary.md), [Slice 026](slices/026-llm-town-generation.md), [Slice 031](slices/031-bigger-village-npc-leader-housing.md), [Slice 052](slices/052-f026-llm-town-at-boot.md), [Slice 053](slices/053-f026-monster-exclusion-from-town-bounds.md)
- Public seam: `server/starting_town_hub_fixture.gd`
  (`blueprint()` generating the radius-30 organic octagon via `_in_town`/`_tile_kind`
  with main + secondary streets, 28 `_STRUCTURES` incl. `npc_house`/`village_hall`,
  ±38 `_SPAWN_POINTS`),
  `shared/sector_blueprint_schema.gd` (`MAX_TILE_COUNT` 4096, `MAX_COORDINATE_ABS` 48,
  `npc_house`/`village_hall` in the v3 vocabulary),
  `server/town_layout_provider.gd` (`resolve`, `meets_required_structures`,
  `request_town`, `default_town_prompt`, `llm_at_boot_enabled`,
  `resolve_boot_town`),
  `server/server_monster_manager.gd` (`town_exclusion_half_extent()` derived
  exclusion, `TOWN_EXCLUSION_MARGIN_YARDS` 2.0, `TOWN_EXCLUSION_HALF_EXTENT` 32.0
  fallback/default),
  `client/gameplay.tscn` (100×100 `FlatPlane`),
  `server/server_main.gd` (`_start_server()` boot wiring behind
  `PROJECT0_LLM_TOWN_AT_BOOT`, and deriving/logging the monster exclusion
  half-extent from the validated town blueprint).
- Validation: See [Slice 023](slices/023-organic-districted-town.md) for exact
  commands and results (8/8 fixture + 7/7 manager + 4/4 replication focused
  tests, 140/140 full suite, exit 0), and [Slice 053](slices/053-f026-monster-exclusion-from-town-bounds.md)
  for the final item's validation (16/16 focused, 315/315 full suite, exit 0).
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index),
  [Organic LLM Village map](../.scratch/organic-village/map.md),
  supersedes [F-019](#f-019-starting-town-hub-fixture),
  [DT-008](TECHNICAL-DEBT-TRACKER.md#dt-008-per-tile-staticbody3d-geometry-did-not-scale-to-city-size) (resolved by Slice 024)
- Change history:
  - Date: 2026-09-14
    What changed: Implemented Slice 053 — replaced the hard-coded
    `TOWN_EXCLUSION_HALF_EXTENT = 32.0` constant with
    `ServerMonsterManager.town_exclusion_half_extent(blueprint)`, a pure
    derivation (`max over tiles of max(|x|, |y|)` plus a
    `TOWN_EXCLUSION_MARGIN_YARDS` margin) from the validated town blueprint's
    actual tile bounds, wired at boot in `server_main.gd`. The constant remains
    only as the documented fallback/default. F-026 moved `In Progress` ->
    `Implemented`; no items remain.
    Why: F-026's last remaining item — any town size (not just the current
    fixture) should keep monsters just outside its walls automatically, rather
    than relying on a hand-tuned constant that must be manually updated for
    every future town size.
    Related work: [Slice 053](slices/053-f026-monster-exclusion-from-town-bounds.md)
    Validation: See Slice 053 validation section.
  - Date: 2026-09-12
    What changed: Implemented Slice 023 — enlarged the hub fixture into an
    organic octagon districted town (gate, radial avenues, central plaza,
    residential + trade districts), raised `MAX_TILE_COUNT` to 2048, grew the
    monster exclusion to 18.0 and the ground plane to 60×60, and updated the
    fixture spawn-outside test to the new town outline. Renders through the
    existing per-tile pipeline.
    Why: Deliver an immediately visible, substantially larger, non-square
    starting town (the first Organic Village slice) and the reliable fallback
    base for later LLM generation.
    Related work: [Slice 023](slices/023-organic-districted-town.md)
    Validation: See Slice 023 validation section.
  - Date: 2026-09-12
    What changed: Implemented Slice 024 — the scalable geometry pass. Ground
    tiles now render as one merged `ArrayMesh` per kind (body-free), walls as
    greedy row-merged colliders under one shared `Walls` body, so the town
    renders with a single physics body regardless of tile count.
    Why: Resolve DT-008 and decouple rendered city size from the physics body
    count, unblocking the schema-v3 vocabulary/scale and LLM-generation slices.
    Related work: [Slice 024](slices/024-scalable-geometry-pass.md)
    Validation: See Slice 024 validation section.
  - Date: 2026-09-13
    What changed: Implemented Slice 025 — enriched the hub to the schema-v3
    organic vocabulary: a gated wall, central plaza, path avenues, a grass ring,
    an ornamental pond, and four flavor buildings (church, tavern, item shop,
    well), 17 structures total.
    Why: Make the starting town read like an organic town, the visible payoff of
    the Organic Village effort.
    Related work: [Slice 025](slices/025-organic-vocabulary.md)
    Validation: See Slice 025 validation section.
  - Date: 2026-09-13
    What changed: Implemented Slice 026 — `server/town_layout_provider.gd`, the
    LLM town-layout guarantee: the model proposes a town, the server validates
    it via the schema and requires the fixed structures (10 houses + smithy +
    armor shop + inn), else falls back to the hub fixture so the town is never
    unusable. Pure `resolve`/`meets_required_structures` plus a non-blocking
    `request_town` coroutine over an injected LLM client.
    Why: Deliver the "LLM proposes, server guarantees, fixture fallback" hybrid
    (map Q2) as a tested seam, the last piece before the town can be safely
    LLM-generated.
    Related work: [Slice 026](slices/026-llm-town-generation.md)
    Validation: See Slice 026 validation section.
  - Date: 2026-09-13
    What changed: Implemented Slice 031 — grew the village to radius 30 (~3.5x
    area, secondary streets, bigger plaza/pond), added 10 villager homes
    (`npc_house`) and the village leader's hall (`village_hall`) for 28
    structures, raised `MAX_TILE_COUNT` to 4096 and `MAX_COORDINATE_ABS` to 48,
    grew the monster exclusion to 32 and the ground plane to 100×100, and added
    the two new v3 structure kinds + prefabs.
    Why: User request — a bigger rural village (Qeynos/Elliot feel) with NPC and
    leader housing, not just player houses.
    Related work: [Slice 031](slices/031-bigger-village-npc-leader-housing.md)
    Validation: See Slice 031 validation section.
  - Date: 2026-09-14
    What changed: Implemented Slice 052 — wired `TownLayoutProvider`'s LLM
    generation on at server boot behind a default-off
    `PROJECT0_LLM_TOWN_AT_BOOT` flag (`llm_at_boot_enabled()` /
    `resolve_boot_town()`). When set, `server_main.gd`'s `_start_server()`
    awaits `request_town()` against a `LocalLLMClient` configured from
    environment (Slice 051) before opening its socket; on any failure it falls
    back to the fixture. Unset boots exactly as before.
    Why: Close the last "wire it on" item from the Slice 026 guarantee seam so
    an operator can opt into LLM-generated starting towns without risking an
    unusable boot.
    Related work: [Slice 052](slices/052-f026-llm-town-at-boot.md)
    Validation: See Slice 052 validation section.

### F-030: Accounts and characters persistence repository

- Status: `Implemented`
- Feature: The server durably creates, reads, selects, and soft-deletes
  Accounts and their Characters through one server-only repository on the
  shared SQLite engine — enforcing username uniqueness, global live
  Character-name uniqueness, the 5-Character cap, and ownership, with every
  mutation atomic and fail-closed. Slice 040 boot-wires this repository into
  the running server for the first time (`server_main.gd` now opens the store
  and calls `ensure_schema()` at startup); RPC/client/world-entry consumption
  of Characters specifically remains later player-accounts slices (4-6).
- Problem solved: Phase 14's spec (self-serve registration, up to 5 durable
  Characters per Account, global live name uniqueness) had no data layer;
  the Wave 4 shared SQLite engine ([F-029](#f-029-shared-server-owned-sqlite-persistence-foundation))
  was inert until a consumer created domain tables and a repository seam on
  it, and nothing in the running server opened that store until Slice 040.
- How it solves the problem: Slice 039 adds the pure, versioned
  `shared/character_record.gd` (`CharacterRecord`) and
  `shared/account_handle.gd` (`AccountHandle`) value contracts plus bounded
  rejection enums and `display_name` validation (length 3-20, charset
  `[A-Za-z0-9 _-]`, no leading/trailing/double spaces) — no DB handle or
  secrets. `server/account_character_repository.gd`
  (`class_name AccountCharacterRepository`) wraps a `SqliteStore` and creates
  the `accounts`/`characters` tables (`ensure_schema()`, idempotent
  `CREATE TABLE IF NOT EXISTS`), including a partial unique index on
  `characters.display_name WHERE deleted = 0` and an index on `account_id`.
  Every mutating operation (`create_account`, `create_character`,
  `select_character`, `soft_delete_character`) runs inside one
  `SqliteStore.transaction()` `BEGIN`/`COMMIT`, uses only
  `query_with_bindings` (never string-concatenated SQL), and enforces name
  uniqueness and the 5-cap at both the app layer (pre-check) and the DB layer
  (partial unique index) as defense in depth, surfacing a DB-layer race loss
  as the same bounded `NAME_TAKEN`/`USERNAME_TAKEN` reason rather than a
  crash. The repository stores and returns the PBKDF2 credential bytes it is
  given verbatim; it never computes or compares them — Slice 040's
  `PasswordHasher`/`AuthService` ([F-031](#f-031-account-authentication-and-session-server))
  is the first real caller that computes those bytes.
- Name-reservation reconciliation: ticket 06's explicit partial unique index
  `WHERE deleted = 0` is authoritative over ticket 05's prose ("name stays
  reserved to the Account"). A soft-deleted Character row is retained (for
  history/possible future restore) but its `display_name` is no longer
  reserved — any Account, including a different one, may reuse it once it is
  the only claim on that name among live rows. See
  [Slice 039](slices/039-accounts-characters-repository.md#reconciliation-name-reservation-across-soft-delete)
  for the full rationale.
- Phase: 14. Player accounts and characters
- Implementation slices: [Slice 039](slices/039-accounts-characters-repository.md),
  [Slice 040](slices/040-account-auth-session.md) (boot-wires the repository
  into the running server for the first time)
- Public seam: `server/account_character_repository.gd`
  (`AccountCharacterRepository.ensure_schema`, `create_account`,
  `find_account_by_username`, `create_character`, `list_characters`,
  `select_character`, `soft_delete_character`); `shared/character_record.gd`
  (`CharacterRecord`, rejection enums, `is_valid_display_name`);
  `shared/account_handle.gd` (`AccountHandle`).
- Validation: Focused `tests/unit/test_character_record.gd` 10/10 and
  `tests/integration/test_account_character_repository.gd` 10/10 (against a
  temporary `user://` database per test). Full suite
  `scripts/run_gut_validation.sh` 248/248 across 32 scripts, exit 0
  (`scripts_expected == scripts_ran == 32`, current as of Slice 040).
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index),
  [player-accounts spec](../.scratch/player-accounts/spec.md),
  [player-accounts issue 05](../.scratch/player-accounts/issues/05-character-data-model-and-lifecycle.md),
  [player-accounts issue 06](../.scratch/player-accounts/issues/06-account-character-persistence-design.md),
  [F-029](#f-029-shared-server-owned-sqlite-persistence-foundation) (the
  consumed SQLite engine foundation), [F-031](#f-031-account-authentication-and-session-server)
  (the first runtime consumer).
- Change history:
  - Date: 2026-09-13
    What changed: Opened F-030 via Slice 039 — added the shared
    `CharacterRecord`/`AccountHandle` contracts and the server-only
    `AccountCharacterRepository` with atomic, parameter-bound, fail-closed
    account/character CRUD on top of the Slice 038 `SqliteStore` engine.
    Why: Phase 14's spec needs a durable data layer before auth/RPC/client
    slices can be built on it; this is the next unblocked slice now that the
    Wave 4 shared SQLite foundation (F-029) is delivered.
    Validation: Focused suites 10/10 and 10/10; full GUT suite 233/233 across
    30 scripts, exit 0.
  - Date: 2026-09-13
    What changed: Promoted F-030 to `Implemented` via Slice 040, which
    boot-wires `server_main.gd` to open the accounts `SqliteStore` and call
    `ensure_schema()` at startup — the repository's first runtime consumer.
    Why: the handoff for Slice 040 named this promotion explicitly, since a
    repository that is only ever exercised by tests is not yet a delivered
    runtime capability; Slice 040's boot wiring closes that gap.
    Validation: full GUT suite 248/248 across 32 scripts, exit 0.

### F-029: Shared server-owned SQLite persistence foundation

- Status: `Implemented` (engine seam only; no domain tables — see Known limitations)
- Feature: One server-owned SQLite engine (`server/sqlite_store.gd`, `class_name SqliteStore`) that opens a database in `user://` (never `res://`), enables `PRAGMA journal_mode=WAL`, reads/writes `PRAGMA user_version` and fails closed on an unsupported version, exposes an atomic `BEGIN`/`COMMIT`/`ROLLBACK` transaction helper, and a parameter-bound query API (`query_with_bindings`).
- Problem solved: nothing in this repository durably persists structured records across restarts yet. Both Phase 14 (Player accounts and characters) and Phase 9 (Canon persistence) independently need a durable, atomic, fail-closed, injection-safe store; building two would diverge and duplicate risk. This is Wave 4 of the delivery roadmap — "the linchpin, build once."
- How it solves the problem: Slice 038 vendors the `godot-sqlite` GDExtension (2shady4u, MIT) pinned at release `v4.4` (built against Godot 4.3-stable, an exact engine match) into `addons/godot-sqlite/`, then wraps it in a server-only `RefCounted` seam that never leaves `server/`. Every write path goes through `transaction()` (rollback on any failure, so no partial durable record) and `query_with_bindings()` (never string-concatenated SQL). An existing database's `user_version` is checked on open and rejected outright if it doesn't match the one version this build supports — never guessed/migrated forward.
- Phase: 9 (Canon persistence and world mutation) and 14 (Player accounts and characters) — cross-cutting shared foundation, not owned by either phase's domain schema.
- Implementation slices: [Slice 038](slices/038-shared-sqlite-persistence-foundation.md)
- Public seam: `server/sqlite_store.gd` (`SqliteStore.open`, `close`, `is_open`, `get_user_version`, `transaction`, `query_with_bindings`, `query`); `addons/godot-sqlite/` (vendored, pinned).
- Validation: Headless extension-load proof (ad hoc smoke script, `godot --headless --path . --script ...`) — exit 0, `SMOKE_OK`, no load error. Focused `tests/integration/test_sqlite_store.gd` 6/6 passed, 22 asserts. Full suite `scripts/run_gut_validation.sh` 213/213 across 28 scripts, exit 0 (`scripts_expected == scripts_ran == 28`).
- Related work: [Project Tracker](PROJECT-TRACKER.md#delivery-order-and-parallelization) (Wave 4), [player-accounts spec](../.scratch/player-accounts/spec.md), [player-accounts issue 03](../.scratch/player-accounts/issues/03-research-godot-persistence-sqlite.md), [player-accounts issue 06](../.scratch/player-accounts/issues/06-account-character-persistence-design.md).
- Change history:
  - Date: 2026-09-13
    What changed: Delivered F-029 via Slice 038 — vendored the pinned `godot-sqlite` v4.4 GDExtension and added the `SqliteStore` engine seam (`user://`-only, WAL, fail-closed `user_version`, atomic transactions, parameter-bound queries only). No domain tables (Account/Character/Canon schemas remain later slices).
    Why: Phase 14 (player accounts) and Phase 9 (Canon) both require one shared, server-owned, atomic, fail-closed, injection-safe persistence mechanism per the resolved player-accounts persistence research/design (tickets 03/06); building it once now unblocks both.
    Validation: Headless load proof exit 0 (`SMOKE_OK`); focused suite 6/6; full GUT suite 213/213 across 28 scripts, exit 0.

### F-028: Imperial world-scale measurement contract

- Status: `Implemented`
- Feature: The game has one canonical, versioned world scale — the world is Imperial and one world unit is one yard, in a three-tier world unit → Tile → Sector model where a Sector is a ¼-mile (440-unit) region. A single shared contract (`WorldScale`) converts between world units, feet, and miles.
- Problem solved: Scale lived implicitly and inconsistently — the blueprint Tile was 1 unit, movement was bare "units/second", and the monster constants silently assumed meters — with no canonical source of truth and no scale term in `CONTEXT.md`.
- How it solves the problem: Slice 036 adds `shared/world_scale.gd` (`WorldScale`), a pure versioned value contract (constants `SCALE_VERSION`, `UNIT_LABEL`, `FEET_PER_YARD`, `YARDS_PER_MILE`, `TILE_EDGE_UNITS`, `SECTOR_EDGE_UNITS` plus `units_to_feet`/`units_to_miles`/`miles_to_units`), read identically by client and server with no authority. The decision is recorded in [ADR 0003](adr/0003-imperial-world-scale.md) and the [World Scale map](../.scratch/world-scale/map.md); `CONTEXT.md` gains the World unit, Tile, and Sector-span terms.
- Phase: 8. JIT world generation and local inference (cross-cutting scale contract)
- Implementation slices: [Slice 036](slices/036-world-scale-measurement-contract.md), [Slice 037](slices/037-world-scale-constant-relabel.md)
- Public seam: `shared/world_scale.gd` (`SCALE_VERSION`, `UNIT_LABEL`, `FEET_PER_YARD`, `YARDS_PER_MILE`, `TILE_EDGE_UNITS`, `SECTOR_EDGE_UNITS`, `units_to_feet`, `units_to_miles`, `miles_to_units`).
- Validation: See [Slice 036](slices/036-world-scale-measurement-contract.md) — focused `test_world_scale` 8/8 (15 asserts, exit 0); full suite `scripts/run_gut_validation.sh` 207/207 across 27 scripts, exit 0 (`scripts_expected == scripts_ran == 27`).
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index), [World Scale map](../.scratch/world-scale/map.md), [ADR 0003](adr/0003-imperial-world-scale.md). The meters→yards relabel of existing constants (world-scale ticket 04) was completed in Slice 037.
- Change history:
  - Date: 2026-09-13
    What changed: Delivered F-028 via Slice 036 — added the versioned `WorldScale` measurement contract (1 unit = 1 yard; world unit → Tile → Sector; ¼-mile Sector), recorded [ADR 0003](adr/0003-imperial-world-scale.md), and added the `CONTEXT.md` scale terms. Planning charted via the World Scale wayfinder map (tickets 01–05).
    Why: Scale was implicit and inconsistent (1-unit tiles, bare "units/second", monster constants silently in "meters"); the user asked for a measurement system to define scale, in Imperial units.
    Validation: Focused `test_world_scale` 8/8 exit 0; full GUT suite 207/207 across 27 scripts, exit 0.
  - Date: 2026-09-13
    What changed: Completed F-028's constant adoption via Slice 037 — renamed the world-scale-bearing constants meters→yards (monster `*_YARDS`, combat `reach_yards`, `RESPAWN_AREA_RADIUS_YARDS`) and relabeled the `network_config`/`player` unit comments; magnitudes unchanged.
    Why: Adopt the Imperial vocabulary (1 unit = 1 yard) in the existing code so the "meters" labels no longer contradict ADR 0003.
    Validation: Rename-only; full GUT suite stays green 207/207 across 27 scripts, exit 0.

### F-027: Server-authoritative movement collision

- Status: `Implemented`
- Feature: The server keeps the player out of walls and buildings — authoritative movement resolves against the town's solid cells (wall tiles + building footprints) with wall-sliding, so the village is physically solid to walk around in.
- Problem solved: The server owned player position by pure integration with no collision, so the player walked straight through walls, houses, and the village hall.
- How it solves the problem: Slice 030 adds `shared/sector_collision_map.gd` (`SectorCollisionMap`), built from the validated blueprint into a blocked grid-cell set (every `wall` tile plus each structure's per-kind footprint from `SectorGeometryLookup.structure_footprint`); `resolve_move(from, to)` does axis-separated sliding so the player stops at a solid cell's face and slides along walls. `server/server_player_state.gd`'s movement integration applies `resolve_move` when a map is injected (null = free movement, backward compatible), and `server/server_main.gd` builds the map from the hub at boot and injects it into every peer. Walkable ground (floor/path/plaza/gate/grass/water) stays open; the southern gate is passable.
- Phase: 10. Authoritative runtime and action input
- Implementation slices: [Slice 030](slices/030-server-side-collision.md)
- Public seam: `shared/sector_collision_map.gd` (`is_blocked`, `resolve_move`, `blocked_count`), `shared/sector_geometry_lookup.gd` (`structure_footprint`), `server/server_player_state.gd` (`set_collision_map`), `server/server_main.gd` (`_town_collision`).
- Validation: See [Slice 030](slices/030-server-side-collision.md) — 6/6 collision-map + 4/4 player-state-collision + 10/10 lookup focused tests; full suite `scripts/run_gut_validation.sh` 188/188 across 24 scripts, exit 0. Live client-blocked confirmation is pending a server restart.
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index), extends [IP-001](#ip-001-server-authoritative-networked-multiplayer), makes [F-026](#f-026-organic-districted-starting-city) solid.
- Change history:
  - Date: 2026-09-13
    What changed: Implemented Slice 030 — server-side wall/building collision (`SectorCollisionMap` + per-kind footprints), applied in `ServerPlayerState` movement and injected from server boot, so the village is physically solid with wall-sliding.
    Why: The village rendered but the player walked through everything (no collision authority); a "is it walkable?" review surfaced the gap.
    Validation: See Slice 030 validation section.

### P-004: Agent-assisted delivery orchestration

- Status: `Implemented`
- Feature: Copilot in VS Code produces a bounded implementation handoff that triggers Claude Code CLI for the named multi-file changes and returns validation evidence for review, backed by a durable handoff template and a defined traceable-handoff evidence record.
- Problem solved: Planning, implementation, and review can drift when agent ownership and handoff evidence are implicit.
- How it solves the problem: Slice 027 promotes the handoff brief to a durable template (`docs/templates/claude-code-handoff-template.md`), adds an "Agent-assisted delivery orchestration" section to `DEVELOPMENT-WORKFLOW.md` defining the loop (Copilot brief → Claude Code CLI implements → returns evidence → Copilot reviews) and the five-part traceable-handoff evidence record, and demonstrates one real traceable handoff (Slice 008) whose review caught a missing-evidence gap and tracked it as DT-006 rather than accepting it. Ownership stays authoritative in `AGENTS.md` and `.github/copilot-instructions.md`.
- Phase: 7. Delivery workflow capabilities
- Implementation slices: [Slice 027](slices/027-agent-assisted-delivery-orchestration.md)
- Public seam: `docs/templates/claude-code-handoff-template.md`, the `DEVELOPMENT-WORKFLOW.md` "Agent-assisted delivery orchestration" section, and the slice records with their synchronized `FEATURE-LIST.md`/`PROJECT-TRACKER.md` entries.
- Validation: See [Slice 027](slices/027-agent-assisted-delivery-orchestration.md) — focused documentation check (required template sections present, workflow section present, no unresolved placeholders) PASS exit 0, plus `scripts/run_gut_validation.sh` 168/168 across 22 scripts, exit 0 (no regression).
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index), [game-vision map](../.scratch/game-vision/map.md)
- Change history:
  - Date: 2026-09-13
    What changed: Delivered P-004 via Slice 027 — promoted the Claude Code handoff template into `docs/templates/`, documented the orchestration loop and traceable-handoff evidence record in `DEVELOPMENT-WORKFLOW.md`, and demonstrated one traceable handoff (Slice 008). Moved P-004 `Planned` → `Implemented`.
    Why: Make agent ownership and handoff evidence explicit and traceable so planning, implementation, and review no longer drift.
    Validation: Focused documentation check exit 0; full GUT suite 168/168, exit 0.

### F-025: Project flow visual-management dashboard

- Status: `Implemented`
- Feature: A read-only web dashboard renders the delivery flow live — per-goal
  issue vetting, a Vetting → Planned → Ready → Active → Done lifecycle strip, an
  implementation board whose feature cards are correlated to the `.scratch`
  issues they were promoted from, Andon/stop signals, and phase status.
- Problem solved: Delivery state was spread across `.scratch` maps/issues,
  `FEATURE-LIST.md`, and `PROJECT-TRACKER.md` with no single visual read on what
  is being vetted, what is ready, what is active, and what is done.
- How it solves the problem: `dashboard/app.py` (a dependency-free
  `http.server`) parses `.scratch/<goal>/map.md` + `issues/*.md`,
  `FEATURE-LIST.md`, `PROJECT-TRACKER.md`, and `TECHNICAL-DEBT-TRACKER.md` on
  each request and renders the board; it runs read-only in the
  `project0-flow-visual` container and hot-reloads on source change.
- Phase: 7. Delivery workflow capabilities
- Public seam: `dashboard/app.py` (`goal_maps`, `feature_cards`,
  `feature_stage`, `phase_rows`, `debt_cards`, `render`),
  `dashboard/Dockerfile`, `dashboard/docker-compose.yml`.
- Validation: Served live at `http://127.0.0.1:18083` (HTTP 200); the parsers
  run against the live records each request. No GUT coverage — this is Python
  delivery tooling outside the Godot suite.
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index),
  [project flow dashboard](../.scratch/game-vision/issues/14-project-flow-dashboard.md)
- Change history:
  - Date: 2026-09-12
    What changed: Backfilled this F-025 record for the already-delivered flow
    dashboard (resolved planning ticket game-vision #14, which had no feature
    record), then added the goal-map vetting roadmap, the delivery-lifecycle
    flow strip, and the feature-to-issue-correlated implementation board.
    Why: Close a traceability gap — a delivered `task` issue with no feature —
    and make the delivery flow itself a first-class tracked capability.
    Validation: Dashboard serves HTTP 200 with the live board.

### F-022: Player house allocation

- Status: `Implemented`
- Feature: Each connecting peer is assigned a unique house from the starting
  town's fixed 10-house pool, server-authoritatively, freed immediately on
  disconnect; the owning client sees "Your house: <id>" in its HUD.
- Problem solved: The town has 10 houses but nothing tied a player to one; the
  original vision is that each adventurer gets their own house in town.
- How it solves the problem: Slice 019 adds `server/house_allocator.gd` (a pure,
  unit-testable allocator: first-available, idempotent per peer, fail-closed on
  exhaustion, immediate release with no reconnect reservation) built from the
  Slice 016 hub blueprint's `house` structures. `server/server_main.gd` assigns
  on connect (telemetry-logged) and notifies only the owning client via a new
  `receive_assigned_house` reliable RPC on `client/network_client.gd`, which a
  `HouseLabel` HUD element (`client/assigned_house_label.gd`) presents.
- Phase: 8. JIT world generation and local inference
- Implementation slices: [Slice 019](slices/019-player-house-allocation.md)
- Public seam: `server/house_allocator.gd`
  (`house_ids_from_blueprint`, `assign`, `release`, `assigned_house`,
  `available_count`, `pool_size`), `server/server_main.gd`
  (`get_assigned_house`), `client/network_client.gd`
  (`receive_assigned_house`, `assigned_house_received`).
- Validation: See [Slice 019](slices/019-player-house-allocation.md) for exact
  commands and results (7/7 allocator unit tests, 1/1 HUD test, 117/117 full
  suite, exit 0).
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index),
  [Starting Town map](../.scratch/starting-town/map.md),
  [issue 05](../.scratch/starting-town/issues/05-player-house-allocation.md)
- Change history:
  - Date: 2026-09-12
    What changed: Implemented Slice 019 — server-authoritative unique-house
    allocation from the hub's fixed 10-house pool, freed on disconnect, surfaced
    in the owning client's HUD. Fixed an in-development headless class-cache
    parse error (a bare `HouseAllocator` type annotation) surfaced by the full
    suite before completion.
    Why: Deliver the Starting Town map's final planning ticket (player house
    allocation), realizing "each adventurer gets their own house in town".
    Related work: [Slice 019](slices/019-player-house-allocation.md)
    Validation: See Slice 019 validation section.

### F-021: Facade enter/exit proximity labels

- Status: `Implemented`
- Feature: Walking the local player up to a starting-town building (House,
  Smithy, Armor Shop, Inn) shows a cosmetic "You are at the <building>" label
  that clears when they walk away.
- Problem solved: The rendered town (Slice 017) was inert; there was no
  feedback for approaching a building, and no seam for "where the adventure
  begins" interactions.
- How it solves the problem: Slice 018 adds `client/facade_proximity.gd` (an
  `Area3D` on each structure prefab that filters to the local `Player` body and
  reports to a presenter found via the `facade_presenter` group) and
  `client/facade_presenter.gd` (a `Label` in the gameplay UI). Each of the four
  `client/structures/*.tscn` prefabs gains a `FacadeProximity` area with its
  building name; `client/gameplay.tscn` gains the presenter `FacadeLabel`. It is
  purely client-observed and cosmetic — no server authority, no exclusivity, no
  interior scene.
- Phase: 8. JIT world generation and local inference
- Implementation slices: [Slice 018](slices/018-facade-enter-exit.md)
- Public seam: `client/facade_proximity.gd`
  (`is_local_player`, `building_display_name`),
  `client/facade_presenter.gd` (`show_facade`, `clear_facade`, `line_for`,
  `GROUP_NAME`).
- Validation: See [Slice 018](slices/018-facade-enter-exit.md) for exact
  commands and results (4/4 presenter unit tests, 5/5 proximity integration
  tests incl. a real physics-overlap test, 109/109 full suite, exit 0).
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index),
  [Starting Town map](../.scratch/starting-town/map.md),
  [issue 04](../.scratch/starting-town/issues/04-facade-representation-and-enter-exit.md)
- Change history:
  - Date: 2026-09-12
    What changed: Implemented Slice 018 — cosmetic client-only facade proximity
    labels on the four starting-town building prefabs, plus a UI presenter.
    Fixed an in-development regression (a malformed 11-value `Transform3D` in
    the four structure prefabs) surfaced by the full suite before completion.
    Why: Make the now-visible starting town interactive (the map's facade
    enter/exit planning ticket), toward the "adventures begin in a tavern" goal.
    Related work: [Slice 018](slices/018-facade-enter-exit.md)
    Validation: See Slice 018 validation section.

### F-020: Server-to-client sector blueprint replication

- Status: `Implemented`
- Feature: On connect, the server replicates the validated starting town hub
  blueprint to each client, which re-validates it and renders it into a
  dedicated `SectorGeometry` scene node — producing a visible, end-to-end
  starting town (server hub fixture → wire → client-rendered geometry).
- Problem solved: The server held a validated hub (Slice 016) and the client
  could translate a blueprint into geometry (Slice 015), but nothing connected
  the two; a validated blueprint had no path from server to a client's scene.
- How it solves the problem: Slice 017 adds a reliable authority RPC
  `receive_sector_blueprint(blueprint)` on `client/network_client.gd`, sent by
  `server/server_main.gd._on_peer_connected` (before player-spawn RPCs) with
  the in-memory hub Dictionary. The client re-validates through
  `SectorBlueprintSchema.validate()` at the boundary and, only on success,
  runs the Slice 015 `SectorGeometryTranslator` into a dedicated
  `SectorGeometry` node, leaving `FlatPlane`/`Player`/UI untouched. An invalid
  payload renders nothing. The render logic is a static, parent-injected
  `render_sector_blueprint()` seam for testability; a `sector_blueprint_received`
  signal plus send/receive logs provide replication telemetry.
- Phase: 8. JIT world generation and local inference
- Implementation slices: [Slice 017](slices/017-blueprint-replication.md)
- Public seam: `client/network_client.gd`
  (`receive_sector_blueprint`, `render_sector_blueprint`,
  `sector_blueprint_received`), `server/server_main.gd`
  (`_on_peer_connected` send).
- Validation: See [Slice 017](slices/017-blueprint-replication.md) for exact
  commands and results (4/4 focused tests, 100/100 full suite, exit 0).
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index),
  [Starting Town map](../.scratch/starting-town/map.md),
  [issue 06](../.scratch/starting-town/issues/06-blueprint-replication-contract.md)
- Change history:
  - Date: 2026-09-12
    What changed: Implemented Slice 017 — reliable server→client replication of
    the validated hub blueprint, re-validated and rendered client-side into a
    dedicated `SectorGeometry` node, completing the Starting Town map
    end-to-end.
    Why: Close the map's final resolved planning ticket (blueprint replication
    contract) so the hub is actually visible in a connected client, unblocking
    facade-interaction and house-allocation slices.
    Related work: [Slice 017](slices/017-blueprint-replication.md)
    Validation: See Slice 017 validation section.

### F-019: Starting town hub fixture

- Status: `Implemented`
- Feature: The headless server materializes a hard-coded, schema-v2 starting
  town hub blueprint (reserved `sector_id` `starting_town_hub`, a bounded
  wall/corridor/floor footprint, and 13 structures — a 10-house player pool
  plus Smithy, Armor Shop, and Inn) at boot, validating it through the same
  `SectorBlueprintSchema` the LLM path uses and failing closed if it is
  invalid.
- Problem solved: The starting town must reliably contain the same buildings
  every run; live LLM generation cannot guarantee that, so the hub ships as
  static, server-owned, schema-validated data rather than a generated sector.
- How it solves the problem: Slice 016 adds
  `server/starting_town_hub_fixture.gd` (a `RefCounted` with static
  `blueprint()` and a pure fail-closed `materialize()` seam) and wires it into
  `server/server_main.gd._start_server()`, which validates the fixture before
  opening a socket, holds the validated blueprint in memory (exposed read-only
  via `get_starting_town_hub_blueprint()`), and refuses to start (`quit(1)`,
  logging the outcome/detail) if validation fails. The hub bypasses Ollama and
  `provisional_sector_generator.gd` entirely.
- Phase: 8. JIT world generation and local inference
- Implementation slices: [Slice 016](slices/016-starting-town-hub-fixture.md)
- Public seam: `server/starting_town_hub_fixture.gd`
  (`SECTOR_ID`, `blueprint()`, `materialize()`),
  `server/server_main.gd` (`get_starting_town_hub_blueprint()`).
- Validation: See [Slice 016](slices/016-starting-town-hub-fixture.md) for
  exact commands and results (8/8 focused tests, 96/96 full suite, exit 0).
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index),
  [Starting Town map](../.scratch/starting-town/map.md),
  [issue 03](../.scratch/starting-town/issues/03-hub-sector-identity-and-pinning.md),
  [issue 05](../.scratch/starting-town/issues/05-player-house-allocation.md)
- Change history:
  - Date: 2026-09-12
    What changed: Implemented Slice 016 — a hard-coded, schema-validated
    starting town hub fixture materialized fail-closed at server boot and held
    in memory for future client replication.
    Why: Close the Starting Town map's third resolved planning ticket (hub
    sector identity and pinning) so a reliable, reproducible town exists before
    replication, facade interaction, or per-player house allocation slices.
    Related work: [Slice 016](slices/016-starting-town-hub-fixture.md)
    Validation: See Slice 016 validation section.

### F-018: Client-side sector geometry translation

- Status: `Implemented`
- Feature: A validated sector blueprint Dictionary (schema v1 or v2) is
  translated on the client into 3D scene geometry: procedural per-kind boxes
  for tiles and instanced placeholder prefab scenes for structures.
- Problem solved: A validated blueprint had no path to becoming visible scene
  geometry; CLAUDE.md previously treated geometry translation as fully
  unimplemented.
- How it solves the problem: Slice 015 adds `shared/sector_geometry_lookup.gd`
  (a pure `RefCounted` helper, no scene-tree dependency) mapping tile kind to
  mesh/collision box dimensions and structure kind to a `PackedScene` path,
  and `client/sector_geometry_translator.gd`, which takes an already-validated
  blueprint Dictionary and a parent `Node3D` and instantiates one
  `StaticBody3D`/`MeshInstance3D`/`CollisionShape3D` per tile and one
  `PackedScene.instantiate()` per structure at its `x`/`y`/`facing_degrees`.
  Four placeholder structure scenes
  (`client/structures/{house,smithy,armor_shop,inn}.tscn`) follow the existing
  `TargetDummy`-style placeholder-art convention.
- Phase: 8. JIT world generation and local inference
- Implementation slices: [Slice 015](slices/015-sector-geometry-translation.md), [Slice 024](slices/024-scalable-geometry-pass.md), [Slice 025](slices/025-organic-vocabulary.md)
- Public seam: `shared/sector_geometry_lookup.gd` (`tile_dimensions`,
  `tile_is_solid`), `client/sector_geometry_translator.gd` (`translate`).
- Validation: See [Slice 015](slices/015-sector-geometry-translation.md) for
  exact commands and results.
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index),
  [Starting Town map](../.scratch/starting-town/map.md),
  [issue 02](../.scratch/starting-town/issues/02-geometry-translation-strategy.md)
- Change history:
  - Date: 2026-09-12
    What changed: Implemented Slice 015 — client-side translation of a
    validated sector blueprint into procedural tile geometry and instanced
    placeholder structure prefabs.
    Why: Close the Starting Town map's second resolved planning ticket
    (geometry translation strategy) before hub materialization, facade
    interaction, or player house allocation work.
    Related work: [Slice 015](slices/015-sector-geometry-translation.md)
    Validation: See Slice 015 validation section.
  - Date: 2026-09-12
    What changed: Implemented Slice 024 — replaced the one-`StaticBody3D`-per-tile
    strategy with a merged geometry pass: non-solid ground tiles combine into one
    `ArrayMesh` per kind on a body-free `MeshInstance3D`, and wall tiles
    greedy-merge per row into box colliders under one shared `Walls`
    `StaticBody3D`. Added `SectorGeometryLookup.tile_is_solid`.
    Why: Remediate [DT-008](TECHNICAL-DEBT-TRACKER.md#dt-008-per-tile-staticbody3d-geometry-did-not-scale-to-city-size)
    so rendered town size is decoupled from the physics body count, unblocking
    the F-026 city-scale destination and the later schema-v3/LLM slices.
    Related work: [Slice 024](slices/024-scalable-geometry-pass.md)
    Validation: See Slice 024 validation section.
  - Date: 2026-09-13
    What changed: Added geometry-lookup dimensions for the five organic ground
    kinds and scene paths for the four new structure prefabs
    (church/tavern/item_shop/well) (Slice 025).
    Why: Let the merged geometry pass render the schema-v3 organic vocabulary
    with no new geometry code.
    Related work: [Slice 025](slices/025-organic-vocabulary.md)
    Validation: See Slice 025 validation section.
  - Date: 2026-09-13
    What changed: Added scene paths and placeholder prefabs for the two new
    structure kinds `npc_house` (villager home) and `village_hall` (the rural
    leader's hall) (Slice 031).
    Why: Render the bigger village's NPC and leader housing.
    Related work: [Slice 031](slices/031-bigger-village-npc-leader-housing.md)
    Validation: See Slice 031 validation section.

### F-017: Sector blueprint schema v2 — structures and spawn points

- Status: `Implemented`
- Feature: The sector blueprint validator accepts an optional version-two
  shape (`structures` and `spawn_points` arrays) alongside the existing
  tiles-only version-one contract, so a future town-like hub sector can
  describe building placements and monster spawn markers without weakening
  or replacing plain version-one sectors.
- Problem solved: The Starting Town map needs a validated way to describe
  House/Smithy/Armor Shop/Inn placements and monster spawn markers before any
  geometry translation, hub materialization, or monster work can begin.
- How it solves the problem: Slice 014 changes `schema_version` validation
  from strict equality to a supported-set check (`1` or `2`), and adds two
  new optional top-level arrays validated with the same fail-closed style as
  the existing `tiles` array: `structures` (unique `structure_id`, a `kind`
  bounded by `SUPPORTED_STRUCTURE_KINDS`, bounded `x`/`y`, and
  `facing_degrees` in `[0, 360)`) and `spawn_points` (`spawn_id`, bounded
  `x`/`y`, bounded in count by `MAX_SPAWN_POINT_COUNT = 16`). Absent or empty
  arrays remain valid for both schema versions, so existing non-town v1
  sectors are unaffected. `server/sector_blueprint_service.gd` required no
  change since it already forwards whatever outcome/blueprint the validator
  returns.
- Phase: 8. JIT world generation and local inference
- Implementation slices: [Slice 014](slices/014-sector-blueprint-schema-v2-structures.md), [Slice 025](slices/025-organic-vocabulary.md)
- Public seam: `shared/sector_blueprint_schema.gd` (`SUPPORTED_SCHEMA_VERSIONS`, `SUPPORTED_TILE_KINDS`, `SUPPORTED_STRUCTURE_KINDS`, `ORGANIC_VOCABULARY_MIN_VERSION`).
- Validation: See [Slice 014](slices/014-sector-blueprint-schema-v2-structures.md)
  for exact commands and results (16/16 focused unit tests, 20 assertions;
  77/77 full suite, 188 assertions, exit 0).
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index),
  [Starting Town map](../.scratch/starting-town/map.md),
  [issue 01](../.scratch/starting-town/issues/01-schema-v2-structures-and-spawn-points.md)
- Change history:
  - Date: 2026-09-12
    What changed: Implemented Slice 014 — version-2-capable sector blueprint
    validation with optional `structures` and `spawn_points` arrays,
    preserving version-1 backward compatibility.
    Why: Close the Starting Town map's first resolved planning ticket (schema
    v2 shape) before any geometry translation, hub materialization, or
    monster spawning work.
    Related work: [Slice 014](slices/014-sector-blueprint-schema-v2-structures.md)
    Validation: `godot --headless -s addons/gut/gut_cmdln.gd
    -gdir=res://tests/unit -gselect=test_sector_blueprint_schema_v2 -gexit`
    passed 16/16 tests, 20 assertions, exit 0; the full configured GUT suite
    (`scripts/run_gut_validation.sh`) passed 77/77 tests, 188 assertions,
    exit 0.
  - Date: 2026-09-13
    What changed: Extended the schema to version 3 with the organic tile
    vocabulary (path/plaza/gate/water/grass) and structure vocabulary
    (church/item_shop/tavern/well), version-gated so v1/v2 keep their original
    vocabulary (Slice 025).
    Why: Give the starting town an organic town vocabulary while keeping
    schema_version a meaningful compatibility signal for the future LLM path.
    Related work: [Slice 025](slices/025-organic-vocabulary.md)
    Validation: See Slice 025 validation section.
  - Date: 2026-09-13
    What changed: Raised `MAX_TILE_COUNT` to 4096 and `MAX_COORDINATE_ABS` to 48
    for the ~3x-bigger village, and added `npc_house` and `village_hall` to the
    v3 organic structure vocabulary (Slice 031).
    Why: Fit the larger rural village and its NPC/leader housing within the
    validated blueprint contract.
    Related work: [Slice 031](slices/031-bigger-village-npc-leader-housing.md)
    Validation: See Slice 031 validation section.

### F-007: Living architecture anchor

- Status: `Implemented`
- Feature: Root `CLAUDE.md` records durable architecture boundaries and the
  normative combat, progression, magic, and Canon contract while pointing
  agents to authoritative project records.
- Problem solved: Agents otherwise reconstruct architecture from scattered
  files and may introduce contradictory authority or state rules.
- How it solves the problem: Slice 010 defines binding server/client ownership,
  six-node vessel and derived-state rules, Kinetic/Meridian/Burnout behavior,
  magic equilibrium, versioned contracts, intent validation, Canon boundaries,
  telemetry, implementation placement, and test seams while distinguishing the
  current implementation from future target behavior.
- Phase: 7. Delivery workflow capabilities
- Implementation slices: [Slice 010](slices/010-core-mechanics-architecture.md)
- Public seam: Root `CLAUDE.md`, linked `AGENTS.md`, `CONTEXT.md`, ADR 0002,
  and delivery records.
- Validation: Slice 010's required-term/placeholder and local-link checks passed
  with exit 0. `scripts/run_gut_validation.sh` passed 23/23 tests and 70
  assertions with exit 0; JUnit and JSON summary artifacts were verified.
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index),
  [ADR 0002](adr/0002-authoritative-mechanics-and-progression.md)
- Change history:
  - Date: 2026-09-12
    What changed: Slice 011 made Mind versus Tool an explicit architecture
    boundary, added perceptual-cue and combat execution-profile contracts, and
    clarified `MET` as derived Metabolism distinct from Mental Focus.
    Why: Preserve player-owned observation and reasoning while allowing the
    Player body's stats to modify physical execution and authored feedback.
    Related work: [Slice 011](slices/011-mind-tool-architecture-refinement.md)
    Validation: Focused semantic checks and the 23-test GUT suite passed.
  - Date: 2026-09-12
    What changed: Replaced the thin architecture note with the unified core
    mechanics contract and recorded its authority decision.
    Why: Make the user's biological progression and combat rules a durable
    constraint before implementation decisions fragment across slices.
    Related work: [Slice 010](slices/010-core-mechanics-architecture.md)
    Validation: Focused documentation checks and the 23-test GUT suite passed.

### F-005: Automated validation gate and test telemetry

- Status: `Implemented`
- Feature: Every push and pull request runs the repository's GUT validation suite and preserves machine-readable results.
- Problem solved: Local validation can be forgotten or can pass without leaving durable evidence for regression review.
- How it solves the problem: `.github/workflows/validation.yml` runs the same `scripts/run_gut_validation.sh` delivery command in a pinned Godot 4.3 container, fails the check on a nonzero result, and uploads JUnit XML, logs, and a JSON status summary even when validation fails.
- Phase: 7. Delivery workflow capabilities
- Implementation slices: Current delivery-process slice, recorded in [Project Tracker](PROJECT-TRACKER.md#implementation-slice-index)
- Public seam: `.github/workflows/validation.yml`, `scripts/run_gut_validation.sh`, and `build/validation/validation-summary.json`.
- Validation: Local runner passes 14/14 tests and 38 assertions; forced runner failure exits nonzero and emits `status: failed`. CI configuration is syntactically reviewed and uses the same local command.
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index), [Development Workflow](DEVELOPMENT-WORKFLOW.md)
- Change history:
  - Date: 2026-09-12
    What changed: Added push/pull-request validation with retained JUnit and JSON telemetry artifacts.
    Why: Make executable validation and regression evidence part of delivery rather than an optional local habit.
    Validation evidence: Local success and failure-path runner checks passed; full local suite is 14/14.

### F-003: LAN client connection

- Status: `Implemented`
- Feature: A Windows Godot client can connect to the Linux server over the local network.
- Problem solved: Slice 002 only works when client and server share a machine because the server binds to `127.0.0.1`.
- How it solves the problem: Make the server bind address and client target host configurable while preserving localhost defaults for automated checks. Slice 003 implements the CLI-arg/env-var resolution, validated headlessly and verified in a two-machine LAN run.
- Phase: 3. LAN client connection
- Implementation slices: [Slice 003](slices/003-lan-client-connection.md)
- Public seam: `shared/network_config.gd` (`resolve_server_bind_address`, `resolve_client_target_host`), `server/server_main.gd`, `client/network_client.gd`.
- Validation: Verified headlessly via `tests/unit/test_lan_config.gd` using
  GUT (including real server/probe subprocesses) and in an interactive
  physical two-machine LAN run between Windows and Linux.
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index), [LAN client connection](../.scratch/game-vision/issues/08-lan-client-connection.md)

### F-004: Multi-peer Player replication

- Status: `Implemented`
- Feature: Two connected clients see distinct Player representations and observe each other's server-authoritative movement.
- Problem solved: The network proof through Slice 005 models only one connected Player and does not replicate peer state to other clients.
- How it solves the problem: The server owns one `ServerPlayerState` per connected peer (keyed by peer id) and replicates each peer's authoritative position to every other connected peer; each client renders every other peer as a distinct `RemotePlayer_<peer_id>` node, spawned/despawned by explicit server RPCs. Slice 007 implements this for two concurrent peers.
- Phase: 11. Multi-peer Player replication
- Implementation slices: [Slice 007](slices/007-multi-peer-player-replication.md)
- Public seam: `server/server_main.gd`, `server/server_player_state.gd`, `client/network_client.gd`, and `client/remote_player.gd`.
- Validation: Headlessly validated via `scripts/test_multi_peer_replication.gd` and verified interactively in a physical two-machine LAN run with multiple peers.
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index), [Multi-peer Player replication](../.scratch/game-vision/issues/13-multi-peer-player-replication.md)

### F-002: Portable Windows client package

- Status: `Implemented`
- Feature: A tester receives a portable Windows 64-bit ZIP package containing
  only the exported client runtime, extracts it without the Godot editor or
  Linux source share, and launches it to the identity gate, configuring the
  server address via `--server-host=<LAN IP>` or the
  `PROJECT0_SERVER_HOST` environment variable.
- Problem solved: The project had a working LAN client but no reproducible
  distributed package boundary. Slices 003–005 proved the complete client
  behavior; this slice packages that behavior for distribution and testing.
- How it solves the problem: A Godot Windows Desktop export preset
  (`export_presets.cfg`) with an inclusion-list of client-runtime files
  (client/*.gd/client/*.tscn, shared/network_config.gd, project.godot),
  deliberately excluding server/, scripts/, and local_llm_client.gd. A build
  script (`scripts/export_windows_client.sh`) exports and zips the result.
  A tester guide documents extraction, server configuration, and expected
  outcomes.
- Phase: 6. Windows client package
- Implementation slices: [Slice 006](slices/006-windows-client-package.md)
- Public seam: `export_presets.cfg` (Windows Desktop preset with client-only
  file list), `scripts/export_windows_client.sh` (build/export script),
  `docs/windows-client-tester-guide.md` (tester documentation).
- Validation: See [Slice 006](slices/006-windows-client-package.md)
  for the exact export and LAN-test results.
- Change history:
  - Date: 2026-09-12
    What changed: Implemented Slice 006 — the Windows Desktop export preset
    was created with client-only files, the build script was added, and the
    tester guide was written. The exported client was LAN-tested by the user,
    launched outside the Godot editor, and reached full connected status.
    Why: User-directed Phase 6 packaging, recorded in
    `.scratch/game-vision/issues/12-windows-client-package.md`.
    Related work: [Slice 006](slices/006-windows-client-package.md),
    [DT-005](TECHNICAL-DEBT-TRACKER.md#dt-005-windows-export-artifact-was-unavailable-in-the-original-sandbox)
    Validation: See Slice 006 validation section.

### F-001: Local identity gate, flat plane scene, and player movement

- Status: `Implemented`
- Feature: A player enters a display name at a local identity gate, is placed
  in a scene containing a flat plane under a fixed 3/4 isometric camera, and
  moves a Player node around that plane with WASD keyboard input.
- Problem solved: The project needed a minimal, always-playable vertical slice
  proving the core play loop (identity → scene → movement) before any
  networking, generation, or persistence existed.
- How it solves the problem: Slice 001 adds a local identity gate
  (`client/identity_gate.gd`) that rejects an empty name and, on submit,
  changes to the gameplay scene, plus a client-side `CharacterBody3D` Player
  (`client/player.gd`) constrained to the XZ plane and driven by the four
  directional input actions each physics tick. It is fully local: no network
  calls, no files written, and the display name is held only in memory. See
  [ADR 0001](adr/0001-client-side-authority-for-first-slice.md) for why
  movement is client-side here and what must change before networking.
- Phase: 1. First playable vertical slice
- Implementation slices: [Slice 001](slices/001-identity-gate-flat-plane-movement.md)
- Public seam: `client/identity_gate.gd` (`_on_enter_pressed`),
  `client/player.gd` (`_physics_process`, `get_planar_input`).
- Validation: See [Slice 001](slices/001-identity-gate-flat-plane-movement.md)
  for the exact headless commands and results; the identity-gate and movement
  seams are covered by `tests/unit/test_identity_gate_and_movement.gd`.
- Related work: [Project Tracker](PROJECT-TRACKER.md#phase-work-index),
  [choose first playable slice](../.scratch/game-vision/issues/02-choose-first-playable-slice.md),
  [DT-002](TECHNICAL-DEBT-TRACKER.md#dt-002-no-automated-gdscript-test-framework)
- Change history:
  - Date: 2026-09-11
    What changed: Implemented Slice 001 — the local identity gate, the
    flat-plane gameplay scene under a fixed 3/4 camera, and client-side planar
    Player movement. This F-001 record was backfilled on 2026-09-12 to resolve a
    dangling Project Tracker reference: the feature was delivered in Slice 001
    but never had a feature-list section.
    Why: Establish the minimal always-playable vertical slice the rest of the
    networked product builds on.
    Related work: [Slice 001](slices/001-identity-gate-flat-plane-movement.md),
    [DT-002](TECHNICAL-DEBT-TRACKER.md#dt-002-no-automated-gdscript-test-framework)
    Validation: See Slice 001 validation section.