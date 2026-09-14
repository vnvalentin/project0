# Project0 Tracker

## Tracking system

This tracker owns phases, phase exit gates, and the cross-index of delivery
work. It does not duplicate the authoritative detail held by the other records:

- `FEATURE-LIST.md` owns planned, in-progress, and validated product
  capabilities, including their change history and validation evidence.
- `TECHNICAL-DEBT-TRACKER.md` owns all liabilities from discovery through
  remediation, reclassification, or permanent acceptance.
- `PROJECT-TRACKER.md` maps every feature and debt item to its phase and status,
  and maps every implementation slice to one primary phase and its linked work.

Synchronize the three records. When a feature or debt item's scope or status
changes, update its entry and the phase work index here at the same time. When
a slice is added or its completion changes, update the implementation slice
index here. The detailed item records remain authoritative; this file is a
navigable cross-reference.

Mandatory implementation sync: if the public seam or implementation evidence
shows a capability is live, the tracker status, feature list status, and debt
status must be updated in the same delivery change. A stale status is treated as
a project-process defect, not as an accepted implementation state. If a mismatch
is found, fix the root cause immediately and record the reason in the relevant
feature or debt change history.

## Goal

Ship a networked, server-authoritative 3D isometric action-adventure where
canon world areas are JIT-generated via a local LLM, validated, and persisted
to SQLite — built up from a minimal, always-playable vertical slice.

## Process maps

The TPSA material/information flowchart and the three concurrent process maps
are maintained in [PROCESS-MAPS.md](PROCESS-MAPS.md). The maps are part of the
delivery evidence for each slice; they are not optional narrative diagrams.

## Foundation exit gate

- [x] Domain terms and authorities are documented in `CONTEXT.md`.
- [x] Repository boundaries, commands, sensitive data, and rollback rules are
  documented in `AGENTS.md`.
- [x] The Engineering Constitution and development workflow are installed.
- [x] The first public seam and test strategy are identified.
- [x] Required ADRs and initial risks are recorded (see
  [ADR 0001](adr/0001-client-side-authority-for-first-slice.md); no further
  ADRs are required to close the gate).
- [x] `FEATURE-LIST.md` and `TECHNICAL-DEBT-TRACKER.md` are installed with the
  initial phase work indexed here.

## Delivery order and parallelization

This is the recommended finish order across the remaining phases, with the
tracks that may run in parallel and the dependencies that must be sequenced. It
mirrors the "Delivery roadmap" panel on the Flow Dashboard (`dashboard/app.py`).
Waves are sequential; tracks inside a wave run in parallel.

1. **Finish the combat loop and make the village solid — done.** Monster
   damage/death (Slice 029), client rendering (Slice 033, GUI-confirmed), and
   server-side collision (F-027) are delivered. The earlier monster-position
   RPC error was a stale-server method-table artifact, not a code defect
   (Slice 032 re-run reaches `connected: player spawned`).
2. **Lock cross-cutting decisions (parallel, planning only).** The world-scale
   ADR (`.scratch/world-scale/`: 1 unit = 1 yard, Sector ~= 1/4 mile) and the
   player-accounts + shared-persistence design (`.scratch/player-accounts/`)
   can be charted in parallel; both are docs-only.
3. **World-scale migration — done.** The versioned `WorldScale` seam
   (`shared/world_scale.gd`, Slice 036) and the meters→yards relabel of the
   existing constants (Slice 037, magnitudes unchanged) are delivered under
   [F-028](FEATURE-LIST.md#f-028-imperial-world-scale-measurement-contract);
   the full GUT suite stays green (268/268).
4. **Shared SQLite persistence foundation (linchpin, build once) — done.** One
   server-owned SQLite engine (`server/sqlite_store.gd`, Slice 038, F-029)
   consumed by both player-accounts and Phase 9 Canon; it unblocks the
   containerized runtime and the progression store. Engine only — no domain
   tables yet.
5. **Two consumers in parallel.** Player accounts and characters
   (`.scratch/player-accounts/`) alongside Canon persistence (P-011/P-012/P-013)
   and JIT-generation completion (IP-008 boundary detection, F-026 LLM-on-boot,
   P-009 hardware inference). Mostly disjoint files.
6. **Containerized fixed-tick runtime (P-014).** Needs the Phase 9 persistence
   design and a feature-stable server.
7. **Biological progression and kinetic systems (P-016) — last.** Largest and
   most speculative; needs the combat loop, persistence, the locked scale, and
   the accounts vessel seam.

**Runs in parallel throughout (independent files):** public game access via
WireGuard (P-024: `infra/`, `ci/`, the `native/wgnetstack/` GDExtension), and
the workflow fillers (P-005 Remote-SSH, P-006 asset quarantine; DT-006 test
migration is now resolved — Slice 041).

**Must sequence (hard dependencies or shared files):**

- World-scale ADR then migration then any further large generation/bounds work.
- SQLite engine then accounts storage, Canon storage, and progression storage.
- Persistence design then the containerized runtime (P-014).
- Combat loop + persistence + locked scale + accounts vessel seam then
  biological progression (P-016).
- Shared hot-spot files (`server/server_player_state.gd`,
  `server/server_main.gd` connect lifecycle, `shared/sector_blueprint_schema.gd`
  constants, `shared/monster_contracts.gd`): edit one track at a time even when
  the tracks are otherwise parallel.

## Phases

| Phase | Status | Exit gate |
| --- | --- | --- |
| 0. Foundation and contracts | done | Foundation records completed, cross-linked, and validated; gate marker removed. |
| 1. First playable vertical slice | in-progress | A player can pass a local identity gate, enter a scene with a flat plane, and move a Player around it, validated by headless Godot checks. |
| 2. Network connection proof | done | A headless Godot server accepts one ENet client and the client visibly represents the connected Player on the existing flat plane, with no movement synchronization or persistence required yet. |
| 3. LAN client connection | done | A Windows Godot client can target the Linux server's configured LAN address while localhost remains the default for automated checks; no gameplay synchronization or internet exposure is included. |
| 4. Authoritative movement proof | done | One connected client sends WASD intent, the server owns and updates that Player position, and the client displays the returned authoritative position without prediction or interpolation. |
| 5. Prediction and reconciliation proof | done | The client responds immediately to local input, acknowledges ordered server snapshots, reconciles prediction drift, and smoothly renders authoritative movement without remote-player replication or persistence. |
| 6. Windows client package | done | A reproducible portable Windows 64-bit package launches the current client without the Godot editor, source share, or server-only files and can be configured to connect to the Linux server. |
| 11. Multi-peer Player replication | done | Two clients connect to one server, see distinct Players, observe each other's authoritative movement, and clean up a disconnected Player. |
| 7. Delivery workflow capabilities | in-progress | Agent handoffs, Remote-SSH operation, asset quarantine, and the architecture anchor are documented, exercised, and synchronized with feature records. |
| 8. JIT world generation and local inference | in-progress | The server requests non-blocking sector generation, validates local Ollama JSON blueprints, and exposes bounded failures without interrupting the multiplayer loop. |
| 9. Canon persistence and world mutation | in-progress | Validated sectors and authorized player mutations are durable, uniquely identified, and recovered consistently from SQLite. |
| 10. Authoritative runtime and action input | in-progress | The server runs in an isolated fixed-tick runtime and resolves validated action intents, including combat, authoritatively. |
| 12. Biological progression and kinetic systems | queued | Server-validated play redistributes the six-node vessel, derives kinetic and friction effects, unlocks Meridians, applies Burnout, and enforces magic equilibrium without gating player reasoning. |
| 13. Public game access | in-progress | Remote players reach the home-hosted authoritative server over a split-tunnel WireGuard tunnel with invite-code enrollment and OPNsense-managed peers, without a VPS, client OS admin rights, or LAN exposure. |
| 14. Player accounts and characters | in-progress | A person registers or logs in over the WireGuard tunnel, manages up to five durable Characters across restarts, and enters the world as the selected Character — all server-authoritative and fail-closed. |

### Phase work index

Every feature and technical-debt item maps to the phase it helps complete, with
one status badge: `done`, `in-progress`, `ready`, `queued`, `blocked`, or
`deferred`. These badges mirror the delivery lifecycle defined in
[DEVELOPMENT-WORKFLOW.md](DEVELOPMENT-WORKFLOW.md#delivery-lifecycle)
(Vetting → `ready` → `in-progress` (Active) → `done`). The progress calculation
is `done items / all items in the phase`, rounded to the nearest whole percent.
An item can appear in more than one phase when it advances multiple exit gates.

**Phase 0 — Foundation and contracts**

Progress: **100%** (1 of 1 items done)

- Features: none — this phase produces records, not product features.
- Tech debt: `done` [DT-001](TECHNICAL-DEBT-TRACKER.md#dt-001-foundation-records-left-as-unpopulated-templates) — foundation records were unpopulated templates; now completed and validated.

**Phase 1 — First playable vertical slice**

Progress: **100%** (3 of 3 items done)

- Features: `done` [F-001](FEATURE-LIST.md#f-001-local-identity-gate-flat-plane-scene-and-player-movement) — local identity gate, flat-plane scene, and player movement.
- Tech debt: `done` [DT-002](TECHNICAL-DEBT-TRACKER.md#dt-002-no-automated-gdscript-test-framework) — GUT framework installed and Slice 001's smoke test migrated; `done` [DT-006](TECHNICAL-DEBT-TRACKER.md#dt-006-remaining-hand-rolled-smoke-tests-not-yet-migrated-to-gut) — remaining hand-rolled scripts migrated/wrapped/reclassified (Slice 041).

**Phase 2 — Network connection proof**

Progress: **100%** (1 of 1 items done)

- Features: `done` [IP-001](FEATURE-LIST.md#ip-001-server-authoritative-networked-multiplayer) — the connection proof (headless server, one ENet client, visible networked Player) is live and validated; the feature stays `In Progress` overall because movement sync and authority handoff are still unbuilt.
- Tech debt: `open` [DT-003](TECHNICAL-DEBT-TRACKER.md#dt-003-no-interactive-gui-confirmation-of-slice-002s-visual-result) — no interactive GUI confirmation of the visual result yet, headless-only validation.

**Phase 3 — LAN client connection**

Progress: **100%** (1 of 1 items done)

- Features: `done` [F-003](FEATURE-LIST.md#f-003-lan-client-connection) — the CLI-arg/env-var resolver mechanism, localhost-default safety behavior, and two-machine LAN run verified by user.
- Tech debt: `done` [DT-004](TECHNICAL-DEBT-TRACKER.md#dt-004-no-physical-two-machine-windowslinux-lan-run-of-slice-003) — two-machine LAN run verified by user.

**Phase 4 — Authoritative movement proof**

Progress: **100%** (1 of 1 items done)

- Features: `done` [IP-001](FEATURE-LIST.md#ip-001-server-authoritative-networked-multiplayer) — Slice 004 adds server-authoritative movement for one connected Player, validated headlessly and verified by user in interactive GUI and physical LAN runs.
- Tech debt: `done` [DT-003](TECHNICAL-DEBT-TRACKER.md#dt-003-no-interactive-gui-confirmation-of-slice-002s-visual-result) — interactive GUI confirmation verified by user.

**Phase 5 — Prediction and reconciliation proof**

Progress: **100%** (1 of 1 items done)

- Features: `done` [IP-001](FEATURE-LIST.md#ip-001-server-authoritative-networked-multiplayer) — Slice 005 adds local prediction, server acknowledgement, reconciliation, and bounded smoothing, validated headlessly and verified by user in interactive GUI and physical LAN runs.
- Tech debt: `done` [DT-003](TECHNICAL-DEBT-TRACKER.md#dt-003-no-interactive-gui-confirmation-of-slice-002s-visual-result) — interactive GUI confirmation verified by user.

**Phase 6 — Windows client package**

Progress: **100%** (1 of 1 items done)

- Features: `done` [F-002](FEATURE-LIST.md#f-002-portable-windows-client-package) — the client was exported, launched outside the editor/source share, and connected over LAN.
- Tech debt: none; DT-005 is resolved by the real Windows export and launch evidence.

**Phase 11 — Multi-peer Player replication**

Progress: **100%** (1 of 1 items done)

- Features: `done` [F-004](FEATURE-LIST.md#f-004-multi-peer-player-replication) — two-client authoritative Player replication; Slice 007 implements and validates two-peer replication and disconnect cleanup, verified by user in interactive GUI and physical LAN runs.
- Tech debt: `done` [DT-003](TECHNICAL-DEBT-TRACKER.md#dt-003-no-interactive-gui-confirmation-of-slice-002s-visual-result), [DT-004](TECHNICAL-DEBT-TRACKER.md#dt-004-no-physical-two-machine-windowslinux-lan-run-of-slice-003) — interactive GUI and physical LAN runs verified by user.

**Phase 7 — Delivery workflow capabilities**

Progress: **71%** (5 of 7 items done)

- Features: `done` [F-005](FEATURE-LIST.md#f-005-automated-validation-gate-and-test-telemetry), [F-007](FEATURE-LIST.md#f-007-living-architecture-anchor), [F-025](FEATURE-LIST.md#f-025-project-flow-visual-management-dashboard), [P-004](FEATURE-LIST.md#p-004-agent-assisted-delivery-orchestration); `queued` [P-005](FEATURE-LIST.md#p-005-remote-ssh-server-workspace), [P-006](FEATURE-LIST.md#p-006-token-efficient-asset-quarantine).
- Tech debt: `done` [DT-007](TECHNICAL-DEBT-TRACKER.md#dt-007-lan-config-tests-spawned-a-real-server-on-the-fixed-default-port-9999-non-hermetic) — resolved with a validated `--server-port` override, ephemeral-port tests, and a reimport-first validation gate.

- **Current slice:** [027 — Agent-assisted delivery orchestration](slices/027-agent-assisted-delivery-orchestration.md) — **100% complete; documentation checks and full-suite validation passed**
  - **Feature:** [P-004](FEATURE-LIST.md#p-004-agent-assisted-delivery-orchestration)

**Phase 8 — JIT world generation and local inference**

Progress: **100%** (11 of 11 items done)

- Features: `done` [IP-008](FEATURE-LIST.md#ip-008-just-in-time-sector-generation), `done` [P-009](FEATURE-LIST.md#p-009-hardware-accelerated-local-inference), `done` [F-017](FEATURE-LIST.md#f-017-sector-blueprint-schema-v2-structures-and-spawn-points), `done` [IP-004](FEATURE-LIST.md#ip-004-structured-sector-blueprint-translation), `done` [F-018](FEATURE-LIST.md#f-018-client-side-sector-geometry-translation), `done` [F-019](FEATURE-LIST.md#f-019-starting-town-hub-fixture), `done` [F-020](FEATURE-LIST.md#f-020-server-to-client-sector-blueprint-replication), `done` [F-021](FEATURE-LIST.md#f-021-facade-enter-exit-proximity-labels), `done` [F-022](FEATURE-LIST.md#f-022-player-house-allocation), `done` [F-026](FEATURE-LIST.md#f-026-organic-districted-starting-city) (Organic Village; supersedes F-019), `done` [F-028](FEATURE-LIST.md#f-028-imperial-world-scale-measurement-contract) (cross-cutting scale contract).
- Tech debt: `done` [DT-008](TECHNICAL-DEBT-TRACKER.md#dt-008-per-tile-staticbody3d-geometry-did-not-scale-to-city-size) — resolved by the Slice 024 geometry pass (merged `ArrayMesh` ground + one merged `Walls` body), decoupling town size from the physics body count.

- **Current slice:** [053 — F-026 derive monster exclusion from town bounds](slices/053-f026-monster-exclusion-from-town-bounds.md) — **100% complete; focused, parse, full-suite, record-sync, and runtime boot validation passed**
  - **Feature:** [F-026](FEATURE-LIST.md#f-026-organic-districted-starting-city) (final item delivered; feature now `Implemented`)

**Phase 9 — Canon persistence and world mutation**

Progress: **75%** (3 of 4 items done)

- Features: `done` [F-029](FEATURE-LIST.md#f-029-shared-server-owned-sqlite-persistence-foundation) (cross-cutting persistence-engine foundation, shared with Phase 14), `done` [P-011](FEATURE-LIST.md#p-011-canonical-history-archive), [P-012](FEATURE-LIST.md#p-012-one-time-blueprint-canonicalization), `in-progress` [P-013](FEATURE-LIST.md#p-013-dynamic-world-mutation-tracking).
- Tech debt: none yet.

- **Current slice:** [050 — Canon mutation persistence (dynamic world mutation tracking)](slices/050-canon-mutation-persistence.md) — **delivered; append-only mutation log with optimistic per-sector revision, focused + full-suite + record-sync validation passed**
  - **Feature:** [P-013](FEATURE-LIST.md#p-013-dynamic-world-mutation-tracking) (first slice)

**Phase 10 — Authoritative runtime and action input**

Progress: **50%** (2 of 4 items done)

- Features: `queued` [P-014](FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime), `in-progress` [IP-015](FEATURE-LIST.md#ip-015-authoritative-action-input), `done` [IP-023](FEATURE-LIST.md#ip-023-basic-monster-combat), `done` [F-027](FEATURE-LIST.md#f-027-server-authoritative-movement-collision), [P-016](FEATURE-LIST.md#p-016-biological-progression-and-kinetic-combat-systems) (cross-cutting contract).
- Tech debt: none yet.

- **Current slice:** [033 — Client monster replication and rendering](slices/033-client-monster-replication-and-rendering.md) — **100% complete; focused and full-suite validation passed; interactive GUI confirmation obtained (2026-09-13)**
  - **Feature:** [IP-023](FEATURE-LIST.md#ip-023-basic-monster-combat)

**Phase 12 — Biological progression and kinetic systems**

Progress: **0%** (0 of 1 items done)

- Features: `queued` [P-016](FEATURE-LIST.md#p-016-biological-progression-and-kinetic-combat-systems).
- Tech debt: none yet.

**Phase 13 — Public game access**

Progress: **0%** (0 of 3 items done)

- Features: `in-progress` [P-024](FEATURE-LIST.md#p-024-public-game-access-via-opnsense-native-wireguard) — the OPNsense tunnel, Windows DLL packaging, remote-Windows WAN runtime, enrollment service, and live `/healthz`/`/redeem` path are delivered and validated. Slice 054 remains active only for Windows secure-launcher live enrollment/tunnel evidence, real tunnel-teardown timing, and idempotent re-enrollment.
- Tech debt: none yet.
- **Current slice:** [054 — Secure Windows tunnel enrollment and credential storage](slices/054-secure-windows-tunnel-enrollment.md) — **in progress; secure launcher implemented and full-suite tested; enrollment service deployed live and validated; Windows-launcher live tunnel validation pending**

**Phase 14 — Player accounts and characters**

Progress: **83%** (5 of 6 items done)

- Design complete: the player-accounts map and its six tickets are resolved and the handoff-ready spec is [spec.md](../.scratch/player-accounts/spec.md); `CONTEXT.md` now carries Account and Character as canonical terms. Progress above reflects: the shared engine foundation, Account/Character repository, auth/session, Character CRUD, and server-side Character world-entry binding are implemented and validated; only the client login/character screens (Slice 044) remain open for Windows GUI evidence. The mandatory-auth hard-flip and multi-peer Character replication remain queued follow-ups.
- Features: `done` [F-029](FEATURE-LIST.md#f-029-shared-server-owned-sqlite-persistence-foundation), `done` [F-030](FEATURE-LIST.md#f-030-accounts-and-characters-persistence-repository), `done` [F-031](FEATURE-LIST.md#f-031-account-authentication-and-session-server), `done` [F-032](FEATURE-LIST.md#f-032-character-crud-over-the-wire-server), `done` [F-033](FEATURE-LIST.md#f-033-character-world-entry-server-binding), `in-progress` [F-034](FEATURE-LIST.md#f-034-client-login-and-character-selection-screens) (client UI screens; Windows GUI verification pending).
- Tech debt: none yet.

- **Current slice:** [044 — Client login and character selection UI](slices/044-client-login-character-ui.md) — **server validation complete at 315/315 tests across 44/44 scripts; Windows GUI verification pending**
  - **Features:** [F-033](FEATURE-LIST.md#f-033-character-world-entry-server-binding), [F-034](FEATURE-LIST.md#f-034-client-login-and-character-selection-screens)

### Implementation slice index

A phase is the product-level desired outcome and exit gate. A slice is the
smallest observable, reversible increment that tests a stated hypothesis and
delivers a bounded capability toward a phase. Each slice has one primary phase
for delivery ownership, even when its linked work advances another phase.

Slice completion is based on its own SDD, BDD, TDD, ADR/no-ADR rationale,
validation, and review evidence. Phase completion is based on progress toward
the phase exit gate; it is not a count of completed slices.

#### Phase 1 — First playable vertical slice

- **Slice:** [001 — Identity gate, flat plane, and player movement](slices/001-identity-gate-flat-plane-movement.md) — **100% complete**
  - **Features:** [F-001](FEATURE-LIST.md#f-001-local-identity-gate-flat-plane-scene-and-player-movement)
  - **Tech debt:** [DT-002](TECHNICAL-DEBT-TRACKER.md#dt-002-no-automated-gdscript-test-framework) is done; [DT-006](TECHNICAL-DEBT-TRACKER.md#dt-006-remaining-hand-rolled-smoke-tests-not-yet-migrated-to-gut) (residual migration) is now also done (Slice 041)

- **Slice:** [041 — DT-006 remaining-smoke-test GUT migration](slices/041-dt-006-remaining-smoke-test-gut-migration.md) — **100% complete; test-tooling/records only; focused and full-suite validation passed**
  - **Features:** none new
  - **Tech debt:** [DT-006](TECHNICAL-DEBT-TRACKER.md#dt-006-remaining-hand-rolled-smoke-tests-not-yet-migrated-to-gut) — resolved. Deleted the duplicate `scripts/test_sector_blueprint_contract.gd`, reclassified `scripts/test_ollama.gd` to `scripts/probe_ollama.gd`, and wrapped the three remaining real-process E2E harnesses in GUT (`tests/integration/test_prediction_reconciliation_e2e.gd`, `tests/integration/test_multi_peer_replication_e2e.gd`, `tests/integration/test_authoritative_melee_strike_socket_e2e.gd`). Wrapping the melee harness surfaced and fixed a latent Slice 030 town-collision regression via a new default-off `PROJECT0_E2E_DISABLE_TOWN_COLLISION` server env-var isolation seam.
  - **Planning ticket:** none (technical-debt closure)

#### Phase 2 — Network connection proof

- **Slice:** [002 — Client connects to headless server and shows connected Player](slices/002-client-connects-to-server.md) — **100% complete**
  - **Feature:** [IP-001](FEATURE-LIST.md#ip-001-server-authoritative-networked-multiplayer)
  - **Tech debt:** [DT-006](TECHNICAL-DEBT-TRACKER.md#dt-006-remaining-hand-rolled-smoke-tests-not-yet-migrated-to-gut) (done, Slice 041), [DT-003](TECHNICAL-DEBT-TRACKER.md#dt-003-no-interactive-gui-confirmation-of-slice-002s-visual-result)
  - **Planning ticket:** [Connect client to server](../.scratch/game-vision/issues/07-connect-client-to-server.md)

#### Phase 3 — LAN client connection

- **Slice:** [003 — Windows client connects to configurable Linux server](slices/003-lan-client-connection.md) — **100% complete; physical two-machine LAN run verified by user**
  - **Feature:** [F-003](FEATURE-LIST.md#f-003-lan-client-connection)
  - **Tech debt:** [DT-004](TECHNICAL-DEBT-TRACKER.md#dt-004-no-physical-two-machine-windowslinux-lan-run-of-slice-003)

#### Phase 4 — Authoritative movement proof

- **Slice:** [004 — Server-authoritative movement for one connected Player](slices/004-authoritative-player-movement.md) — **100% complete; interactive GUI confirmation and physical two-machine LAN run verified by user**
  - **Feature:** [IP-001](FEATURE-LIST.md#ip-001-server-authoritative-networked-multiplayer)
  - **Tech debt:** [DT-006](TECHNICAL-DEBT-TRACKER.md#dt-006-remaining-hand-rolled-smoke-tests-not-yet-migrated-to-gut) (done, Slice 041), [DT-003](TECHNICAL-DEBT-TRACKER.md#dt-003-no-interactive-gui-confirmation-of-slice-002s-visual-result), [DT-004](TECHNICAL-DEBT-TRACKER.md#dt-004-no-physical-two-machine-windowslinux-lan-run-of-slice-003)
  - **Planning ticket:** [Authoritative Player movement](../.scratch/game-vision/issues/09-authoritative-player-movement.md)
  - **Planning ticket:** [LAN client connection](../.scratch/game-vision/issues/08-lan-client-connection.md)

#### Phase 5 — Prediction and reconciliation proof

- **Slice:** [005 — Predicted local movement with authoritative reconciliation](slices/005-prediction-reconciliation.md) — **100% complete; interactive GUI confirmation and physical two-machine LAN run verified by user**
  - **Feature:** [IP-001](FEATURE-LIST.md#ip-001-server-authoritative-networked-multiplayer)
  - **Tech debt:** [DT-006](TECHNICAL-DEBT-TRACKER.md#dt-006-remaining-hand-rolled-smoke-tests-not-yet-migrated-to-gut) (done, Slice 041), [DT-003](TECHNICAL-DEBT-TRACKER.md#dt-003-no-interactive-gui-confirmation-of-slice-002s-visual-result), [DT-004](TECHNICAL-DEBT-TRACKER.md#dt-004-no-physical-two-machine-windowslinux-lan-run-of-slice-003)
  - **Planning ticket:** [Prediction and reconciliation](../.scratch/game-vision/issues/11-prediction-reconciliation.md)

#### Phase 6 — Windows client package

- **Slice:** [006 — Portable Windows client package](slices/006-windows-client-package.md) — **100% complete; exported and LAN-tested by user**
  - **Feature:** [F-002](FEATURE-LIST.md#f-002-portable-windows-client-package)

#### Phase 11 — Multi-peer Player replication

- **Slice:** [007 — Two-client Player replication and disconnect cleanup](slices/007-multi-peer-player-replication.md) — **100% complete; interactive GUI confirmation and physical two-machine LAN run verified by user**
  - **Feature:** [F-004](FEATURE-LIST.md#f-004-multi-peer-player-replication)
  - **Tech debt:** [DT-006](TECHNICAL-DEBT-TRACKER.md#dt-006-remaining-hand-rolled-smoke-tests-not-yet-migrated-to-gut) (done, Slice 041), [DT-003](TECHNICAL-DEBT-TRACKER.md#dt-003-no-interactive-gui-confirmation-of-slice-002s-visual-result), [DT-004](TECHNICAL-DEBT-TRACKER.md#dt-004-no-physical-two-machine-windowslinux-lan-run-of-slice-003)
  - **Planning ticket:** [Multi-peer Player replication](../.scratch/game-vision/issues/13-multi-peer-player-replication.md)
  - **Planning ticket:** [Windows client package](../.scratch/game-vision/issues/12-windows-client-package.md)

#### Phase 8 — JIT world generation and local inference

- **Slice:** [046 — Authoritative sector-boundary detection for JIT generation](slices/046-sector-boundary-detection.md) — **100% complete; focused, runtime parse, and full GUT validation passed**
  - **Feature:** [IP-008](FEATURE-LIST.md#ip-008-just-in-time-sector-generation)
  - **Planning ticket:** [Provisional sector generation](../.scratch/game-vision/issues/16-provisional-sector-generation.md)
  - **Public seam:** `server/sector_boundary_detector.gd`; consumes authoritative position updates and Canon lookup, emits bounded generation requests
  - **Validation:** unit GUT passed 184/184 tests across 22 scripts, exit 0; `server/server_main.gd` check-only passed, exit 0; full GUT passed 278/278 tests across 38/38 scripts and 1063 assertions, exit 0
- **Slice:** [047 — JIT result canonicalization and sector replication](slices/047-jit-result-canonicalization-replication.md) — **100% complete; focused, runtime parse, full GUT, and record-sync validation passed**
  - **Features:** [IP-008](FEATURE-LIST.md#ip-008-just-in-time-sector-generation), [P-011](FEATURE-LIST.md#p-011-canonical-history-archive), [P-012](FEATURE-LIST.md#p-012-one-time-blueprint-canonicalization)
  - **Public seam:** `server/canon_generation_coordinator.gd` plus the server's reliable blueprint broadcast
  - **Validation:** coordinator test ran after forced import; unit suite passed 188/188 tests, exit 0; server check-only passed, exit 0; full GUT telemetry passed 282/282 tests across 39/39 scripts and 1073 assertions, exit 0

- **Slice:** [051 — Hardware-accelerated local inference](slices/051-p009-hardware-accelerated-local-inference.md) — **100% complete; focused, full GUT, and record-sync validation passed; live P100 probe confirmed**
  - **Feature:** [P-009](FEATURE-LIST.md#p-009-hardware-accelerated-local-inference)
  - **Public seam:** `shared/local_llm_client.gd` (`resolve_config()`, `configure_from_env()`, `request_outcome_reported` signal, bounded `outcome`/`duration_ms` result fields)
  - **Validation:** focused unit passed 5/5 tests (16 assertions), exit 0; focused integration passed 6/6 tests across 2 scripts (52 assertions), exit 0; full GUT passed 304/304 tests across 43/43 scripts and 1182 assertions, exit 0; record sync passed with 0 errors; live `scripts/probe_ollama.gd` run against `llama3:latest` on the Tesla P100 returned a successful parsed JSON response (2026-09-14)

- **Slice:** [052 — F-026 LLM town generation ON at server boot](slices/052-f026-llm-town-at-boot.md) — **100% complete; focused, server parse, full GUT, record-sync, and runtime boot validation passed**
  - **Feature:** [F-026](FEATURE-LIST.md#f-026-organic-districted-starting-city)
  - **Public seam:** `server/town_layout_provider.gd` (`llm_at_boot_enabled()`, `resolve_boot_town()`), `server/server_main.gd` (`_start_server()` boot wiring behind `PROJECT0_LLM_TOWN_AT_BOOT`)
  - **Validation:** focused unit passed 6/6 tests (15 assertions), exit 0; `server/server_main.gd` check-only exit 0; full GUT passed 310/310 tests across 44/44 scripts and 1197 assertions, exit 0; record sync exit 0; runtime boot evidence captured for both the default-OFF and opt-in-ON paths against a locally running `llama3:latest` Ollama instance (2026-09-14)
  - **Planning ticket:** [Organic LLM Village map](../.scratch/organic-village/map.md) (deferred "wire LLM at boot" item)

- **Slice:** [053 — F-026 derive monster exclusion from town bounds](slices/053-f026-monster-exclusion-from-town-bounds.md) — **100% complete; focused, parse, full GUT, record-sync, and runtime boot validation passed**
  - **Feature:** [F-026](FEATURE-LIST.md#f-026-organic-districted-starting-city) (final item; feature now `Implemented`)
  - **Public seam:** `server/server_monster_manager.gd` (`town_exclusion_half_extent()`, `TOWN_EXCLUSION_MARGIN_YARDS`, per-instance `exclusion_half_extent` `_init` param), `server/server_main.gd` (`_start_server()` deriving/logging the exclusion half-extent from the validated town blueprint)
  - **Validation:** focused unit passed 16/16 tests (175 assertions), exit 0; both `server/server_monster_manager.gd` and `server/server_main.gd` check-only exit 0; full GUT passed 315/315 tests across 44/44 scripts and 1224 assertions, exit 0; record sync exit 0; runtime boot evidence captured (derived half-extent logged as 32.0 yd, matching prior hard-coded behavior for the shipped fixture, 2026-09-14)
  - **Planning ticket:** [Organic LLM Village map](../.scratch/organic-village/map.md) (closes the map's last deferred item)

- **Slice:** [008 — Async validated sector blueprint contract](slices/008-sector-blueprint-contract.md) — **100% complete; focused public-seam validation passed**
  - **Feature:** [IP-004](FEATURE-LIST.md#ip-004-structured-sector-blueprint-translation)
  - **Tech debt:** no Slice 008-specific test migration debt remains; [DT-006](TECHNICAL-DEBT-TRACKER.md#dt-006-remaining-hand-rolled-smoke-tests-not-yet-migrated-to-gut) (unrelated hand-rolled scripts) is now resolved (Slice 041).
  - **Planning ticket:** [Sector blueprint contract](../.scratch/game-vision/issues/15-sector-blueprint-contract.md)

- **Slice:** [009 — Asynchronous provisional sector generation](slices/009-provisional-sector-generation.md) — **100% complete; focused and full-suite public-seam validation passed**
  - **Feature:** [IP-008](FEATURE-LIST.md#ip-008-just-in-time-sector-generation)
  - **Tech debt:** none new; [DT-006](TECHNICAL-DEBT-TRACKER.md#dt-006-remaining-hand-rolled-smoke-tests-not-yet-migrated-to-gut) (unrelated hand-rolled scripts) is now resolved (Slice 041).
  - **Planning ticket:** [Provisional sector generation](../.scratch/game-vision/issues/16-provisional-sector-generation.md)

- **Slice:** [014 — Sector blueprint schema v2: structures and spawn points](slices/014-sector-blueprint-schema-v2-structures.md) — **100% complete; focused and full-suite validation passed**
  - **Feature:** [F-017](FEATURE-LIST.md#f-017-sector-blueprint-schema-v2-structures-and-spawn-points)
  - **Tech debt:** none identified
  - **Planning ticket:** [Starting Town map](../.scratch/starting-town/map.md), [issue 01](../.scratch/starting-town/issues/01-schema-v2-structures-and-spawn-points.md)

- **Slice:** [015 — Client-side sector geometry translation](slices/015-sector-geometry-translation.md) — **100% complete; focused and full-suite validation passed**
  - **Feature:** [F-018](FEATURE-LIST.md#f-018-client-side-sector-geometry-translation)
  - **Tech debt:** none identified
  - **Planning ticket:** [Starting Town map](../.scratch/starting-town/map.md), [issue 02](../.scratch/starting-town/issues/02-geometry-translation-strategy.md)

- **Slice:** [016 — Starting town hub fixture](slices/016-starting-town-hub-fixture.md) — **100% complete; focused and full-suite validation passed**
  - **Feature:** [F-019](FEATURE-LIST.md#f-019-starting-town-hub-fixture)
  - **Tech debt:** none identified
  - **Planning ticket:** [Starting Town map](../.scratch/starting-town/map.md), [issue 03](../.scratch/starting-town/issues/03-hub-sector-identity-and-pinning.md), [issue 05](../.scratch/starting-town/issues/05-player-house-allocation.md)

- **Slice:** [017 — Server-to-client blueprint replication](slices/017-blueprint-replication.md) — **100% complete; focused and full-suite validation passed**
  - **Feature:** [F-020](FEATURE-LIST.md#f-020-server-to-client-sector-blueprint-replication)
  - **Tech debt:** none identified
  - **Planning ticket:** [Starting Town map](../.scratch/starting-town/map.md), [issue 06](../.scratch/starting-town/issues/06-blueprint-replication-contract.md)

- **Slice:** [018 — Facade enter/exit proximity labels](slices/018-facade-enter-exit.md) — **100% complete; focused and full-suite validation passed**
  - **Feature:** [F-021](FEATURE-LIST.md#f-021-facade-enter-exit-proximity-labels)
  - **Tech debt:** none identified
  - **Planning ticket:** [Starting Town map](../.scratch/starting-town/map.md), [issue 04](../.scratch/starting-town/issues/04-facade-representation-and-enter-exit.md)

- **Slice:** [019 — Player house allocation](slices/019-player-house-allocation.md) — **100% complete; focused and full-suite validation passed**
  - **Feature:** [F-022](FEATURE-LIST.md#f-022-player-house-allocation)
  - **Tech debt:** none identified
  - **Planning ticket:** [Starting Town map](../.scratch/starting-town/map.md), [issue 05](../.scratch/starting-town/issues/05-player-house-allocation.md)

- **Slice:** [023 — Bigger organic districted starting town](slices/023-organic-districted-town.md) — **100% complete; focused and full-suite validation passed**
  - **Feature:** [F-026](FEATURE-LIST.md#f-026-organic-districted-starting-city) (supersedes [F-019](FEATURE-LIST.md#f-019-starting-town-hub-fixture))
  - **Tech debt:** [DT-008](TECHNICAL-DEBT-TRACKER.md#dt-008-per-tile-staticbody3d-geometry-did-not-scale-to-city-size) — introduced the per-tile-body scaling liability (resolved by Slice 024).
  - **Planning ticket:** [Organic LLM Village map](../.scratch/organic-village/map.md) (decisions Q1–Q5)

- **Slice:** [024 — Scalable geometry pass](slices/024-scalable-geometry-pass.md) — **100% complete; focused and full-suite validation passed**
  - **Feature:** [F-018](FEATURE-LIST.md#f-018-client-side-sector-geometry-translation) / [F-026](FEATURE-LIST.md#f-026-organic-districted-starting-city)
  - **Tech debt:** resolves [DT-008](TECHNICAL-DEBT-TRACKER.md#dt-008-per-tile-staticbody3d-geometry-did-not-scale-to-city-size) — merged `ArrayMesh` ground + one merged `Walls` body; town size decoupled from physics body count.
  - **Planning ticket:** [Organic LLM Village map](../.scratch/organic-village/map.md) (Slice 024, geometry-pass half)

- **Slice:** [025 — Schema v3 organic vocabulary](slices/025-organic-vocabulary.md) — **100% complete; focused and full-suite validation passed**
  - **Feature:** [F-017](FEATURE-LIST.md#f-017-sector-blueprint-schema-v2-structures-and-spawn-points) / [F-018](FEATURE-LIST.md#f-018-client-side-sector-geometry-translation) / [F-026](FEATURE-LIST.md#f-026-organic-districted-starting-city)
  - **Tech debt:** none identified
  - **Planning ticket:** [Organic LLM Village map](../.scratch/organic-village/map.md) (Q3 vocabulary decision)

- **Slice:** [026 — LLM town generation with a required-structure guarantee](slices/026-llm-town-generation.md) — **100% complete; focused and full-suite validation passed**
  - **Feature:** [F-026](FEATURE-LIST.md#f-026-organic-districted-starting-city)
  - **Tech debt:** none identified
  - **Planning ticket:** [Organic LLM Village map](../.scratch/organic-village/map.md) (Q2 hybrid LLM + guarantee + fallback)

- **Slice:** [031 — Bigger rural village with NPC and leader housing](slices/031-bigger-village-npc-leader-housing.md) — **100% complete; focused and full-suite validation passed**
  - **Feature:** [F-026](FEATURE-LIST.md#f-026-organic-districted-starting-city)
  - **Tech debt:** none identified
  - **Planning ticket:** [Organic LLM Village map](../.scratch/organic-village/map.md) (user request: ~3x bigger + NPC/leader housing)

- **Slice:** [036 — Imperial world-scale measurement contract (WorldScale)](slices/036-world-scale-measurement-contract.md) — **100% complete; focused and full-suite validation passed**
  - **Feature:** [F-028](FEATURE-LIST.md#f-028-imperial-world-scale-measurement-contract) (cross-cutting scale contract)
  - **Tech debt:** none identified
  - **Planning ticket:** [World Scale map](../.scratch/world-scale/map.md) (tickets 01–05), [ADR 0003](adr/0003-imperial-world-scale.md)

- **Slice:** [037 — World-scale constant relabel (meters → yards)](slices/037-world-scale-constant-relabel.md) — **100% complete; rename-only, full-suite validation passed (207/207 unchanged)**
  - **Feature:** [F-028](FEATURE-LIST.md#f-028-imperial-world-scale-measurement-contract) (completes constant adoption)
  - **Tech debt:** none identified
  - **Planning ticket:** [World Scale map](../.scratch/world-scale/map.md) (ticket 04), [ADR 0003](adr/0003-imperial-world-scale.md)

#### Phase 7 — Delivery workflow capabilities

- **Slice:** [010 — Core mechanics architecture contract](slices/010-core-mechanics-architecture.md) — **100% complete; focused documentation and full-suite validation passed**
  - **Features:** [F-007](FEATURE-LIST.md#f-007-living-architecture-anchor), [P-016](FEATURE-LIST.md#p-016-biological-progression-and-kinetic-combat-systems)
  - **Tech debt:** none identified
  - **Planning ticket:** [Core mechanics architecture contract](../.scratch/game-vision/issues/17-core-mechanics-architecture.md)
  - **Decision:** [ADR 0002](adr/0002-authoritative-mechanics-and-progression.md)

- **Slice:** [011 — Mind versus Tool architecture refinement](slices/011-mind-tool-architecture-refinement.md) — **100% complete; focused documentation and full-suite validation passed**
  - **Features:** [F-007](FEATURE-LIST.md#f-007-living-architecture-anchor), [P-016](FEATURE-LIST.md#p-016-biological-progression-and-kinetic-combat-systems)
  - **Tech debt:** none identified
  - **Planning ticket:** [Mind versus Tool architecture refinement](../.scratch/game-vision/issues/18-mind-tool-architecture-refinement.md)
  - **Decision:** updates [ADR 0002](adr/0002-authoritative-mechanics-and-progression.md)

- **Slice:** [027 — Agent-assisted delivery orchestration](slices/027-agent-assisted-delivery-orchestration.md) — **100% complete; documentation checks and full-suite validation passed**
  - **Feature:** [P-004](FEATURE-LIST.md#p-004-agent-assisted-delivery-orchestration)
  - **Tech debt:** none identified
  - **Planning ticket:** [game-vision map](../.scratch/game-vision/map.md) (Delivery workflow / Handoff rule)
  - **Decision:** no new ADR; formalizes the existing Copilot → Claude Code CLI handoff mechanism

#### Phase 10 — Authoritative runtime and action input

- **Slice:** [012 — Server-authoritative melee strike and hit registration](slices/012-authoritative-melee-strike.md) — **100% complete; focused and full-suite validation passed**
  - **Feature:** [IP-015](FEATURE-LIST.md#ip-015-authoritative-action-input)
  - **Tech debt:** none identified
  - **Planning ticket:** [melee-combat map](../.scratch/melee-combat/map.md) and its resolved issues 01–05
  - **Decision:** no new ADR; implements [ADR 0002](adr/0002-authoritative-mechanics-and-progression.md)'s existing action-resolution contract

- **Slice:** [013 — Melee strike visual indicator and player facing](slices/013-melee-strike-visual-indicator.md) — **100% complete; focused and full-suite validation passed**
  - **Feature:** [IP-015](FEATURE-LIST.md#ip-015-authoritative-action-input)
  - **Tech debt:** none identified
  - **Planning ticket:** [melee-combat map](../.scratch/melee-combat/map.md) (its "Not yet specified" presentation item)
  - **Decision:** no new ADR; presentation-only layer over Slice 012's authoritative lifecycle and its new `melee_swing_started` broadcast signal

- **Slice:** [020 — Monster HP, damage, and death model](slices/020-monster-hp-damage-death.md) — **100% complete; focused and full-suite validation passed**
  - **Feature:** [IP-023](FEATURE-LIST.md#ip-023-basic-monster-combat)
  - **Tech debt:** none identified
  - **Planning ticket:** [Basic Monsters map](../.scratch/basic-monsters/map.md), [issue 01](../.scratch/basic-monsters/issues/01-hp-damage-death-model.md)

- **Slice:** [021 — Monster AI state machine with attack telegraph](slices/021-monster-ai-state-machine.md) — **100% complete; focused and full-suite validation passed**
  - **Feature:** [IP-023](FEATURE-LIST.md#ip-023-basic-monster-combat)
  - **Tech debt:** none identified
  - **Planning ticket:** [Basic Monsters map](../.scratch/basic-monsters/map.md), [issue 02](../.scratch/basic-monsters/issues/02-monster-state-machine-with-telegraph.md)

- **Slice:** [022 — Monster spawning and respawn (outside town)](slices/022-monster-spawning-and-respawn.md) — **100% complete; focused and full-suite validation passed**
  - **Feature:** [IP-023](FEATURE-LIST.md#ip-023-basic-monster-combat)
  - **Tech debt:** none identified
  - **Planning ticket:** [Basic Monsters map](../.scratch/basic-monsters/map.md), [issue 03](../.scratch/basic-monsters/issues/03-monster-spawn-points-from-town-schema.md)

- **Slice:** [029 — Authoritative monster melee damage and death broadcast](slices/029-authoritative-monster-melee-damage.md) — **100% complete; focused and full-suite validation passed**
  - **Feature:** [IP-023](FEATURE-LIST.md#ip-023-basic-monster-combat)
  - **Tech debt:** none identified
  - **Planning ticket:** [Basic Monsters map](../.scratch/basic-monsters/map.md)
  - **Decision:** no new ADR; wires existing Slice 012 hit-test and Slice 020/021 damage/death seams through the existing combat-event broadcast channel

- **Slice:** [033 — Client monster replication and rendering](slices/033-client-monster-replication-and-rendering.md) — **100% complete; focused and full-suite validation passed; interactive GUI confirmation obtained (2026-09-13)**
  - **Feature:** [IP-023](FEATURE-LIST.md#ip-023-basic-monster-combat)
  - **Tech debt:** none identified
  - **Planning ticket:** [Basic Monsters map](../.scratch/basic-monsters/map.md)
  - **Decision:** no new ADR; purely cosmetic client layer over the existing Slice 020-022/029 authoritative monster lifecycle, following the established remote-player replication pattern

- **Slice:** [030 — Server-side wall and building collision](slices/030-server-side-collision.md) — **100% complete; focused and full-suite validation passed**
  - **Feature:** [F-027](FEATURE-LIST.md#f-027-server-authoritative-movement-collision)
  - **Tech debt:** none identified
  - **Planning ticket:** none (arose from the "is the village walkable?" review)
  - **Decision:** no new ADR; extends the ADR 0001 server-authoritative movement model with collision

#### Phase 9 — Canon persistence and world mutation

- **Slice:** [038 — Shared server-owned SQLite persistence foundation](slices/038-shared-sqlite-persistence-foundation.md) — **100% complete; engine seam only (no domain tables); focused and full-suite validation passed**
  - **Feature:** [F-029](FEATURE-LIST.md#f-029-shared-server-owned-sqlite-persistence-foundation)
  - **Tech debt:** none identified
  - **Planning ticket:** [player-accounts issue 03](../.scratch/player-accounts/issues/03-research-godot-persistence-sqlite.md), [player-accounts issue 06](../.scratch/player-accounts/issues/06-account-character-persistence-design.md) (the persistence-mechanism decision was made in the player-accounts design track; this slice is Wave 4, the shared build-once foundation both Phase 9 Canon and Phase 14 accounts consume)
  - **Decision:** no new ADR; implements the already-accepted ticket 03/06 decision (one shared `godot-sqlite` engine, WAL, fail-closed `user_version`, parameter-bound queries)
- **Slice:** [045 — Canon sector persistence and one-time blueprint canonicalization](slices/045-canon-sector-persistence.md) — **100% complete; focused, runtime parse, full GUT, and record-sync validation passed**
  - **Features:** [P-011](FEATURE-LIST.md#p-011-canonical-history-archive), [P-012](FEATURE-LIST.md#p-012-one-time-blueprint-canonicalization)
  - **Planning ticket:** [Canon persistence issue](../.scratch/game-vision/issues/05-define-canon-persistence.md)
  - **Public seam:** `server/canon_repository.gd` over `server/sqlite_store.gd`; no client, geometry, mutation, or boundary-triggering code
  - **Validation:** focused Canon integration path passed 94/94 tests and 375 assertions, exit 0; `server/server_main.gd` check-only passed, exit 0; full GUT passed 268/268 tests across 36/36 scripts, exit 0; `scripts/check_record_sync.sh` passed with 0 errors and 6 pre-existing warnings
- **Slice:** [050 — Canon mutation persistence (dynamic world mutation tracking)](slices/050-canon-mutation-persistence.md) — **delivered; server-only append-only mutation log, idempotent by event_id, optimistic per-sector revision, fail-closed at the boundary**
  - **Feature:** [P-013](FEATURE-LIST.md#p-013-dynamic-world-mutation-tracking) (first slice)
  - **Tech debt:** none identified
  - **Planning ticket:** [Canon persistence issue](../.scratch/game-vision/issues/05-define-canon-persistence.md)
  - **Public seam:** `server/canon_mutation_repository.gd` over `server/sqlite_store.gd` + the Slice 045 `server/canon_repository.gd`; no client, geometry, GUID-assignment, RPC, or gameplay-authorization code
  - **Validation:** focused integration suite passed with the 11 new `test_canon_mutation_repository` cases (94 → 105 integration tests, all passing), exit 0; `server/canon_mutation_repository.gd` check-only passed, exit 0; full GUT passed 293/293 tests across 40/40 scripts, exit 0 (`scripts_expected == scripts_ran`); `scripts/check_record_sync.sh` passed with 0 errors and 6 pre-existing warnings

#### Phase 13 — Public game access

- **Slice:** [028 — WireGuard remote-access infrastructure foundation](slices/028-wireguard-remote-access-infrastructure-foundation.md) — **records-first handoff complete; awaiting live OPNsense/host execution evidence**
  - **Feature:** [P-024](FEATURE-LIST.md#p-024-public-game-access-via-opnsense-native-wireguard)
  - **Tech debt:** none identified
  - **Planning ticket:** [Public Game Access via WireGuard map](../.scratch/wan-wireguard/map.md), [issue 03](../.scratch/wan-wireguard/issues/03-opnsense-wireguard-infra-automation.md), [issue 05](../.scratch/wan-wireguard/issues/05-host-firewall-lockdown-script.md)
  - **Decision:** no new ADR; implements the existing SDD-GAME-WG-001 design basis
- **Slice:** [032 — wgnetstack netstack bridge (Linux prototype)](slices/032-wgnetstack-netstack-bridge-linux-prototype.md) — **delivered; Godot client reaches `connected: player spawned` through the bridge against the live, restarted server; direct (no-bridge) re-run against the same server confirms the earlier gap was a stale-server RPC method-table mismatch, not a bridge or Slice 033 code defect**
  - **Feature:** [P-024](FEATURE-LIST.md#p-024-public-game-access-via-opnsense-native-wireguard)
  - **Tech debt:** none identified
  - **Planning ticket:** [Public Game Access via WireGuard map](../.scratch/wan-wireguard/map.md), [issue 01](../.scratch/wan-wireguard/issues/01-enet-transport-netstack-bridging.md), [issue 02](../.scratch/wan-wireguard/issues/02-godot-gdextension-wireguard-netstack.md)
  - **Decision:** no new ADR; implements the existing SDD-GAME-WG-001 design basis (issue 01/02 decisions)
- **Slice:** [034 — wgnetstack in-client GDExtension + tunnel integration (Linux)](slices/034-wgnetstack-godot-gdextension-tunnel-integration-linux.md) — **delivered; the real Godot client opens the WireGuard tunnel in-process via the `WgNetstack` GDExtension (no external process, no OS TUN, no admin) and reaches `connected: player spawned` against the live server; tunnel mode is env-gated and default-off (direct connect unchanged), and `scripts/run_gut_validation.sh` stays green 199/199**
  - **Feature:** [P-024](FEATURE-LIST.md#p-024-public-game-access-via-opnsense-native-wireguard)
  - **Tech debt:** none identified
  - **Planning ticket:** [Public Game Access via WireGuard map](../.scratch/wan-wireguard/map.md), [issue 02](../.scratch/wan-wireguard/issues/02-godot-gdextension-wireguard-netstack.md)
  - **Decision:** no new ADR; implements the existing SDD-GAME-WG-001 design basis (issue 02 decision), packaging the Slice 032 bridge as a GDExtension
- **Slice:** [035 — wgnetstack Windows DLL cross-compile + client repackage](slices/035-wgnetstack-windows-dll-client-repackage.md) — **delivered (build + package); the GDExtension cross-compiles via mingw to a valid PE32+ Windows DLL, and `dist/Project0-client-windows-x64-0.7.0-tunnel.zip` bundles it next to `Project0.exe`. The Windows runtime spawn-through-tunnel proof is now user-confirmed (2026-09-14).**
  - **Feature:** [P-024](FEATURE-LIST.md#p-024-public-game-access-via-opnsense-native-wireguard)
  - **Tech debt:** none identified
  - **Planning ticket:** [Public Game Access via WireGuard map](../.scratch/wan-wireguard/map.md), [issue 02](../.scratch/wan-wireguard/issues/02-godot-gdextension-wireguard-netstack.md)
  - **Decision:** no new ADR; implements the existing SDD-GAME-WG-001 design basis (issue 02 decision), Windows packaging of the Slice 034 GDExtension
- **Slice:** [048 — WireGuard invite-code enrollment service (logic + tests)](slices/048-wireguard-enrollment-service.md) — **100% complete for this slice's scope; FastAPI service logic under `infra/enrollment/` proven by automated tests against a fake OPNsense client and a temp sqlite DB; live deployment behind `enroll.valentin.vip` is a follow-up ops step**
  - **Feature:** [P-024](FEATURE-LIST.md#p-024-public-game-access-via-opnsense-native-wireguard)
  - **Tech debt:** none identified
  - **Planning ticket:** [Public Game Access via WireGuard map](../.scratch/wan-wireguard/map.md), [issue 04](../.scratch/wan-wireguard/issues/04-enrollment-service-invite-system.md)
  - **Decision:** no new ADR; implements the existing SDD-GAME-WG-001 design basis (issue 04 decision) with one non-architectural choice — stdlib `sqlite3` (not `godot-sqlite`, which is Godot-only) for this standalone Python service's local store
  - **Public seam:** `infra/enrollment/service.py`'s `EnrollmentService.redeem()`, exposed as `POST /redeem` (`infra/enrollment/app.py`) and an admin CLI (`infra/enrollment/cli.py`)
  - **Validation:** `python3 -m pytest infra/enrollment/tests -q` passed 39/39, exit 0; `scripts/check_record_sync.sh` passed with 0 errors and 6 pre-existing warnings, exit 0; no `.gd` files changed, so the GUT suite was not run
- **Slice:** [049 — WireGuard peer revocation/ban lifecycle (logic + tests)](slices/049-wireguard-revocation-lifecycle.md) — **100% complete for this slice's scope; `RevocationService` and its OPNsense `delete_client`/store `release_allocation_by_public_key` seams proven by automated tests against a fake OPNsense client and a temp sqlite DB; live deployment and real tunnel-teardown timing are follow-ups**
  - **Feature:** [P-024](FEATURE-LIST.md#p-024-public-game-access-via-opnsense-native-wireguard)
  - **Tech debt:** none identified
  - **Planning ticket:** [Public Game Access via WireGuard map](../.scratch/wan-wireguard/map.md), [issue 06](../.scratch/wan-wireguard/issues/06-revocation-and-ban-lifecycle.md)
  - **Decision:** no new ADR; implements the existing SDD-GAME-WG-001 design basis (issue 06 decision) with one non-architectural choice — revocation is keyed on the peer's `public_key`, not `ip_address` or `invite_code` (see the slice record's Identifier choice section); idempotent re-enrollment (issue 06 point 4) is deliberately deferred as a documented follow-up
  - **Public seam:** `infra/enrollment/service.py`'s `RevocationService.revoke()`, exposed only via the operator CLI (`infra/enrollment/cli.py revoke-peer <public_key>`) — no HTTP admin route, deliberately
  - **Validation:** `python3 -m pytest infra/enrollment/tests -q` passed 54/54 (39 pre-existing, 15 new), exit 0; `scripts/check_record_sync.sh` passed with 0 errors and 6 pre-existing warnings, exit 0; no `.gd` files changed, so the GUT suite was not run
- **Slice:** [054 — Secure Windows tunnel enrollment and credential storage](slices/054-secure-windows-tunnel-enrollment.md) — **in progress; secure launcher implemented and tested; enrollment service deployed live and validated; Windows-launcher live tunnel validation pending**
  - **Feature:** [F-035](FEATURE-LIST.md#f-035-secure-windows-tunnel-enrollment-and-credential-storage), under [P-024](FEATURE-LIST.md#p-024-public-game-access-via-opnsense-native-wireguard)
  - **Planning basis:** [Slice 048](slices/048-wireguard-enrollment-service.md), [Slice 049](slices/049-wireguard-revocation-lifecycle.md), and the resolved WAN WireGuard issue map
  - **Public seam:** Windows enrollment client, `POST /redeem`, DPAPI credential store, and the existing `NetworkClient`/`WgNetstack` startup seam
  - **Deployment:** the enrollment service is live behind `enroll.valentin.vip` (systemd `project0-enrollment.service` on the okami Linux host, `192.168.1.254:8095`, OPNsense nginx TLS vhost publishing only `/healthz` and `/redeem`); the WireGuard endpoint uses the static WAN IP `192.69.180.236:51900` directly (no `game` DNS record). Validated 2026-09-14: `infra/enrollment/tests` 55/55 passed; live `/healthz` and `/redeem` proof through Cloudflare (real OPNsense peer registration, then revoke); method guard confirmed.
  - **Non-goal:** no change to the verified temporary WAN path until replacement enrollment evidence exists

#### Phase 14 — Player accounts and characters

- **Slice:** [039 — Accounts and characters persistence repository](slices/039-accounts-characters-repository.md) — **100% complete; server-only data layer (no RPC/auth/client/world entry); focused and full-suite validation passed**
  - **Feature:** [F-030](FEATURE-LIST.md#f-030-accounts-and-characters-persistence-repository)
  - **Tech debt:** none identified
  - **Planning ticket:** [player-accounts spec](../.scratch/player-accounts/spec.md), [player-accounts issue 05](../.scratch/player-accounts/issues/05-character-data-model-and-lifecycle.md), [player-accounts issue 06](../.scratch/player-accounts/issues/06-account-character-persistence-design.md)
  - **Decision:** no new ADR; implements the already-accepted ticket 05/06 design with one documented reconciliation (ticket 06's partial unique index `WHERE deleted = 0` is authoritative over ticket 05's "name stays reserved" prose — see the slice record's Reconciliation section)
- **Slice:** [040 — Account authentication and session (server)](slices/040-account-auth-session.md) — **100% complete; additive PBKDF2 auth/session RPC seam and first-runtime accounts-DB boot wiring; existing connect/spawn lifecycle unchanged; focused and full-suite validation passed**
  - **Feature:** [F-031](FEATURE-LIST.md#f-031-account-authentication-and-session-server)
  - **Tech debt:** none identified
  - **Planning ticket:** [player-accounts spec](../.scratch/player-accounts/spec.md) (Implementation Slice 3), [handoff-040](../.scratch/player-accounts/handoff-040-account-auth-session.md)
  - **Decision:** no new ADR; implements the already-accepted ticket 04 design (PBKDF2-HMAC-SHA256, opaque in-memory sessions, no-enumeration `BAD_CREDENTIALS`) with one implementation-level detail — hand-rolling the RFC 8018 PBKDF2 block construction on `Crypto.hmac_digest` since Godot 4.3 has no native PBKDF2 API, proven against a published known-answer vector (see the slice record's No-ADR rationale)
- **Slice:** [042 — Character CRUD over the wire (server)](slices/042-character-crud-rpc.md) — **100% complete; session-gated Character CRUD RPC seam; account scoping derived from the session (the client never supplies an account_id); no client UI, no world entry; focused and full-suite validation passed**
  - **Feature:** [F-032](FEATURE-LIST.md#f-032-character-crud-over-the-wire-server)
  - **Tech debt:** none identified
  - **Planning ticket:** [player-accounts spec](../.scratch/player-accounts/spec.md) (Implementation Slice 4), [handoff-042](../.scratch/player-accounts/handoff-042-character-crud-rpc.md)
  - **Decision:** no new ADR; implements the already-accepted ticket 05 Character lifecycle over the existing Slice 040 auth-RPC pattern
- **Slice:** [043 — Character world entry (server-side binding)](slices/043-character-world-entry.md) — **100% complete; server resolves the session's selected Character and binds its identity/cosmetic to the Player; additive to the connect-time spawn; no client UI; focused and full-suite validation passed**
  - **Feature:** [F-033](FEATURE-LIST.md#f-033-character-world-entry-server-binding)
  - **Tech debt:** none identified
  - **Planning ticket:** [player-accounts spec](../.scratch/player-accounts/spec.md) (Implementation Slice 6), [handoff-043](../.scratch/player-accounts/handoff-043-pregameplay-auth-character-flow.md)
  - **Decision:** no new ADR; delivers the server half of the coupled spec 5+6 flow additively (no mandatory-auth hard-flip), the client screens following as Slice 044
- **Slice:** [044 — Client login and character selection UI](slices/044-client-login-character-ui.md) — **server validation complete; account_gate and character_gate scenes + controllers wired to Phase 40-43 RPC seams; Windows GUI verification pending**
  - **Feature:** [F-033](FEATURE-LIST.md#f-033-character-world-entry-server-binding) (client half), [F-034](FEATURE-LIST.md#f-034-client-login-and-character-selection-screens) (new feature for the UI)
  - **Tech debt:** none identified
  - **Planning ticket:** [player-accounts spec](../.scratch/player-accounts/spec.md) (Implementation Slice 5), [handoff-044](../.scratch/player-accounts/handoff-044-client-login-character-screens.md) (if created)
  - **Decision:** no new ADR; defensive refactor discovered spawn-deferral brittleness against e2e harnesses; reverted deferral, documented intended pattern (login manages connection, gameplay inherits it); Linux authoritative validation passes 315/315 tests across 44/44 scripts and 1224 assertions. Known limitation: spawn may misfire into login menu if Player RPC arrives mid-auth (low probability, low impact, documented as follow-up). GUI-confirmed behavior on Windows remains the final Slice 044 gate.

## Implementation slice acceptance

Every slice links:

- [ ] Slice design (SDD), when the boundary is meaningful.
- [ ] BDD scenarios for normal, highest-risk, and applicable safety/idempotency behavior.
- [ ] TDD tests at the agreed public seam.
- [ ] Related ADR, or explicit no-ADR rationale.
- [ ] Focused and final validation results.
- [ ] Review outcome and documentation updates.

## Work queue

This section lists planned work with no implementation slice started yet. An
item only becomes a tracked, in-progress slice (and moves out of this queue)
once its SDD/BDD/TDD scope is set and a `docs/slices/0NN-*.md` record exists.

- [x] Define the Godot 4 High-Level Multiplayer authority model for
  networked gameplay (client input/prediction vs. server
  simulation/replication), per [game-vision issue 03](../.scratch/game-vision/issues/03-define-authority-model.md).
  Resolved in practice by [ADR 0001](adr/0001-client-side-authority-for-first-slice.md),
  formalized as normative law in `CLAUDE.md`, and implemented/validated by
  Slices 002, 004, 005, 007, and 012.
- [x] Done — Sector-boundary detection for IP-008 (Phase 8): Slice 046 triggers
  `server/provisional_sector_generator.gd` requests when an authoritative
  player position crosses into an unexplored sector, closing the trigger gap
  between Slice 009 and a fully `Implemented`
  [IP-008](FEATURE-LIST.md#ip-008-just-in-time-sector-generation).
- [~] Active — Canon persistence (Phase 9): the durable sector and
  canonicalization seam is delivered (Slices 045/047) on the shared engine
  ([Slice 038](slices/038-shared-sqlite-persistence-foundation.md), F-029 —
  `server/sqlite_store.gd`), and the first mutation slice landed (Slice 050 —
  `server/canon_mutation_repository.gd`: append-only, idempotent, optimistic
  per-sector revision), so
  [P-011](FEATURE-LIST.md#p-011-canonical-history-archive) and
  [P-012](FEATURE-LIST.md#p-012-one-time-blueprint-canonicalization) are
  `Implemented` and [P-013](FEATURE-LIST.md#p-013-dynamic-world-mutation-tracking)
  is `In Progress`. Remaining P-013 work (stable entity GUIDs, physical-event
  verification, actor authorization, the mutation-intent RPC, and replay into
  live scene state) and the JIT boundary path continue as follow-up slices,
  resolving the open event-model questions in
  [game-vision issue 05](../.scratch/game-vision/issues/05-define-canon-persistence.md).
- [ ] Queued — Containerized fixed-tick server runtime (Phase 10, blocked):
  [P-014](FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)
  needs the runtime-boundary questions in
  [game-vision issue 06](../.scratch/game-vision/issues/06-define-runtime-boundaries.md)
  resolved, which is itself blocked on the canon persistence design above.
- [ ] Queued — Remaining delivery workflow capabilities (Phase 7): Remote-SSH
  server workspace
  ([P-005](FEATURE-LIST.md#p-005-remote-ssh-server-workspace)) and
  token-efficient asset quarantine
  ([P-006](FEATURE-LIST.md#p-006-token-efficient-asset-quarantine)).
  Agent-assisted delivery orchestration
  ([P-004](FEATURE-LIST.md#p-004-agent-assisted-delivery-orchestration)) was
  delivered by [Slice 027](slices/027-agent-assisted-delivery-orchestration.md).
- [x] Done — DT-006 remaining hand-rolled smoke test migration (Phase 1
  residual, cross-cutting): the last hand-rolled `scripts/test_*.gd` scripts
  are now closed out —
  [Slice 041](slices/041-dt-006-remaining-smoke-test-gut-migration.md) deleted
  the duplicate blueprint-contract script, reclassified the Ollama script as a
  probe, and wrapped the three remaining real-process E2E harnesses in GUT,
  fixing a latent Slice 030 town-collision regression it surfaced in the melee
  harness along the way. See
  [DT-006](TECHNICAL-DEBT-TRACKER.md#dt-006-remaining-hand-rolled-smoke-tests-not-yet-migrated-to-gut).
- [x] Starting Town map (Phase 8/9 handoff, pre-slice design): charting a
  JIT-generated hub sector with facade House/Smithy/Armor Shop/Inn structures
  and per-player house allocation. Delivered as slices: sector-blueprint
  schema v2 (`structures`/`spawn_points`, Slice 014), client-side geometry
  translation (Slice 015), starting town hub fixture (Slice 016), and
  server-to-client blueprint replication (Slice 017). See
  [starting-town map](../.scratch/starting-town/map.md).
- [x] World Scale map (Phase 8, cross-cutting scale foundation): charting the
  Imperial world-scale measurement system (1 unit = 1 yard, world unit → Tile →
  Sector, ¼-mile Sector). Decisions locked in
  [ADR 0003](adr/0003-imperial-world-scale.md); delivered as
  [Slice 036](slices/036-world-scale-measurement-contract.md) (the `WorldScale`
  contract) and [Slice 037](slices/037-world-scale-constant-relabel.md) (the
  meters→yards constant relabel). See [world-scale map](../.scratch/world-scale/map.md).
- [ ] In progress — Basic Monsters map (Phase 10 handoff, pre-slice design):
  charting a minimal server-authoritative monster (flat HP/damage/death,
  detect/chase/attack state machine with a readable attack telegraph per
  `CLAUDE.md`'s Combat Reading rules), spawned from the Starting Town map's
  spawn points. Delivered as slices: HP/damage/death contract (Slice 020), the
  detect/chase/attack state machine (Slice 021), spawning and respawn outside
  town (Slice 022), wiring a player's accepted melee hit to monster
  damage/death server-side
  ([Slice 029](slices/029-authoritative-monster-melee-damage.md)), and client
  rendering of monsters and their hit/death reactions
  ([Slice 033](slices/033-client-monster-replication-and-rendering.md)).
  Monsters are now fully damageable, defeatable, and visibly renderable/
  fightable; only interactive GUI visual/fight confirmation remains before
  this map's "make monsters visible to and fightable by players" boundary is
  complete. See [basic-monsters map](../.scratch/basic-monsters/map.md).
- [x] Done — Organic LLM Village map (Phase 8): replaced the small Slice 016
  square hub with a large, organic, districted, walled starting city on the
  scale/feel of EverQuest Qeynos or FF7 Midgar, LLM-generated but validated so
  the required structures always exist. Decisions Q1–Q5 resolved.
  First slice delivered: [Slice 023](slices/023-organic-districted-town.md) — a
  bigger organic octagon hand-authored town (gate, radial avenues, central
  plaza, districts) rendered by the existing pipeline. Then
  [Slice 024](slices/024-scalable-geometry-pass.md) delivered the merged
  scalable geometry pass, resolving
  [DT-008](TECHNICAL-DEBT-TRACKER.md#dt-008-per-tile-staticbody3d-geometry-did-not-scale-to-city-size)
  so town size no longer multiplies physics bodies, and
  [Slice 025](slices/025-organic-vocabulary.md) added the schema-v3 organic
  vocabulary (gate/plaza/path/grass/water tiles + church/tavern/item_shop/well)
  and enriched the hub to use it, and
  [Slice 026](slices/026-llm-town-generation.md) added the `TownLayoutProvider`
  guarantee (LLM proposes, server validates + requires the fixed structures,
  else falls back to the fixture). Slice 031 grew the village to ~3x area
  (radius 30) with villager homes (`npc_house`) and the village leader's hall
  (`village_hall`). [Slice 052](slices/052-f026-llm-town-at-boot.md) wired LLM
  generation on at boot behind a default-off `PROJECT0_LLM_TOWN_AT_BOOT` flag
  (the fixture stays the default and always-safe fallback), and
  [Slice 053](slices/053-f026-monster-exclusion-from-town-bounds.md) replaced
  the hard-coded monster exclusion constant with a pure derivation from the
  validated town blueprint's actual tile bounds — the map's last deferred item.
  [F-026](FEATURE-LIST.md#f-026-organic-districted-starting-city) is now
  `Implemented`; this map is closed. See
  [organic-village map](../.scratch/organic-village/map.md).
- [x] In progress — Public game access via WireGuard (Phase 13): the first
  implementation slice,
  [028 — WireGuard remote-access infrastructure foundation](slices/028-wireguard-remote-access-infrastructure-foundation.md),
  is scoped against issues
  [03](../.scratch/wan-wireguard/issues/03-opnsense-wireguard-infra-automation.md)
  and
  [05](../.scratch/wan-wireguard/issues/05-host-firewall-lockdown-script.md)
  of the resolved [wan-wireguard map](../.scratch/wan-wireguard/map.md) under
  SDD-GAME-WG-001. Records-first: the infra scripts
  (`infra/opnsense/setup_wireguard_game_tunnel.py`,
  `ci/host-firewall-helper.sh`) and live-execution validation evidence are a
  follow-up handoff owned by Copilot.
- [~] Active — Secure Windows tunnel enrollment and credential storage (Phase
  13): [F-035](FEATURE-LIST.md#f-035-secure-windows-tunnel-enrollment-and-credential-storage)
  and [Slice 054](slices/054-secure-windows-tunnel-enrollment.md) replace the
  temporary embedded-key WAN verifier with invite redemption, client-generated
  keys, Windows DPAPI protection, automatic tunnel startup, and operator
  revocation. Keep the current verifier available until replacement evidence
  is complete.
  [032 — wgnetstack netstack bridge (Linux prototype)](slices/032-wgnetstack-netstack-bridge-linux-prototype.md)
  is scoped against issues
  [01](../.scratch/wan-wireguard/issues/01-enet-transport-netstack-bridging.md)
  and
  [02](../.scratch/wan-wireguard/issues/02-godot-gdextension-wireguard-netstack.md)
  to deliver S2: a `native/wgnetstack/` Go netstack bridge proven on Linux
  with the existing Godot client, ahead of S3 (Windows DLL validation,
  `.gdextension` packaging) and S4 (enrollment automation).
  [034 — wgnetstack in-client GDExtension + tunnel integration (Linux)](slices/034-wgnetstack-godot-gdextension-tunnel-integration-linux.md)
  delivers S3a: the Slice 032 bridge wrapped as a real in-process Godot 4.3
  GDExtension (`native/wgnetstack/gdext/`, godot-cpp-based, linking a new
  `cmd/cgoarchive` static build of the same bridge logic) plus a
  `client/network_client.gd` tunnel-mode integration, so the client opens the
  tunnel itself with no separate probe process.
  [Slice 035](slices/035-wgnetstack-windows-dll-client-repackage.md) delivers
  S3b, the Windows DLL cross-compile and client repackage, with the
  remote-Windows WAN runtime now user-confirmed (2026-09-14).
  [Slice 048](slices/048-wireguard-enrollment-service.md) delivers the
  invite-code enrollment service's logic (issue 04): single-use CSPRNG
  invites, strict public-key validation, `/32` pool allocation, and an
  injectable, fail-closed OPNsense client, proven by 39/39 passing automated
  tests.
  [Slice 049](slices/049-wireguard-revocation-lifecycle.md) delivers the
  revocation/ban lifecycle's logic (issue 06) on top of it:
  `RevocationService.revoke()` keyed on the peer's public key calls OPNsense
  `delClient` + `reconfigure` before releasing the local `/32` allocation
  back to the free pool, fail-closed on any upstream failure (no local
  release, so a banned peer never keeps access from a swallowed error), and
  idempotent (`ALREADY_ABSENT`) on an unknown or already-revoked key.
  Revocation is CLI/operator-only (`infra/enrollment/cli.py revoke-peer`); no
  HTTP admin route was added. Proven by 54/54 passing automated tests (39
  pre-existing plus 15 new). Live deployment behind `enroll.valentin.vip`,
  the real ~25s tunnel-teardown timing, and idempotent re-enrollment (reusing
  an existing peer UUID) remain queued, unscoped work for
  [P-024](FEATURE-LIST.md#p-024-public-game-access-via-opnsense-native-wireguard).
- [x] Ready — Player accounts and characters, data layer (Phase 14): design
  complete (`.scratch/player-accounts/spec.md`, all six tickets resolved,
  `CONTEXT.md` reconciled). The Wave 4 shared SQLite foundation
  ([Slice 038](slices/038-shared-sqlite-persistence-foundation.md), F-029)
  and the `accounts`/`characters` schema and repository on top of it
  ([Slice 039](slices/039-accounts-characters-repository.md), F-030) are now
  delivered.
- [x] In progress — Player accounts and characters, auth + session (Phase 14):
  the register/login ENet RPC seam, PBKDF2-HMAC-SHA256 hashing (off the main
  thread), and the opaque in-memory `SessionRegistry`
  ([Slice 040](slices/040-account-auth-session.md), F-031) are now delivered,
  additive to the existing always-playable connect lifecycle (auth is not yet
  mandatory for world entry).
- [x] In progress — Player accounts and characters, Character CRUD (Phase 14):
  session-gated `list_characters`/`create_character`/`select_character`/
  `delete_character` over ENet ([Slice 042](slices/042-character-crud-rpc.md),
  F-032) are delivered — every operation is scoped to the peer's session
  account (the client never supplies an `account_id`), enforcing the 5-cap,
  global live-name uniqueness, and ownership. Still queued, unscoped: client
  login/character screens replacing `identity_gate.tscn` (spec slice 5), and
  Character -> Player `start_for_peer` instantiation (spec slice 6). Self-serve
  registration behind the Phase 13 WireGuard gate; up to 5 globally-unique,
  soft-deletable Characters per Account.
- [x] In progress — Player accounts and characters, world entry (Phase 14):
  the server-side selected-Character world-entry binding
  ([Slice 043](slices/043-character-world-entry.md), F-033) is delivered —
  `get_selected_character` resolves the session's selection and
  `bind_character` instantiates the Player as it, additive to the connect-time
  spawn. Still queued, GUI-confirmed: the client login/register/character
  screens replacing `identity_gate.tscn` (spec slice 5, Slice 044), and the
  optional mandatory-auth hard-flip.