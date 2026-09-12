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
| 9. Canon persistence and world mutation | queued | Validated sectors and authorized player mutations are durable, uniquely identified, and recovered consistently from SQLite. |
| 10. Authoritative runtime and action input | in-progress | The server runs in an isolated fixed-tick runtime and resolves validated action intents, including combat, authoritatively. |
| 12. Biological progression and kinetic systems | queued | Server-validated play redistributes the six-node vessel, derives kinetic and friction effects, unlocks Meridians, applies Burnout, and enforces magic equilibrium without gating player reasoning. |
| 13. Public game access | queued | Remote players reach the home-hosted authoritative server over a split-tunnel WireGuard tunnel with invite-code enrollment and OPNsense-managed peers, without a VPS, client OS admin rights, or LAN exposure. |

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

Progress: **67%** (2 of 3 items done)

- Features: `done` [F-001](FEATURE-LIST.md#f-001-local-identity-gate-flat-plane-scene-and-player-movement) — local identity gate, flat-plane scene, and player movement.
- Tech debt: `done` [DT-002](TECHNICAL-DEBT-TRACKER.md#dt-002-no-automated-gdscript-test-framework) — GUT framework installed and Slice 001's smoke test migrated; `open` [DT-006](TECHNICAL-DEBT-TRACKER.md#dt-006-remaining-hand-rolled-smoke-tests-not-yet-migrated-to-gut) — remaining hand-rolled scripts pending incremental migration.

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

Progress: **29%** (2 of 7 items done)

- Features: `done` [F-005](FEATURE-LIST.md#f-005-automated-validation-gate-and-test-telemetry), [F-007](FEATURE-LIST.md#f-007-living-architecture-anchor); `queued` [P-004](FEATURE-LIST.md#p-004-agent-assisted-delivery-orchestration), [P-005](FEATURE-LIST.md#p-005-remote-ssh-server-workspace), [P-006](FEATURE-LIST.md#p-006-token-efficient-asset-quarantine).
- Tech debt: `open` [DT-007](TECHNICAL-DEBT-TRACKER.md#dt-007-lan-config-tests-spawn-a-real-server-on-the-fixed-default-port-9999-non-hermetic) — the LAN-config tests bind the fixed default port 9999, so the automated validation gate false-reds whenever that port is occupied.

**Phase 8 — JIT world generation and local inference**

Progress: **78%** (7 of 9 items done)

- Features: `in-progress` [IP-008](FEATURE-LIST.md#ip-008-just-in-time-sector-generation), `queued` [P-009](FEATURE-LIST.md#p-009-hardware-accelerated-local-inference), `done` [F-017](FEATURE-LIST.md#f-017-sector-blueprint-schema-v2-structures-and-spawn-points), `done` [IP-004](FEATURE-LIST.md#ip-004-structured-sector-blueprint-translation), `done` [F-018](FEATURE-LIST.md#f-018-client-side-sector-geometry-translation), `done` [F-019](FEATURE-LIST.md#f-019-starting-town-hub-fixture), `done` [F-020](FEATURE-LIST.md#f-020-server-to-client-sector-blueprint-replication), `done` [F-021](FEATURE-LIST.md#f-021-facade-enter-exit-proximity-labels), `done` [F-022](FEATURE-LIST.md#f-022-player-house-allocation).
- Tech debt: none yet.

- **Current slice:** [019 — Player house allocation](slices/019-player-house-allocation.md) — **100% complete; focused and full-suite validation passed**
  - **Feature:** [F-022](FEATURE-LIST.md#f-022-player-house-allocation)

**Phase 9 — Canon persistence and world mutation**

Progress: **0%** (0 of 3 items done)

- Features: `queued` [P-011](FEATURE-LIST.md#p-011-canonical-history-archive), [P-012](FEATURE-LIST.md#p-012-one-time-blueprint-canonicalization), [P-013](FEATURE-LIST.md#p-013-dynamic-world-mutation-tracking).
- Tech debt: none yet.

**Phase 10 — Authoritative runtime and action input**

Progress: **0%** (0 of 3 items done)

- Features: `queued` [P-014](FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime), `in-progress` [IP-015](FEATURE-LIST.md#ip-015-authoritative-action-input), `in-progress` [IP-023](FEATURE-LIST.md#ip-023-basic-monster-combat), [P-016](FEATURE-LIST.md#p-016-biological-progression-and-kinetic-combat-systems) (cross-cutting contract).
- Tech debt: none yet.

- **Current slice:** [022 — Monster spawning and respawn (outside town)](slices/022-monster-spawning-and-respawn.md) — **100% complete; focused and full-suite validation passed**
  - **Feature:** [IP-023](FEATURE-LIST.md#ip-023-basic-monster-combat)

**Phase 12 — Biological progression and kinetic systems**

Progress: **0%** (0 of 1 items done)

- Features: `queued` [P-016](FEATURE-LIST.md#p-016-biological-progression-and-kinetic-combat-systems).
- Tech debt: none yet.

**Phase 13 — Public game access**

Progress: **0%** (0 of 1 items done)

- Features: `ready` [P-024](FEATURE-LIST.md#p-024-public-game-access-via-opnsense-native-wireguard) — WireGuard public access is design-complete (all 6 `.scratch/wan-wireguard/` tickets resolved, SDD-GAME-WG-001) but has no implementation slice yet.
- Tech debt: none yet.

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
  - **Tech debt:** [DT-002](TECHNICAL-DEBT-TRACKER.md#dt-002-no-automated-gdscript-test-framework) is done; residual migration is tracked by [DT-006](TECHNICAL-DEBT-TRACKER.md#dt-006-remaining-hand-rolled-smoke-tests-not-yet-migrated-to-gut)

#### Phase 2 — Network connection proof

- **Slice:** [002 — Client connects to headless server and shows connected Player](slices/002-client-connects-to-server.md) — **100% complete**
  - **Feature:** [IP-001](FEATURE-LIST.md#ip-001-server-authoritative-networked-multiplayer)
  - **Tech debt:** [DT-006](TECHNICAL-DEBT-TRACKER.md#dt-006-remaining-hand-rolled-smoke-tests-not-yet-migrated-to-gut), [DT-003](TECHNICAL-DEBT-TRACKER.md#dt-003-no-interactive-gui-confirmation-of-slice-002s-visual-result)
  - **Planning ticket:** [Connect client to server](../.scratch/game-vision/issues/07-connect-client-to-server.md)

#### Phase 3 — LAN client connection

- **Slice:** [003 — Windows client connects to configurable Linux server](slices/003-lan-client-connection.md) — **100% complete; physical two-machine LAN run verified by user**
  - **Feature:** [F-003](FEATURE-LIST.md#f-003-lan-client-connection)
  - **Tech debt:** [DT-004](TECHNICAL-DEBT-TRACKER.md#dt-004-no-physical-two-machine-windowslinux-lan-run-of-slice-003)

#### Phase 4 — Authoritative movement proof

- **Slice:** [004 — Server-authoritative movement for one connected Player](slices/004-authoritative-player-movement.md) — **100% complete; interactive GUI confirmation and physical two-machine LAN run verified by user**
  - **Feature:** [IP-001](FEATURE-LIST.md#ip-001-server-authoritative-networked-multiplayer)
  - **Tech debt:** [DT-006](TECHNICAL-DEBT-TRACKER.md#dt-006-remaining-hand-rolled-smoke-tests-not-yet-migrated-to-gut), [DT-003](TECHNICAL-DEBT-TRACKER.md#dt-003-no-interactive-gui-confirmation-of-slice-002s-visual-result), [DT-004](TECHNICAL-DEBT-TRACKER.md#dt-004-no-physical-two-machine-windowslinux-lan-run-of-slice-003)
  - **Planning ticket:** [Authoritative Player movement](../.scratch/game-vision/issues/09-authoritative-player-movement.md)
  - **Planning ticket:** [LAN client connection](../.scratch/game-vision/issues/08-lan-client-connection.md)

#### Phase 5 — Prediction and reconciliation proof

- **Slice:** [005 — Predicted local movement with authoritative reconciliation](slices/005-prediction-reconciliation.md) — **100% complete; interactive GUI confirmation and physical two-machine LAN run verified by user**
  - **Feature:** [IP-001](FEATURE-LIST.md#ip-001-server-authoritative-networked-multiplayer)
  - **Tech debt:** [DT-006](TECHNICAL-DEBT-TRACKER.md#dt-006-remaining-hand-rolled-smoke-tests-not-yet-migrated-to-gut), [DT-003](TECHNICAL-DEBT-TRACKER.md#dt-003-no-interactive-gui-confirmation-of-slice-002s-visual-result), [DT-004](TECHNICAL-DEBT-TRACKER.md#dt-004-no-physical-two-machine-windowslinux-lan-run-of-slice-003)
  - **Planning ticket:** [Prediction and reconciliation](../.scratch/game-vision/issues/11-prediction-reconciliation.md)

#### Phase 6 — Windows client package

- **Slice:** [006 — Portable Windows client package](slices/006-windows-client-package.md) — **100% complete; exported and LAN-tested by user**
  - **Feature:** [F-002](FEATURE-LIST.md#f-002-portable-windows-client-package)

#### Phase 11 — Multi-peer Player replication

- **Slice:** [007 — Two-client Player replication and disconnect cleanup](slices/007-multi-peer-player-replication.md) — **100% complete; interactive GUI confirmation and physical two-machine LAN run verified by user**
  - **Feature:** [F-004](FEATURE-LIST.md#f-004-multi-peer-player-replication)
  - **Tech debt:** [DT-006](TECHNICAL-DEBT-TRACKER.md#dt-006-remaining-hand-rolled-smoke-tests-not-yet-migrated-to-gut), [DT-003](TECHNICAL-DEBT-TRACKER.md#dt-003-no-interactive-gui-confirmation-of-slice-002s-visual-result), [DT-004](TECHNICAL-DEBT-TRACKER.md#dt-004-no-physical-two-machine-windowslinux-lan-run-of-slice-003)
  - **Planning ticket:** [Multi-peer Player replication](../.scratch/game-vision/issues/13-multi-peer-player-replication.md)
  - **Planning ticket:** [Windows client package](../.scratch/game-vision/issues/12-windows-client-package.md)

#### Phase 8 — JIT world generation and local inference

- **Slice:** [008 — Async validated sector blueprint contract](slices/008-sector-blueprint-contract.md) — **100% complete; focused public-seam validation passed**
  - **Feature:** [IP-004](FEATURE-LIST.md#ip-004-structured-sector-blueprint-translation)
  - **Tech debt:** no Slice 008-specific test migration debt remains; residual [DT-006](TECHNICAL-DEBT-TRACKER.md#dt-006-remaining-hand-rolled-smoke-tests-not-yet-migrated-to-gut) covers unrelated hand-rolled scripts.
  - **Planning ticket:** [Sector blueprint contract](../.scratch/game-vision/issues/15-sector-blueprint-contract.md)

- **Slice:** [009 — Asynchronous provisional sector generation](slices/009-provisional-sector-generation.md) — **100% complete; focused and full-suite public-seam validation passed**
  - **Feature:** [IP-008](FEATURE-LIST.md#ip-008-just-in-time-sector-generation)
  - **Tech debt:** none new; residual [DT-006](TECHNICAL-DEBT-TRACKER.md#dt-006-remaining-hand-rolled-smoke-tests-not-yet-migrated-to-gut) covers unrelated hand-rolled scripts.
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
- [ ] Ready — Sector-boundary detection for IP-008 (Phase 8): trigger
  `server/provisional_sector_generator.gd` requests when an authoritative
  player position crosses into an unexplored sector, closing the remaining gap
  between Slice 009 and a fully `Implemented`
  [IP-008](FEATURE-LIST.md#ip-008-just-in-time-sector-generation).
- [ ] Ready — Canon persistence design (Phase 9): resolve the open SQLite
  schema/transaction/event-model questions in
  [game-vision issue 05](../.scratch/game-vision/issues/05-define-canon-persistence.md)
  before scoping the first slice for
  [P-011](FEATURE-LIST.md#p-011-canonical-history-archive),
  [P-012](FEATURE-LIST.md#p-012-one-time-blueprint-canonicalization), and
  [P-013](FEATURE-LIST.md#p-013-dynamic-world-mutation-tracking).
- [ ] Queued — Containerized fixed-tick server runtime (Phase 10, blocked):
  [P-014](FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)
  needs the runtime-boundary questions in
  [game-vision issue 06](../.scratch/game-vision/issues/06-define-runtime-boundaries.md)
  resolved, which is itself blocked on the canon persistence design above.
- [ ] Queued — Delivery workflow capabilities (Phase 7, no blockers, not yet
  scoped as a slice): agent-assisted delivery orchestration
  ([P-004](FEATURE-LIST.md#p-004-agent-assisted-delivery-orchestration)),
  Remote-SSH server workspace
  ([P-005](FEATURE-LIST.md#p-005-remote-ssh-server-workspace)), and
  token-efficient asset quarantine
  ([P-006](FEATURE-LIST.md#p-006-token-efficient-asset-quarantine)).
- [x] Starting Town map (Phase 8/9 handoff, pre-slice design): charting a
  JIT-generated hub sector with facade House/Smithy/Armor Shop/Inn structures
  and per-player house allocation. Delivered as slices: sector-blueprint
  schema v2 (`structures`/`spawn_points`, Slice 014), client-side geometry
  translation (Slice 015), starting town hub fixture (Slice 016), and
  server-to-client blueprint replication (Slice 017). See
  [starting-town map](../.scratch/starting-town/map.md).
- [ ] In progress — Basic Monsters map (Phase 10 handoff, pre-slice design):
  charting a minimal server-authoritative monster (flat HP/damage/death,
  detect/chase/attack state machine with a readable attack telegraph per
  `CLAUDE.md`'s Combat Reading rules), spawned from the Starting Town map's
  spawn points. No decisions recorded yet; cross-map blocked on the Starting
  Town map's spawn-point schema. See
  [basic-monsters map](../.scratch/basic-monsters/map.md). Not yet a slice.
- [ ] Ready — Public game access via WireGuard (Phase 13, design-complete,
  not yet scoped as a slice): all six
  [wan-wireguard map](../.scratch/wan-wireguard/map.md) tickets are resolved
  (netstack bridging, GDExtension prototype, OPNsense infra automation,
  enrollment invite service, host firewall lockdown, and revocation/ban
  lifecycle) under SDD-GAME-WG-001, but no implementation slice exists yet for
  [P-024](FEATURE-LIST.md#p-024-public-game-access-via-opnsense-native-wireguard).