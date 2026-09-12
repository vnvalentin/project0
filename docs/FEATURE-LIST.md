# Project0 Feature List

Status: active
Last reviewed: 2026-09-12
Owner: valentin.vn@gmail.com

## Rule

This record owns product capabilities. Record each feature as planned (`P-`),
in progress (`IP-`), or implemented (`F-`). A feature becomes implemented only
after focused validation passes. Do not describe planned or unvalidated work as
implemented.

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

### P-004: Agent-assisted delivery orchestration

- Status: `Planned`
- Feature: Copilot in VS Code can produce a bounded implementation handoff that triggers Claude CLI for the named multi-file changes and returns validation evidence for review.
- Problem solved: Planning, implementation, and review can drift when agent ownership and handoff evidence are implicit.
- Phase: 7. Delivery workflow capabilities
- Public seam: Matt Pocock skill workflows, Wayfinder/grilling artifacts, Claude CLI handoff, and slice records.
- Validation: A future workflow slice must demonstrate one traceable handoff without unscoped edits or missing feature synchronization.

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

### P-007: Living architecture anchor

- Status: `Planned`
- Feature: A concise root `CLAUDE.md` records durable architecture boundaries and points agents to the authoritative project records.
- Problem solved: Agents otherwise reconstruct architecture from scattered files and may lose important constraints between sessions.
- Phase: 7. Delivery workflow capabilities
- Public seam: Root `CLAUDE.md` and linked `AGENTS.md`, `CONTEXT.md`, and delivery records.
- Validation: A documentation slice must prove the anchor stays concise, links resolve, and implementation guidance does not diverge from authoritative records.

### P-008: Just-in-time sector generation

- Status: `Planned`
- Feature: When a player reaches an ungenerated sector boundary, the server requests sector content asynchronously without blocking the live multiplayer loop.
- Problem solved: The game needs expandable world content without a synchronous generation pause.
- Phase: 8. JIT world generation and local inference
- Public seam: Server sector request queue, generation state, completion signal, and failure telemetry.
- Validation: A future slice must prove non-blocking request handling, bounded failure behavior, and no sector becomes Canon before validation and persistence.

### P-009: Hardware-accelerated local inference

- Status: `Planned`
- Feature: Server-side Ollama inference uses the local Tesla P100 and a configured Llama model for generation without external cloud inference costs.
- Problem solved: World generation needs an on-premise inference path with predictable ownership and no cloud token dependency.
- Phase: 8. JIT world generation and local inference
- Public seam: `shared/local_llm_client.gd`, Ollama endpoint/model configuration, and request outcome telemetry.
- Validation: A future integration slice must prove configured-model success, timeout/error handling, and that the client never calls Ollama directly.

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
    Validation: `godot --headless -s addons/gut/gut_cmdln.gd
    -gdir=res://tests/integration -gexit` passed 7/7 tests, 24 assertions,
    exit 0; the full configured GUT suite (`scripts/run_gut_validation.sh`)
    passed 14/14 tests, 38 assertions, exit 0.

### P-011: Canonical history archive

- Status: `Planned`
- Feature: The headless server persists validated sector history in a server-owned SQLite database.
- Problem solved: Generated world content must survive process restarts and be shared consistently by multiplayer sessions.
- Phase: 9. Canon persistence and world mutation
- Public seam: SQLite repository, schema migrations, transaction boundary, and persistence telemetry.
- Validation: A future persistence slice must prove restart recovery, transaction failure handling, and server-only database ownership.

### P-012: One-time blueprint canonicalization

- Status: `Planned`
- Feature: The first validated blueprint for a world coordinate is stored once and becomes immutable Canon for that coordinate.
- Problem solved: Regenerating the same coordinate could produce contradictory maps across sessions.
- Phase: 9. Canon persistence and world mutation
- Public seam: Coordinate uniqueness constraint, canonicalization transaction, and duplicate-generation outcome telemetry.
- Validation: A future slice must prove first-write success, duplicate rejection/idempotency, and no partial Canon record after failure.

### P-013: Dynamic world mutation tracking

- Status: `Planned`
- Feature: Generated assets and mutable entities receive stable GUIDs, and direct player-driven changes such as looting or defeating a leader persist across sessions.
- Problem solved: Mutable world state must not reset or duplicate when a sector is revisited.
- Phase: 9. Canon persistence and world mutation
- Public seam: GUID assignment, mutation event/state store, replay/load path, and mutation telemetry.
- Validation: A future slice must prove stable identity, idempotent mutation application, and rejection of unauthorized world-state changes.

### P-014: Containerized fixed-tick authoritative server runtime

- Status: `Planned`
- Feature: The authoritative Godot server runs in an isolated Docker container with a bounded 20–30 Hz simulation tick and server-owned physics/state.
- Problem solved: Multiplayer behavior needs a reproducible Linux runtime boundary and predictable simulation cadence.
- Phase: 10. Authoritative runtime and action input
- Public seam: Server container entrypoint, tick loop, health output, and runtime telemetry.
- Validation: A future slice must prove container startup, tick-rate bounds, clean shutdown, and no client-side authority over server state.

### P-015: Authoritative action input

- Status: `Planned`
- Feature: Client action input, including sword slashing, is validated and resolved by the authoritative server while the client presents responsive feedback.
- Problem solved: Action gameplay must remain responsive without allowing clients to decide combat outcomes.
- Phase: 10. Authoritative runtime and action input
- Public seam: Action intent RPC, server validation/resolution, replicated result, and rejection telemetry.
- Validation: A future slice must cover accepted, rejected, duplicated, and out-of-order action intents.

The remaining scope of server-authoritative networked
multiplayer (movement synchronization, prediction, and world-state
replication) is completed in Slices 002, 004, 005, and 007.

## In Progress Features

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