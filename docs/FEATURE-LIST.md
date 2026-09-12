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

### P-024: Public game access via OPNsense-native WireGuard

- Status: `Ready`
- Feature: Remote players reach the home-hosted authoritative server over a
  split-tunnel WireGuard connection — an in-process userspace netstack
  GDExtension in the Godot client, an invite-code enrollment service, and
  OPNsense-managed peers — without a VPS, OS admin rights, or exposing the LAN.
- Problem solved: The server is only reachable on the LAN today; public play
  needs secure remote access that neither routes through a cloud relay nor
  grants tunnel clients broader reach than the single game host.
- Ready basis: all six `.scratch/wan-wireguard/` issues are `resolved`
  (SDD-GAME-WG-001); no implementation slice has started.
- Phase: 13. Public game access
- Public seam: Future `wgnetstack` GDExtension and its Godot loopback bridge,
  the enrollment service API, `infra/opnsense/` WireGuard/firewall automation,
  and the host firewall lockdown script.
- Validation: Future slices must prove an unprivileged client tunnel on Windows
  and Linux, invite-code enrollment and OPNsense peer registration, split-tunnel
  isolation (WireGuard → game host `/32` only, default-deny to LAN), and peer
  revocation/ban teardown within one keepalive interval.
- Related work: [Public Game Access via WireGuard map](../.scratch/wan-wireguard/map.md),
  [ENet netstack bridging](../.scratch/wan-wireguard/issues/01-enet-transport-netstack-bridging.md),
  [GDExtension netstack prototype](../.scratch/wan-wireguard/issues/02-godot-gdextension-wireguard-netstack.md),
  [OPNsense infra automation](../.scratch/wan-wireguard/issues/03-opnsense-wireguard-infra-automation.md),
  [enrollment invite service](../.scratch/wan-wireguard/issues/04-enrollment-service-invite-system.md),
  [host firewall lockdown](../.scratch/wan-wireguard/issues/05-host-firewall-lockdown-script.md),
  [revocation and ban lifecycle](../.scratch/wan-wireguard/issues/06-revocation-and-ban-lifecycle.md)

## In Progress Features

### IP-023: Basic monster combat

- Status: `In Progress`
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
  town. Making monsters visible to and damageable by players is a later slice,
  so the feature stays `In Progress`.
- Phase: 10. Authoritative runtime and action input
- Implementation slices: [Slice 020](slices/020-monster-hp-damage-death.md), [Slice 021](slices/021-monster-ai-state-machine.md), [Slice 022](slices/022-monster-spawning-and-respawn.md)
- Public seam: `shared/monster_contracts.gd`
  (`MAX_HP`, `DAMAGE_PER_HIT`, `WINDUP_TICKS`, `ATTACK_ACTIVE_TICKS`,
  `RECOVERY_TICKS`, `DETECTION_RADIUS_METERS`, `CHASE_SPEED_METERS_PER_SEC`,
  `MONSTER_REACH_METERS`, `MONSTER_ARC_DEGREES`, `PHASE_*`, `MonsterCombatState`,
  `default_monster`, `monster_attack_archetype`), `shared/combat_contracts.gd`
  (`COMBAT_EVENT_DEATH`), `server/server_monster_state.gd`
  (`advance`, `receive_damage`, `phase_changed`, `attack_resolved`, `died`),
  `server/server_monster_manager.gd` (`advance_all`, `monster_at`,
  `monster_count`, `living_count`, `monster_died`, `monster_respawned`),
  `server/starting_town_hub_fixture.gd` (spawn points outside the town wall).
- Validation: See [Slice 020](slices/020-monster-hp-damage-death.md),
  [Slice 021](slices/021-monster-ai-state-machine.md), and
  [Slice 022](slices/022-monster-spawning-and-respawn.md) for exact commands and
  results (Slice 022: 7/7 manager + 8/8 fixture focused tests, 140/140 full
  suite, exit 0).
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

### IP-008: Just-in-time sector generation

- Status: `In Progress`
- Feature: When a player reaches an ungenerated sector boundary, the server requests sector content asynchronously without blocking the live multiplayer loop.
- Problem solved: The game needs expandable world content without a synchronous generation pause.
- How it solves the problem so far: Slice 009 adds `server/provisional_sector_generator.gd`, a public seam that accepts a sector-generation request keyed by sector id, drives the existing async `SectorBlueprintService`, and exposes in-memory pending/ready state and a completion signal — all without blocking the SceneTree/multiplayer loop. Sector-boundary detection (the trigger for *when* a player reaches an ungenerated sector) is not yet built, so the feature remains `In Progress` rather than `Implemented`.
- Phase: 8. JIT world generation and local inference
- Implementation slices: [Slice 009](slices/009-provisional-sector-generation.md)
- Public seam: `server/provisional_sector_generator.gd` (`request_provisional_sector`, `get_status`, `get_correlation_id`, `get_provisional_result`, `provisional_sector_ready`).
- Validation: See [Slice 009](slices/009-provisional-sector-generation.md) for the exact commands and results (9/9 focused tests, 23/23 full suite, exit 0).
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
- Implementation slices: [Slice 015](slices/015-sector-geometry-translation.md)
- Public seam: `shared/sector_geometry_lookup.gd`,
  `client/sector_geometry_translator.gd`.
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
- Implementation slices: [Slice 014](slices/014-sector-blueprint-schema-v2-structures.md)
- Public seam: `shared/sector_blueprint_schema.gd`.
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