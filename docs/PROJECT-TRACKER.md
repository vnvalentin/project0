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

1. **Close Phase 12 runtime hardening and action-input evidence.** The container
  cutover, fixed tick, assertion-only game boundary, deployment path, and
  rollback tooling are delivered. Remaining work is production mutation-path
  evidence, the independent login image (DT-012), and bounded expansion of
  IP-015 beyond the first melee seam. No client-authored outcomes are allowed.
2. **Close Phase 13 workflow fillers only as they become real needs.** P-005
  Remote-SSH and P-006 asset quarantine remain intentionally planned; they are
  not blockers for the game runtime or Phase 14.
3. **Implement Phase 14 next.** F-036 is `Ready`, Slice 116 is a records-first
  handoff, and the six NPC decision tickets are unclaimed implementation
  work. Build the shared Character boundary first: fixed humanoid baseline,
  organic development, techniques, equipment, movement, combat/status,
  disposition, and role-based spawning.
4. **Follow with Phase 15 progression.** P-016 owns the six-node vessel's
  kinetic/friction, Meridian, Burnout, and magic-equilibrium layers. It must
  consume the Phase 14 Character seam rather than reopen NPC foundations.
5. **Keep Phase 16 as a design track until its contracts converge.** The
  launcher, auto-update, and controller maps are not implementation-ready:
  version identity, patch trust/rollback, LAN/WAN behavior, controller scope,
  and offline/repair telemetry still need decisions. Treat launcher and
  auto-update as one client-delivery contract, with controller input as a
  separate low-risk slice under the same phase.
6. **Keep Phase 17 planning-only.** The operator console has a resolved
  transport/auth research basis but its telemetry, registry, control seam,
  surface, and capstone handoff remain open. Do not allocate implementation
  slices until the capstone spec is resolved.
7. **Keep Phase 18 research-first.** `zone-sharding` has no `map.md` and only
  one open issue. Produce the ownership/handoff model and ADR before adding
  features or slices.

**Renumber note (2026-09-16):** phases were reordered into a clean forward
sequence during a trajectory reassessment. Previous → current: 11→7, 14→10,
13→11, 10→12, 7→13, 12→15; new phases 14 and 16–18 were added. The renumber
updated live records and slice "Tracker context" stamps; dated change-history
prose and ADRs keep their original numbers as append-only history.

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

Phases are numbered in clean forward-delivery order. Numbers 0–13 are complete
or in-progress work; 14–18 are the forward roadmap sourced from the current
`.scratch/<goal>/` maps. (This sequence was renumbered on 2026-09-16 during a
trajectory reassessment; earlier records referred to some of these phases by
their previous numbers — see the change note under "Delivery order".)

| Phase | Status | Exit gate |
| --- | --- | --- |
| 0. Foundation and contracts | done | Foundation records completed, cross-linked, and validated; gate marker removed. |
| 1. First playable vertical slice | done | A player can pass a local identity gate, enter a scene with a flat plane, and move a Player around it, validated by headless Godot checks. |
| 2. Network connection proof | done | A headless Godot server accepts one ENet client and the client visibly represents the connected Player on the existing flat plane, with no movement synchronization or persistence required yet. |
| 3. LAN client connection | done | A Windows Godot client can target the Linux server's configured LAN address while localhost remains the default for automated checks; no gameplay synchronization or internet exposure is included. |
| 4. Authoritative movement proof | done | One connected client sends WASD intent, the server owns and updates that Player position, and the client displays the returned authoritative position without prediction or interpolation. |
| 5. Prediction and reconciliation proof | done | The client responds immediately to local input, acknowledges ordered server snapshots, reconciles prediction drift, and smoothly renders authoritative movement without remote-player replication or persistence. |
| 6. Windows client package | done | A reproducible portable Windows 64-bit package launches the current client without the Godot editor, source share, or server-only files and can be configured to connect to the Linux server. |
| 7. Multi-peer Player replication | done | Two clients connect to one server, see distinct Players, observe each other's authoritative movement, and clean up a disconnected Player. |
| 8. JIT world generation and local inference | done | The server requests non-blocking sector generation, validates local Ollama JSON blueprints, and exposes bounded failures without interrupting the multiplayer loop. |
| 9. Canon persistence and world mutation | done | Validated sectors and authorized player mutations are durable, uniquely identified, and recovered consistently from SQLite. |
| 10. Player accounts and characters | done | A person registers or logs in over the WireGuard tunnel, manages up to five durable Characters across restarts, and enters the world as the selected Character — all server-authoritative and fail-closed. |
| 11. Public game access | done | A new remote player can safely self-register, authenticate, select a Character, provision a least-privilege WireGuard peer, and enter the authoritative server from a real WAN Windows client; public-route abuse controls are validated, and no VPS, client OS admin rights, or LAN exposure is required. |
| 12. Authoritative runtime and action input | in-progress | Production deployment mutation and rollback evidence are recorded, login and game images have an explicit release boundary, and the server resolves a bounded action set authoritatively beyond the first melee seam. |
| 13. Delivery workflow capabilities | in-progress | Agent orchestration and CI/dashboard foundations remain synchronized; Remote-SSH and asset quarantine are either delivered with evidence or explicitly retained as planned non-blockers. |
| 14. NPC generalization and shared Character | done | F-036's shared Character seam is implemented and validated for Player/NPC state, fixed baseline, organic development, techniques, equipment, movement, combat/status, disposition, relevance, and role-based spawning without duplicating Monster logic. **Exit gate met (Slice 131):** the seam is live in the running server for the Player, the combat Monster, and the town NPCs (route-consistent activity movement + anchored population), validated by 632/632 GUT tests incl. the socket E2E harnesses. |
| 15. Biological progression and kinetic systems | done | Phase 15 layers kinetic/friction effects, Meridians, Burnout, and magic equilibrium onto the validated Phase 14 Character/progression seam while preserving hidden state and server authority. **Exit gate met (Slice 140):** the versioned tuning + vessel redistribution + effective-snapshot foundation (P-016-A) and all five subsystems (P-016-B…F) are composed by a server-authoritative `EmbodimentProgressionService` into a deterministic, presentation-safe snapshot, proven end-to-end by 503/503 GUT tests. |
| 16. Client delivery experience | in-progress | Design converged in the Phase 16 handoff spec and ADR: explicit LAN/WAN launcher modes, mandatory pre-auth version gating, RSA-signed manifest and full-pack trust, atomic restart/rollback, repair behavior, onboarding, and a separate XInput named-action controller slice. Implementation started — the client build version identity is delivered (Slice 144); the gate, signed patching, updater, launcher, and controller slices remain. |
| 17. Fleet operations console | queued (design) | A capstone spec resolves the versioned ops snapshot, telemetry content, registry, operator-token control seam, bounded actions, audit, and standalone LAN console surface before implementation slices are allocated. |
| 18. Horizontal scale and zone sharding | queued (research-first) | A researched ownership and cross-shard handoff model plus ADR exists before any implementation feature or slice is created; until then this phase has no validated exit gate. |

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

- Features: `done` [IP-001](FEATURE-LIST.md#ip-001-server-authoritative-networked-multiplayer) — the connection proof, authoritative movement, prediction/reconciliation, and multi-peer replication are live and validated across their completed phases.
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

**Phase 7 — Multi-peer Player replication**

Progress: **100%** (1 of 1 items done)

- Features: `done` [F-004](FEATURE-LIST.md#f-004-multi-peer-player-replication) — two-client authoritative Player replication; Slice 007 implements and validates two-peer replication and disconnect cleanup, verified by user in interactive GUI and physical LAN runs.
- Tech debt: `done` [DT-003](TECHNICAL-DEBT-TRACKER.md#dt-003-no-interactive-gui-confirmation-of-slice-002s-visual-result), [DT-004](TECHNICAL-DEBT-TRACKER.md#dt-004-no-physical-two-machine-windowslinux-lan-run-of-slice-003) — interactive GUI and physical LAN runs verified by user.

- **Current slice:** [086 — Multi-peer Character replication](slices/086-multipeer-character-replication.md) — **delivered; remote Players are labeled with their bound Character's display name (server broadcasts identity at world entry; late-joiners are seeded); GUT 401/401 + login-handoff e2e ALL PASS on Linux. Closes the Phase 10 multi-peer Character replication follow-up. Live two-client GUI confirmation is a manual follow-up.**
  - **Feature:** [F-004](FEATURE-LIST.md#f-004-multi-peer-player-replication)

**Phase 13 — Delivery workflow capabilities**

Progress: **75%** (6 of 8 items done)

- Features: `done` [F-005](FEATURE-LIST.md#f-005-automated-validation-gate-and-test-telemetry), [F-007](FEATURE-LIST.md#f-007-living-architecture-anchor), [F-025](FEATURE-LIST.md#f-025-project-flow-visual-management-dashboard), [P-004](FEATURE-LIST.md#p-004-agent-assisted-delivery-orchestration), [F-038](FEATURE-LIST.md#f-038-cross-cutting-telemetry-pipeline-envelope-transport-storage-dashboard); `queued` [P-005](FEATURE-LIST.md#p-005-remote-ssh-server-workspace), [P-006](FEATURE-LIST.md#p-006-token-efficient-asset-quarantine).
- Tech debt: `done` [DT-007](TECHNICAL-DEBT-TRACKER.md#dt-007-lan-config-tests-spawned-a-real-server-on-the-fixed-default-port-9999-non-hermetic) — resolved with a validated `--server-port` override, ephemeral-port tests, and a reimport-first validation gate.

- **Current slice:** [178 — Reality page phase bars use real Outcome-label completion](slices/178-reality-page-outcome-percentages.md) — **delivered; `/` now sources active-phase completion from `phase_milestones()`, the same data `/detail` uses, instead of an independently-computed tracker-text percentage**
  - **Feature:** [F-025](FEATURE-LIST.md#f-025-project-flow-visual-management-dashboard)
  - **GitHub issue:** #374

- Prior slice: [177 — Dashboard per-slice Goal alignment (real data, not phase-level)](slices/177-dashboard-per-slice-goal-alignment.md) — **delivered; each slice row now shows its own resolved Goal via its linked issue's `Parent goal: #N`, not its phase's full goal list; 23 slices resolved real Goals, rest correctly show no linked goal**
  - **Feature:** [F-025](FEATURE-LIST.md#f-025-project-flow-visual-management-dashboard)
  - **GitHub issue:** #374

- Prior slice: [176 — Dashboard Phase/Outcome/Slice/Goal roadmap rebuild](slices/176-dashboard-phase-outcome-roadmap.md) — **delivered; `/detail` rebuilt around live GitHub Phase-milestone/Outcome-label data per issues #374-#380; retired `.scratch` goal maps, the old traceability summary, phase/slice tables, and the standalone milestone section**
  - **Feature:** [F-025](FEATURE-LIST.md#f-025-project-flow-visual-management-dashboard)
  - **GitHub issue:** #374

- Prior slice: [165 — Dashboard telemetry page](slices/165-dashboard-telemetry-page.md) — **delivered; /telemetry page live, manual e2e HTTP check confirmed counters + filter, record-sync 0 errors — closes out the telemetry pipeline route**
  - **Feature:** [F-038](FEATURE-LIST.md#f-038-cross-cutting-telemetry-pipeline-envelope-transport-storage-dashboard)
  - **GitHub issue:** #353

- Prior slice: [164 — Combat-outcome telemetry emission](slices/164-combat-outcome-telemetry.md) — **delivered; 6-event family live in server_main.gd, 111 scripts/811/811 tests on Linux, record-sync 0 errors, manual dump confirmed correct combat rows**
  - **Feature:** [F-038](FEATURE-LIST.md#f-038-cross-cutting-telemetry-pipeline-envelope-transport-storage-dashboard)
  - **GitHub issue:** #351

- Prior slice: [163 — Connection-lifecycle telemetry emission](slices/163-connection-lifecycle-telemetry.md) — **delivered; 6-event family live in server_main.gd, 111 scripts/811/811 tests on Linux, record-sync 0 errors, manual e2e confirmed 4 rows land correctly**
  - **Feature:** [F-038](FEATURE-LIST.md#f-038-cross-cutting-telemetry-pipeline-envelope-transport-storage-dashboard)
  - **GitHub issue:** #347

- Prior slice: [162 — Live telemetry RPC wiring](slices/162-telemetry-rpc-wiring.md) — **delivered; live RPC + boot-wired sink/limiter + ingest service, 111 scripts/811/811 tests on Linux, record-sync 0 errors**
  - **Feature:** [F-038](FEATURE-LIST.md#f-038-cross-cutting-telemetry-pipeline-envelope-transport-storage-dashboard)
  - **GitHub issue:** #345

- Prior slice: [161 — Telemetry transport contracts](slices/161-telemetry-transport-contracts.md) — **delivered; client batch queue + server rate limiter, 14/14 focused tests on Windows, full suite 805/805 on Linux, record-sync 0 errors**
  - **Feature:** [F-038](FEATURE-LIST.md#f-038-cross-cutting-telemetry-pipeline-envelope-transport-storage-dashboard)
  - **GitHub issue:** #334

- Prior slice: [160 — Telemetry sink + dedicated database](slices/160-telemetry-sink-database.md) — **delivered; server/telemetry_sink.gd schema+emit+retention, 108 scripts/791/791 tests on Linux, record-sync 0 errors**
  - **Feature:** [F-038](FEATURE-LIST.md#f-038-cross-cutting-telemetry-pipeline-envelope-transport-storage-dashboard)
  - **GitHub issue:** #332

- Prior slice: [159 — Telemetry envelope + validation](slices/159-telemetry-envelope-validation.md) — **delivered; shared/telemetry_event.gd build/validate, 11/11 focused tests, full suite 785/785, record-sync 0 errors**
  - **Feature:** [F-038](FEATURE-LIST.md#f-038-cross-cutting-telemetry-pipeline-envelope-transport-storage-dashboard)
  - **GitHub issue:** #329

- Prior slice: [104 — Registry-driven all-server deployment](slices/104-registry-driven-deploy.md) — **delivered; dry-run resolved all five services and live health on okami, mutating path not yet exercised**
  - **Feature:** [P-014](FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)

- Prior slice: [103 — Linux-hosted Windows client package build](slices/103-linux-client-package-build.md) — **delivered; full cross-build executed on okami, artifacts and manifest verified**
  - **Feature:** [F-002](FEATURE-LIST.md#f-002-portable-windows-client-package)

- Prior slice: [102 — Full-stack CI validation gate](slices/102-ci-validation-pipeline.md) — **delivered; all five CI jobs green on PR #80**
  - **Feature:** [F-005](FEATURE-LIST.md#f-005-automated-validation-gate-and-test-telemetry)

- Prior slice: [094 — Reality dashboard truthfulness and delivery-record reconciliation](slices/094-reality-dashboard-truthfulness.md) — **delivered; focused parser validation and record-sync validation passed**
  - **Feature:** [P-004](FEATURE-LIST.md#p-004-agent-assisted-delivery-orchestration)

- Prior slice: [027 — Agent-assisted delivery orchestration](slices/027-agent-assisted-delivery-orchestration.md) — **100% complete; documentation checks and full-suite validation passed**
  - **Feature:** [P-004](FEATURE-LIST.md#p-004-agent-assisted-delivery-orchestration)

- **Also delivered:** [094 — Reality dashboard truthfulness and delivery-record reconciliation](slices/094-reality-dashboard-truthfulness.md) — **feature count deduplication, delivered-slice recognition, item-weighted overall completion, commit provenance, and stale Phase 1/8 status reconciliation**
  - **Feature:** [F-025](FEATURE-LIST.md#f-025-project-flow-visual-management-dashboard)

- **Also delivered:** [111 — Dashboard issue traceability detail](slices/111-dashboard-issue-traceability-detail.md) — **detail screen now foregrounds GitHub traceability: 110/110 slice records linked, 15/15 parent goal issues, 95/95 child planning issues, and `zone-sharding` shown as new/unresearched instead of omitted; stale hardcoded delivery-roadmap block removed from `/detail`**
  - **Feature:** [F-025](FEATURE-LIST.md#f-025-project-flow-visual-management-dashboard)
  - **GitHub issue:** #206

- **Also delivered:** [112 — Reality page Goal source of truth](slices/112-reality-goal-source-of-truth.md) — **Reality page GitHub Source of Truth now renders only parent Goal issues and shows each goal's percent complete from closed child issues over total child issues; non-goal workflow issues and child planning issues are hidden from that section**
  - **Feature:** [F-025](FEATURE-LIST.md#f-025-project-flow-visual-management-dashboard)
  - **GitHub issue:** #207

- **Also delivered:** [113 — Dashboard apps source layout](slices/113-dashboard-apps-source-layout.md) — **dashboard container now standardizes on `/apps/project0/dashboard` as the compose app directory and `/apps/project0/dashboard/repo` as the dedicated read-only repo clone, replacing the stale `/data/code/project0` mirror path**
  - **Feature:** [F-025](FEATURE-LIST.md#f-025-project-flow-visual-management-dashboard)
  - **GitHub issue:** #211

- **Also delivered:** [114 — Goal target coverage cards](slices/114-goal-target-coverage-cards.md) — **Reality page Goal cards now show target-condition coverage from resolved child planning issue status, while preserving separate GitHub open/closed child issue counts**
  - **Feature:** [F-025](FEATURE-LIST.md#f-025-project-flow-visual-management-dashboard)
  - **GitHub issue:** #214

- **Also delivered:** [115 — Goal What Good Looks Like criteria](slices/115-goal-good-looks-like-criteria.md) — **Goal completion now depends on explicit customer-outcome `What Good Looks Like` criteria in the parent Goal, not merely on the current child issues; existing researched maps and mirrored GitHub Goal issues now carry WGL checklists**
  - **Features:** [F-025](FEATURE-LIST.md#f-025-project-flow-visual-management-dashboard), [P-004](FEATURE-LIST.md#p-004-agent-assisted-delivery-orchestration)
  - **GitHub issue:** #215

**Phase 8 — JIT world generation and local inference**

Progress: **100%** (11 of 11 items done)

- Features: `done` [IP-008](FEATURE-LIST.md#ip-008-just-in-time-sector-generation), `done` [P-009](FEATURE-LIST.md#p-009-hardware-accelerated-local-inference), `done` [F-017](FEATURE-LIST.md#f-017-sector-blueprint-schema-v2-structures-and-spawn-points), `done` [IP-004](FEATURE-LIST.md#ip-004-structured-sector-blueprint-translation), `done` [F-018](FEATURE-LIST.md#f-018-client-side-sector-geometry-translation), `done` [F-019](FEATURE-LIST.md#f-019-starting-town-hub-fixture), `done` [F-020](FEATURE-LIST.md#f-020-server-to-client-sector-blueprint-replication), `done` [F-021](FEATURE-LIST.md#f-021-facade-enter-exit-proximity-labels), `done` [F-022](FEATURE-LIST.md#f-022-player-house-allocation), `done` [F-026](FEATURE-LIST.md#f-026-organic-districted-starting-city) (Organic Village; supersedes F-019), `done` [F-028](FEATURE-LIST.md#f-028-imperial-world-scale-measurement-contract) (cross-cutting scale contract).
- Tech debt: `done` [DT-008](TECHNICAL-DEBT-TRACKER.md#dt-008-per-tile-staticbody3d-geometry-did-not-scale-to-city-size) — resolved by the Slice 024 geometry pass (merged `ArrayMesh` ground + one merged `Walls` body), decoupling town size from the physics body count.

- **Current slice:** [053 — F-026 derive monster exclusion from town bounds](slices/053-f026-monster-exclusion-from-town-bounds.md) — **100% complete; focused, parse, full-suite, record-sync, and runtime boot validation passed**
  - **Feature:** [F-026](FEATURE-LIST.md#f-026-organic-districted-starting-city) (final item delivered; feature now `Implemented`)

**Phase 9 — Canon persistence and world mutation**

Progress: **100%** (4 of 4 items done)

- Features: `done` [F-029](FEATURE-LIST.md#f-029-shared-server-owned-sqlite-persistence-foundation) (cross-cutting persistence-engine foundation, shared with Phase 10), `done` [P-011](FEATURE-LIST.md#p-011-canonical-history-archive), `done` [P-012](FEATURE-LIST.md#p-012-one-time-blueprint-canonicalization), `done` [P-013](FEATURE-LIST.md#p-013-dynamic-world-mutation-tracking).
- Tech debt: none yet.

- **Current slice:** [098 — Canon sector mutation replay: server replicates the effective blueprint](slices/098-canon-sector-mutation-replay.md) — **delivered; the server replays a sector's mutation log (`shared/canon_sector_resolver.gd`) and replicates the effective blueprint (destroyed structures removed) so a loaded sector reflects durable changes**
  - **Feature:** [P-013](FEATURE-LIST.md#p-013-dynamic-world-mutation-tracking) (fifth slice, completes the code path)
  - Prior: [097 — Canon mutation intent RPC transport](slices/097-canon-mutation-rpc-transport.md); [096 — intent DTO + resolution service](slices/096-canon-mutation-intent-service.md)

**Phase 12 — Authoritative runtime and action input**

Progress: **50%** (3 of 6 items done)

- Features: `in-progress` [P-014](FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime) — runtime foundations delivered; production-cutover evidence remains; `in-progress` [IP-015](FEATURE-LIST.md#ip-015-authoritative-action-input) — the server now resolves a bounded action set beyond the first melee seam (Heavy Strike, Slice 141); client input binding, damage differentiation, and PvP remain; `in-progress` [F-039](FEATURE-LIST.md#f-039-nakama-v1-entry-and-realtime-foundation) — Nakama v1 entry/realtime foundation starts with the deployment foundation; `done` [IP-023](FEATURE-LIST.md#ip-023-basic-monster-combat), `done` [F-027](FEATURE-LIST.md#f-027-server-authoritative-movement-collision), `done` [P-016](FEATURE-LIST.md#p-016-biological-progression-and-kinetic-combat-systems) (cross-cutting contract; Implemented in Phase 15).
- Tech debt: `open` [DT-012](TECHNICAL-DEBT-TRACKER.md#dt-012-login-authority-shares-the-game-servers-image-and-codebase) — login authority shares the game server's image and codebase; `done` [DT-013](TECHNICAL-DEBT-TRACKER.md#dt-013-advertised-tick_rate-does-not-match-the-actual-authoritative-tick-rate) — engine now runs at the advertised rate (Slice 107); `done` [DT-014](TECHNICAL-DEBT-TRACKER.md#dt-014-container-images-ship-without-the-wgnetstack-gdextension) — the Linux GDExtension now ships in the server image (Slice 110).

- **Current slice:** [141 — Phase 12 (IP-015): second authoritative action kind — Heavy Strike](slices/141-heavy-strike-action.md) — **delivered; a second action kind (`HEAVY_STRIKE`) with its own data-driven archetype (slower/wider/longer-reach, multi-target) routed through the existing action machine + reach/arc test — the server now resolves a bounded action set beyond the first melee seam; new `test_heavy_strike_action` 7/7, melee regression `test_melee_combat_contracts` 21/21 + integration `test_authoritative_melee_strike` 9/9 unchanged; full cumulative tree 712/712 across 97/97, exit 0 on the Linux host**
  - **Feature:** [P-014](FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)
  - **Tech debt:** resolves [DT-013](TECHNICAL-DEBT-TRACKER.md#dt-013-advertised-tick_rate-does-not-match-the-actual-authoritative-tick-rate)

- **Current slice:** [175 — Nakama Character and world-entry client path](slices/175-nakama-character-world-entry.md) — **delivered; presents the Nakama bearer session for server validation, then reuses existing Character CRUD and world-entry RPC seams; okami validation passed 117 scripts / 849 tests / 2645 asserts**
  - **Feature:** [F-039](FEATURE-LIST.md#f-039-nakama-v1-entry-and-realtime-foundation)
  - **GitHub issue:** #371

- **Current slice:** [166 — Nakama v1 deployment foundation](slices/166-nakama-v1-deployment-foundation.md) — **delivered; adds the opt-in single-node Nakama/PostgreSQL compose profile, private Console/admin posture, host-side secrets/config runbook, backup-before-migration rule, and static validation seam; Linux validation passed record-sync 0 errors and full GUT 811/811**
  - **Feature:** [F-039](FEATURE-LIST.md#f-039-nakama-v1-entry-and-realtime-foundation)
  - **GitHub issue:** #355

- **Current slice:** [167 — Nakama Godot auth and session entry](slices/167-nakama-godot-auth-session-entry.md) — **delivered; adds the feature-flagged Godot Nakama HTTP auth/session seam, account-gate login/register path, NetworkConfig endpoint/key controls, and in-memory Nakama Account identity state; Linux record-sync 0 errors and full GUT 826/826 tests passed**
  - **Feature:** [F-039](FEATURE-LIST.md#f-039-nakama-v1-entry-and-realtime-foundation)
  - **GitHub issue:** #356

- **Current slice:** [168 — Project0 Character service keyed by Nakama user ID](slices/168-nakama-character-service.md) — **delivered; adds idempotent Nakama-user-id Account materialization with non-login PBKDF sentinels plus CharacterService Nakama session binding while preserving Project0-owned Character rules; okami validation passed 831 tests / 2585 asserts**
  - **Feature:** [F-039](FEATURE-LIST.md#f-039-nakama-v1-entry-and-realtime-foundation)
  - **GitHub issue:** #357

- **Current slice:** [169 — Project0 world-entry ticket contract for Nakama sessions](slices/169-nakama-world-entry-ticket.md) — **delivered; adds the server-only selected-Character world-entry ticket issue/consume contract for Nakama-bound sessions with replay, expiry, wrong-audience, and invalidation coverage; okami validation passed 114 scripts / 836 tests / 2617 asserts**
  - **Feature:** [F-039](FEATURE-LIST.md#f-039-nakama-v1-entry-and-realtime-foundation)
  - **GitHub issue:** #358

- **Current slice:** [170 — Nakama socket gameplay bridge protocol contract](slices/170-nakama-gameplay-bridge-protocol.md) — **delivered; adds transport-neutral identity-bound input/state/presence/error envelopes before live Nakama socket wiring; okami validation passed 115 scripts / 841 tests / 2633 asserts**
  - **Feature:** [F-039](FEATURE-LIST.md#f-039-nakama-v1-entry-and-realtime-foundation)
  - **GitHub issue:** #359

- **Current slice:** [171 — Default shared playtest world routing and presence](slices/171-nakama-shared-world-routing.md) — **delivered; adds one shared-world route and server-authored presence snapshots over the existing reliable RPC seam; okami validation passed 844 tests / 2633 asserts**
  - **Feature:** [F-039](FEATURE-LIST.md#f-039-nakama-v1-entry-and-realtime-foundation)
  - **GitHub issue:** #360

- **Current slice:** [172 — Nakama v1 smoke and operations gate](slices/172-nakama-v1-smoke-ops-gate.md) — **delivered; adds manifest-backed static deployment validation and explicit bounded live Nakama health/API probing; okami validation passed 116 scripts / 844 tests / 2633 asserts**
  - **Feature:** [F-039](FEATURE-LIST.md#f-039-nakama-v1-entry-and-realtime-foundation)
  - **GitHub issue:** #361

- **Current slice:** [173 — Server-side Nakama session validation seam](slices/173-nakama-session-validation.md) — **delivered; validates Nakama sessions server-side before binding identity into Project0 Character/session authority; okami validation passed 117 scripts / 849 tests / 2645 asserts**
  - **Feature:** [F-039](FEATURE-LIST.md#f-039-nakama-v1-entry-and-realtime-foundation)
  - **GitHub issue:** #381

- **Current slice:** [085 — Remove in-process login from the game server](slices/085-remove-game-in-process-login.md) — **delivered; the game process now builds an assertion-only login graph with NO AuthService (no register/login/PBKDF2) via LoginRuntime.build_assertion_only_services; LoginGateway depends on a SessionRegistry directly with AuthService optional (additive constructor arg, so the login process and existing tests are unchanged); server_main drops the PROJECT0_GAME_ASSERTION_ONLY opt-out and routes disconnect through the gateway; proven on Linux — GUT 58/58, boot logs "assertion-only game server", login handoff e2e ALL PASS (world entry "Handoff Hero") with the game holding no AuthService**
  - **Feature:** [P-014](FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)
- **Current tooling slice:** [110 — Ship the Linux wgnetstack GDExtension in the server image](slices/110-ship-wgnetstack-extension.md) — **delivered; a cached image stage builds the extension and copies it in before the import cache is baked. Boot-log occurrences of `GDExtension dynamic library not found` / `Error loading extension` went from four at every boot to **0**, so a real startup failure is now visible. Resolves DT-014**
  - **Feature:** [P-014](FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)
  - **Tech debt:** resolves [DT-014](TECHNICAL-DEBT-TRACKER.md#dt-014-container-images-ship-without-the-wgnetstack-gdextension)
  - **GitHub issue:** #92
- Prior tooling slice: [109 — Host-assumption sweep and post-deploy smoke checks](slices/109-host-assumption-sweep.md) — **delivered; audited every hardcoded loopback and host path against the container topology, corrected the last wrong value at source, and added smoke checks that exercise cross-boundary calls. Proven in both directions: passes on the fixed stack (`HTTP 401`), and after deliberately reintroducing the Slice 106 defect it produced `FAIL ... expected 401, got 502` and rolled back — the exact failure that reached the user as a malformed client response**
  - **Feature:** [P-014](FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)
- Prior tooling slice: [108 — Retire the git-archive deploy path](slices/108-retire-archive-deploy.md) — **delivered; deleted `deploy_all.sh`, `deploy_server.ps1`, and `services.json`, repointed the rehearsal workflow, and dropped the dead `-DeployServer` stage. Both previously untested deploy failure paths were exercised on the live stack: a missing tag failed with `nothing was changed` and left all services healthy, and an injected health failure produced `ROLLBACK: redeploying previous tag v0.1.1`. Known limitation recorded: rollback reverts the image tag, not the compose file**
  - **Feature:** [P-014](FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)
- Prior tooling slice: [106 — Container runtime cutover](slices/106-container-runtime-cutover.md) — **delivered; the game, login, and enrollment services now run as containers from GHCR images on okami. Runtime evidence, not just container state: game server `server_tick: 11100` at `tick_rate: 30`, login `server_tick: 11130`, enrollment `/healthz` HTTP 200, and `ss -lnup` showing the containers bound to 192.168.1.254:9999 and :9998. Systemd units stopped and disabled. Data volumes started empty by explicit user decision**
  - **Feature:** [P-014](FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)
  - **Tech debt:** [DT-012](TECHNICAL-DEBT-TRACKER.md#dt-012-login-authority-shares-the-game-servers-image-and-codebase) still `open` — login runs in its own container but still from the game server's image
- Prior tooling slice: [105 — Container images for every service, published to GHCR](slices/105-container-images-and-registry.md) — **delivered; all three images publish to GHCR as public packages, and both Python targets return HTTP 200 on `/healthz` from one shared image**
  - **Feature:** [P-014](FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime), [F-002](FEATURE-LIST.md#f-002-portable-windows-client-package)
  - **Tech debt:** [DT-012](TECHNICAL-DEBT-TRACKER.md#dt-012-login-authority-shares-the-game-servers-image-and-codebase) raised — login authority shares the game server's image and codebase; split deferred with client-update ownership as the trigger
- Prior tooling slice: [104 — Registry-driven all-server deployment](slices/104-registry-driven-deploy.md) — **delivered; dry-run resolved all five registered services and evaluated live health on okami, exit 0. The mutating path (backup, replace, restart, health gate, rollback) is NOT yet exercised against production and needs a tag deploy in a maintenance window**
  - **Feature:** [P-014](FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)
- Prior tooling slice: [101 — Server deployment path in the current deployment pipeline](slices/101-server-deployment-pipeline.md) — **delivered; PowerShell parser checks passed and the dirty-worktree guard stopped deployment before SSH**
  - **Feature:** [P-014](FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)

**Phase 15 — Biological progression and kinetic systems**

Progress: **done** (P-016 Implemented; exit gate met at Slice 140)

- Features: `Implemented` [P-016](FEATURE-LIST.md#p-016-biological-progression-and-kinetic-combat-systems).
- Current slice: [143 — Phase 15 follow-on (P-016): durable vessel persistence](slices/143-vessel-persistence.md) — **delivered; the second and last Slice 140 follow-on. `VesselProgressionState.to_wire_dict()` + server-only `server/vessel_repository.gd` (`VesselRepository`) over the shared `SqliteStore` seam (mirroring `CanonRepository`): `ensure_schema`, idempotent `save_vessel` upsert by `character_id`, and `load_vessel` revalidated fail-closed against the current tuning. A Character's earned vessel now survives a server restart; new `test_vessel_repository` 6/6 over a real `user://` SQLite db; full GUT suite 729/729 across 100/100, exit 0 on the Linux host**. Prior: [Slice 142](slices/142-effective-mechanics-replication.md) (mechanics replication), [Slice 140](slices/140-phase15-embodiment-progression-service.md) closed the exit gate. Live save-on-train/load-on-entry wiring remains (gated on the shared-vs-per-Player service-ownership decision).
- Tech debt: none.

**Phase 11 — Public game access**

Progress: **100%** (3 of 3 items done)

- Features: `done` [P-024](FEATURE-LIST.md#p-024-public-game-access-via-opnsense-native-wireguard) — the tunnel, Windows package, enrollment service, HTTPS login/character flow, assertion-gated peer provisioning, client/launcher seams, and real off-LAN Windows validation are delivered.
- Tech debt: `done` [DT-009](TECHNICAL-DEBT-TRACKER.md#dt-009-public-login-on-the-enrollment-service-has-no-rate-limiting-lockout-or-anti-enumeration), `done` [DT-010](TECHNICAL-DEBT-TRACKER.md#dt-010-no-public-https-account-registration-surface-for-the-wan-client).
- **Latest delivered validation:** [054 — Secure Windows tunnel enrollment and credential storage](slices/054-secure-windows-tunnel-enrollment.md) — all six real-WAN checks user-confirmed passed on 2026-09-16.
- **Deferred improvement:** automatic trusted device enrollment/approval may replace manual invite copying in a future F-035 follow-up; the manual single-use invite remains the secure fallback.
- Prior slice: [091 — Auth-gated onboarding C-client-seam: Godot `EnrollmentHttpClient`](slices/091-client-https-auth-character-seam.md) — **delivered; GUT 432/432 across 63/63 scripts, exit 0**
  - **Feature:** [P-024](FEATURE-LIST.md#p-024-public-game-access-via-opnsense-native-wireguard)
- Prior slice: [089 — Auth-gated onboarding B: `/redeem` signed-assertion + idempotent per-account peer lifecycle](slices/089-auth-gated-onboarding-peer-provisioning.md) — **delivered; GUT 420/420, enrollment pytest 96/96 on the Linux host**
  - **Feature:** [P-024](FEATURE-LIST.md#p-024-public-game-access-via-opnsense-native-wireguard)
- Prior slice: [088 — Auth-gated onboarding A: HTTPS /login delegation](slices/088-auth-gated-onboarding-login-delegation.md) — **delivered; validated on the Linux host (server/login_loopback_http_endpoint.gd, shared/network_config.gd's resolve_login_http_port(), infra/enrollment's POST /login + LoginAuthorityClient); GUT 415/415 across 62/62 scripts (1511 asserts), exit 0; enrollment pytest 70/70, exit 0 (also reproduced on Windows)**
  - **Feature:** [P-024](FEATURE-LIST.md#p-024-public-game-access-via-opnsense-native-wireguard)
- Final validation: [054 — Secure Windows tunnel enrollment and credential storage](slices/054-secure-windows-tunnel-enrollment.md) — **delivered; all six real-WAN Windows checks passed on 2026-09-16**

**Phase 10 — Player accounts and characters**

Progress: **100%** (6 of 6 items done)

- Design complete: the player-accounts map and its six tickets are resolved and the handoff-ready spec is [spec.md](../.scratch/player-accounts/spec.md); `CONTEXT.md` now carries Account and Character as canonical terms. All six Phase 10 delivery items are now implemented and validated, including the Windows GUI login/Character/world lifecycle in Slice 044. Multi-peer Character replication is now delivered ([Slice 086](slices/086-multipeer-character-replication.md), under Phase 7/F-004); in-world return to Character Select without re-login is delivered ([Slice 087](slices/087-login-session-resume.md)); the mandatory-auth hard-flip remains a queued follow-up.
- Features: `done` [F-029](FEATURE-LIST.md#f-029-shared-server-owned-sqlite-persistence-foundation), `done` [F-030](FEATURE-LIST.md#f-030-accounts-and-characters-persistence-repository), `done` [F-031](FEATURE-LIST.md#f-031-account-authentication-and-session-server), `done` [F-032](FEATURE-LIST.md#f-032-character-crud-over-the-wire-server), `done` [F-033](FEATURE-LIST.md#f-033-character-world-entry-server-binding), `done` [F-034](FEATURE-LIST.md#f-034-client-login-and-character-selection-screens).
- Tech debt: none yet.

- **Current slice:** [087 — Login-session resume (in-world Character Select without re-login)](slices/087-login-session-resume.md) — **delivered; the handoff fetches a bounded account resume token (server TTL, default 1h) and the in-world Character Select button re-establishes a login session from it to return to the roster, falling back to the login screen on expiry; GUT 407/407 + login-handoff e2e ALL PASS on Linux; Windows GUI confirmed**
  - **Features:** [F-033](FEATURE-LIST.md#f-033-character-world-entry-server-binding), [F-034](FEATURE-LIST.md#f-034-client-login-and-character-selection-screens)

**Phase 14 — NPC generalization and shared Character**

Progress: **0%** (0 of 1 items done; design charted, implementation not started)

- Source goal: [npcs map](../.scratch/npcs/map.md) — generalizes the resolved
  [basic-monsters](../.scratch/basic-monsters/map.md) work and reopens its
  "a monster is always aggressive" assumption.
- Scope: unified Character state for Player and NPC, fixed humanoid player
  baseline, uncapped organic development, multidimensional techniques,
  equipment, activity-driven movement, shared combat/status, and role-based NPC
  spawning/significance. Bridges combat into Phase 15.
- Current slice: [131 — Phase 14 integration: town NPCs live in server_main + client replication](slices/131-phase14-town-npc-live-replication.md) — **delivered; **CLOSES THE PHASE 14 EXIT GATE**. `ServerTownNpcManager` wired into the running `server_main` (fixed in-town anchors, driven each tick) + town-NPC spawn/position/despawn replication + `client/town_npc.gd`; town NPCs appear and walk route-consistently live. Full cumulative Phase 14 tree 632/632 across 87/87 on the Linux host (incl. socket E2E harnesses)**. Prior: Slices 116-128 (contracts + parity), 129-130 (town-NPC state + population).
- Feature status: [F-036](FEATURE-LIST.md#f-036-phase-14-unified-character-and-npc-generalization) is now `Implemented`; Phase 14 exit gate is met (see the phase table).
- Tech debt: none identified across Slices 116-131; 125-126 removed provisional placeholders.

**Phase 16 — Client experience: controller, launcher, and auto-update**

Progress: **design complete; implementation started** (F-037 `in-progress`; first slice delivered)

- Source goals: [unified-launcher map](../.scratch/unified-launcher/map.md),
  [client-auto-update map](../.scratch/client-auto-update/map.md),
  [controller-integration map](../.scratch/controller-integration/map.md).
- Scope: one Windows launcher for safe LAN/WAN selection; a server-owned client
  build version gate before authentication with integrity-verified, atomic,
  rollback-safe patching (remote code delivery); controller input routed through
  existing named actions without adding client authority; first-run onboarding.
  Keyboard/mouse behavior unchanged.
- Handoff: [Windows client delivery contract](../.scratch/client-auto-update/spec.md)
  and [ADR 0008](adr/0008-windows-client-delivery-trust-and-rollback.md).
- Tech debt: `open` [DT-015](TECHNICAL-DEBT-TRACKER.md#dt-015-the-packaged-windows-client-logs-gdextension-load-errors-at-boot)
  — the packaged client logs three expected GDExtension errors at every boot,
  the same false-alarm pattern DT-014 fixed server-side; it will mask a real
  update or rollback failure, where the tester's log is the only evidence.
- **Slice 151:** the export exclusion now removes `.godot/**` editor/import
  metadata, closing DT-015 without shipping the server-only SQLite addon.
  Fresh fixed export contains no SQLite references, and a fresh packaged-client
  boot produced zero SQLite log lines. A separate packaging-tooling follow-on
  remains because the Windows ZIP fallback found Python unavailable.
- **Measured correction (2026-09-18):** a probe against the real packaged client
  disproved the "the running pack is file-locked" justification carried by
  ADR 0008 and the spec. Windows permits rename, open-for-write, and delete
  against a live client. Quit-then-swap is still required — Godot cannot
  hot-reload running scripts/autoloads, and lazy loads would mix new content
  with old code — but the OS provides no protection, so the updater's ordering
  and transaction marker are the only safeguard. Records corrected.
- Features: `in-progress` [F-037](FEATURE-LIST.md#f-037-windows-client-delivery--version-identity-mandatory-gate-and-signed-patching)
  — version identity delivered (Slice 144); handshake/gate, signed manifest,
  updater/rollback, launcher, and onboarding remain. The controller placeholder
  is a separate low-risk slice, not yet allocated a feature.
- Features: `in-progress` [F-037](FEATURE-LIST.md#f-037-windows-client-delivery--version-identity-mandatory-gate-and-signed-patching)
  — version identity (Slice 144) and the pre-auth handshake contract (Slice 145)
  delivered; live gate enforcement, signed manifest, updater/rollback, launcher,
  and onboarding remain. The controller placeholder is a separate low-risk slice,
  not yet allocated a feature.
- Features: `in-progress` [F-037](FEATURE-LIST.md#f-037-windows-client-delivery--version-identity-mandatory-gate-and-signed-patching)
  — version identity (144), handshake contract (145), live gate enforcement
  (146), signed-manifest verifier (147), HTTPS staging (148), updater
  transaction (149), and the trusted signing key + release signing (150)
  delivered; the updater's process orchestration, the enrollment `/patches`
  route, launcher LAN/WAN, and onboarding remain. The controller placeholder is
  a separate low-risk slice, not yet allocated a feature.
- Current slice: [150 — Phase 16 (F-037): trusted release key and one-command signing](slices/150-trusted-signing-key.md) — **delivered; `shared/client_signing_key.gd` embeds the RSA-3072 public key (fingerprint `69db4c67…77a232`) with a fail-closed `is_configured()`, and `scripts/sign_release.sh` signs a release in one command. Private key generated on the operator workstation and held offline — deliberately not on `okami`, which serves the downloads the signature must outlive. Full trust chain proven with the real key and script; GUT 774/774 across 106/106, exit 0**. Prior: [149](slices/149-updater-transaction.md), [148](slices/148-https-update-staging.md), [147](slices/147-signed-update-manifest.md).
- Current slice: [151 — Phase 16 (DT-015): packaged-client export metadata exclusion](slices/151-client-export-metadata-exclusion.md) — **delivered; `export_presets.cfg` now excludes `.godot/**`, removing the stale `extension_list.cfg` that made the packaged client try to load the intentionally excluded server-only SQLite extension. DT-015 is closed; fresh export/package-content and boot evidence remain the final check.** Prior: [150](slices/150-trusted-signing-key.md).
- Current slice: [152 — Phase 16 (F-037): enrollment HTTPS `/patches` hosting](slices/152-enrollment-patch-hosting.md) — **delivered; the existing FastAPI enrollment service serves public release artifacts under `/patches`, and compose mounts the host patch directory read-only. Enrollment pytest 122/122 passed; compose config validated on okami**. Prior: [151](slices/151-client-export-metadata-exclusion.md).
- Current slice: [153 — Phase 16 (F-037): launcher updater orchestration](slices/153-launcher-updater-orchestration.md) — **delivered; the Go launcher now owns a persistent AppData payload, runs startup recovery, exposes a detached apply helper, and relaunches the client through the launcher-owned payload. Go vet clean, `go test ./...` passed; packaged Windows end-to-end evidence remains the follow-on**. Prior: [152](slices/152-enrollment-patch-hosting.md).
- Current slice: [154 — Phase 16 (F-037): launcher signed-update download and staging](slices/154-launcher-signed-update-download.md) — **delivered; native Go now fetches and verifies raw signed manifest bytes over HTTPS, follows only the signed pack URL, checks size/SHA-256, and stages the pack for the detached helper. `go vet` clean and `go test ./...` passed with HTTPS-fixture coverage; live `CLIENT_OUTDATED` wiring and packaged Windows evidence remain**. Prior: [153](slices/153-launcher-updater-orchestration.md).
- Current slice: [155 — Phase 16 (F-037): `CLIENT_OUTDATED` handoff to launcher](slices/155-outdated-client-launcher-handoff.md) — **delivered; packaged-client rejection writes a bounded transient file and exits 20 only when that launcher handoff is configured, while the Go launcher reads/removes it, downloads/stages through Slice 154, and invokes Slice 153's helper with tunnel environment preserved. Go vet/test passed; full GUT 106/774/774; packaged Windows evidence remains**. Prior: [154](slices/154-launcher-signed-update-download.md).
- Current slice: [155 — Phase 16 (F-037): `CLIENT_OUTDATED` handoff to launcher](slices/155-outdated-client-launcher-handoff.md) — **delivered; packaged client rejection writes a bounded transient file and exits 20 only when launched by the updater, while the Go launcher reads/removes it, downloads/stages through Slice 154, and invokes the Slice 153 helper with tunnel environment preserved. Go vet/test passed; full GUT regression required; packaged Windows evidence remains**. Prior: [154](slices/154-launcher-signed-update-download.md).
- Tech debt: none.
- GitHub issues: [#100](https://github.com/vnvalentin/project0/issues/100),
  [#182](https://github.com/vnvalentin/project0/issues/182), and
  [#117](https://github.com/vnvalentin/project0/issues/117).
- Features/tech debt: none allocated yet. Implementation must be sliced from the
  handoff and retain the signed-manifest, fail-closed, rollback-safe boundary.

**Phase 17 — Fleet operations console**

Progress: **0%** (design in `.scratch/server-admin-console`; no delivery items allocated yet)

- Source goal: [server-admin-console map](../.scratch/server-admin-console/map.md).
- Scope: a private, authenticated LAN console showing a versioned ops-snapshot
  for every Project0 server (login, game, and any later server) plus a bounded,
  authorized, audited control-action catalog kept separate from public traffic.
  Extends the operator control plane (Slices 061–063).
- Features/tech debt: none allocated yet.

**Phase 18 — Horizontal scale and zone sharding**

Progress: **0%** (research-first; no `map.md` yet)

- Source goal: `.scratch/zone-sharding` — **new and unresearched** (no `map.md`).
  Must produce a research map and capstone ADR before any implementation slice
  is scoped; the exit gate is provisional until then.
- Scope (provisional): scale the world across multiple authoritative shards with
  a decided ownership and cross-shard handoff boundary, without weakening server
  authority.
- Features/tech debt: none allocated yet.

### Implementation slice index

A phase is the product-level desired outcome and exit gate. A slice is the
smallest observable, reversible increment that tests a stated hypothesis and
delivers a bounded capability toward a phase. Each slice has one primary phase
for delivery ownership, even when its linked work advances another phase.

Slice completion is based on its own SDD, BDD, TDD, ADR/no-ADR rationale,
validation, and review evidence. Phase completion is based on progress toward
the phase exit gate; it is not a count of completed slices.

#### Phase 16 — Client delivery experience

- **Slice:** [157 — Phase 16 (F-037): visible WAN package and opt-in stable-directory updates](slices/157-visible-wan-package.md) — **in-progress; launcher payloads are now external visible package files, installed under stable LocalAppData, and signed updates require explicit confirmation. Release and packaged-Windows runtime evidence remain pending.** Prior: [156](slices/156-release-client-downloads.md).
  - **Feature:** [F-037](FEATURE-LIST.md#f-037-windows-client-delivery--version-identity-mandatory-gate-and-signed-patching)
  - **GitHub issue:** [#100](https://github.com/vnvalentin/project0/issues/100) (also [#182](https://github.com/vnvalentin/project0/issues/182))

- **Slice:** [156 — Phase 16 (F-037): release pipeline publishes Windows client downloads](slices/156-release-client-downloads.md) — **delivered; tagged releases download the CI client artifact, publish the launcher and ZIP under `/patches/downloads/<version>/`, generate the public download page, and verify all three public URLs. v0.7.0 live verification passed.** Prior: [155](slices/155-outdated-client-launcher-handoff.md).
  - **Feature:** [F-037](FEATURE-LIST.md#f-037-windows-client-delivery--version-identity-mandatory-gate-and-signed-patching)
  - **GitHub issue:** [#100](https://github.com/vnvalentin/project0/issues/100) (also [#182](https://github.com/vnvalentin/project0/issues/182))

- **Slice:** [155 — Phase 16 (F-037): `CLIENT_OUTDATED` handoff to launcher](slices/155-outdated-client-launcher-handoff.md) — **delivered; client rejection writes the bounded server response to `PROJECT0_UPDATE_REJECTION_PATH` and exits code 20 only when that launcher handoff is configured; the Go launcher reads/removes it, validates `CLIENT_OUTDATED`, invokes native HTTPS verification/staging, and calls the detached helper with the existing tunnel environment. Direct client runs remain presentation-only. Go vet/test passed; full GUT 106/774/774 with 2451 asserts; packaged Windows runtime evidence remains required**
  - **Feature:** [F-037](FEATURE-LIST.md#f-037-windows-client-delivery--version-identity-mandatory-gate-and-signed-patching)
  - **GitHub issue:** [#100](https://github.com/vnvalentin/project0/issues/100) (also [#182](https://github.com/vnvalentin/project0/issues/182))
  - **Architecture:** [ADR 0008](adr/0008-windows-client-delivery-trust-and-rollback.md)
  - **Ownership:** implemented by Copilot under the standing Claude-unavailable authorization (trigger recorded in the slice record)

- **Slice:** [155 — Phase 16 (F-037): `CLIENT_OUTDATED` handoff to launcher](slices/155-outdated-client-launcher-handoff.md) — **delivered; client rejection writes the bounded server response to `PROJECT0_UPDATE_REJECTION_PATH` and exits code 20 only when that launcher handoff is configured; the Go launcher reads/removes it, validates `CLIENT_OUTDATED`, invokes the native HTTPS verifier/stager, and calls the detached helper with the existing tunnel environment. Direct client runs remain presentation-only. Go vet/test passed; full GUT regression and packaged Windows runtime evidence remain the gates for claiming the loop complete**
  - **Feature:** [F-037](FEATURE-LIST.md#f-037-windows-client-delivery--version-identity-mandatory-gate-and-signed-patching)
  - **GitHub issue:** [#100](https://github.com/vnvalentin/project0/issues/100) (also [#182](https://github.com/vnvalentin/project0/issues/182))
  - **Architecture:** [ADR 0008](adr/0008-windows-client-delivery-trust-and-rollback.md)
  - **Ownership:** implemented by Copilot under the standing Claude-unavailable authorization (trigger recorded in the slice record)

- **Slice:** [154 — Phase 16 (F-037): launcher signed-update download and staging](slices/154-launcher-signed-update-download.md) — **delivered; native Go implements the launcher-side trust boundary: raw manifest bytes verified with the embedded RSA-3072 key before JSON parsing, signed pack URL followed only after verification, size and streamed SHA-256 checked, temporary artifacts removed on failure, and the verified pack staged for Slice 153's helper. `go vet ./...` clean; `go test ./...` ok with a real in-process HTTPS fixture covering success, tamper, plaintext URL, up-to-date, and refusal cleanup. Live `CLIENT_OUTDATED` response wiring and packaged Windows runtime evidence remain**
  - **Feature:** [F-037](FEATURE-LIST.md#f-037-windows-client-delivery--version-identity-mandatory-gate-and-signed-patching)
  - **GitHub issue:** [#100](https://github.com/vnvalentin/project0/issues/100) (also [#182](https://github.com/vnvalentin/project0/issues/182))
  - **Architecture:** [ADR 0008](adr/0008-windows-client-delivery-trust-and-rollback.md)
  - **Ownership:** implemented by Copilot under the standing Claude-unavailable authorization (trigger recorded in the slice record)

- **Slice:** [153 — Phase 16 (F-037): launcher updater orchestration](slices/153-launcher-updater-orchestration.md) — **delivered; replaces disposable temp extraction with a persistent AppData payload, recovers interrupted transactions before launch, adds `--project0-update-helper` for detached apply, and uses client process exit as the current relaunch/readiness hook so the next pre-auth version handshake remains authoritative. Go vet clean, `go test ./...` ok; packaged Windows end-to-end evidence remains required**
  - **Feature:** [F-037](FEATURE-LIST.md#f-037-windows-client-delivery--version-identity-mandatory-gate-and-signed-patching)
  - **GitHub issue:** [#100](https://github.com/vnvalentin/project0/issues/100) (also [#182](https://github.com/vnvalentin/project0/issues/182))
  - **Architecture:** [ADR 0008](adr/0008-windows-client-delivery-trust-and-rollback.md)
  - **Ownership:** implemented by Copilot under the standing Claude-unavailable authorization (trigger recorded in the slice record)

- **Slice:** [152 — Phase 16 (F-037): enrollment HTTPS `/patches` hosting](slices/152-enrollment-patch-hosting.md) — **delivered; `infra/enrollment/app.py` mounts an optional `patches_dir` at `/patches` with `html=False`, `asgi.py` resolves `ENROLLMENT_PATCHES_DIR`, and `deploy/compose.yml` sets `/var/lib/project0/patches` with a read-only host volume. Public unauthenticated access is intentional because clients patch before authentication; the signature remains the trust anchor. Enrollment pytest 122/122 passed; compose config exit 0 on okami**
  - **Feature:** [F-037](FEATURE-LIST.md#f-037-windows-client-delivery--version-identity-mandatory-gate-and-signed-patching)
  - **GitHub issue:** [#100](https://github.com/vnvalentin/project0/issues/100) (also [#182](https://github.com/vnvalentin/project0/issues/182))
  - **Architecture:** [ADR 0008](adr/0008-windows-client-delivery-trust-and-rollback.md)
  - **Ownership:** implemented by Copilot under the standing Claude-unavailable authorization (trigger recorded in the slice record)

- **Slice:** [151 — Phase 16 (DT-015): packaged-client export metadata exclusion](slices/151-client-export-metadata-exclusion.md) — **delivered; adds `.godot/**` to the Windows export exclusion. The source project retains server-only SQLite and the client still excludes `addons/godot-sqlite/**`; the package no longer carries `.godot/extension_list.cfg`, the stale declaration that produced three SQLite GDExtension boot errors. Fresh export evidence identified the cause; a separate Windows ZIP fallback issue (Python unavailable when `zip` was absent) remains outside this slice**
  - **Feature:** [F-037](FEATURE-LIST.md#f-037-windows-client-delivery--version-identity-mandatory-gate-and-signed-patching)
  - **Tech debt:** closes [DT-015](TECHNICAL-DEBT-TRACKER.md#dt-015-the-packaged-windows-client-logs-gdextension-load-errors-at-boot)
  - **GitHub issue:** [#100](https://github.com/vnvalentin/project0/issues/100)
  - **Ownership:** implemented by Copilot under the standing Claude-unavailable authorization (trigger recorded in the slice record)

- **Slice:** [150 — Phase 16 (F-037): trusted release key and one-command signing](slices/150-trusted-signing-key.md) — **delivered; closes the hole Slice 147 left open deliberately. `shared/client_signing_key.gd` embeds the RSA-3072 public key (fingerprint `69db4c67…77a232`) plus a fail-closed `is_configured()` so a keyless build refuses to self-update rather than falling back to trusting its download, and `scripts/sign_release.sh` emits a signed `manifest.json` + detached `manifest.sig` in one command (refusing a malformed version, missing pack, missing key, or plaintext URL). The private key was generated on the operator workstation and stays offline — deliberately NOT on `okami`, which serves the very downloads the signature must be able to outlive. Anti-swap property: the next pack's manifest is verified with the key in the currently installed pack, so an attacker who can substitute a download cannot substitute the key that judges it. **Full trust chain executed with the real offline key and the real script**: `verify_and_parse: ok`, `verify_patch_file: ok`, tampered pack → `hash_mismatch`. GUT 774/774 across 106/106, exit 0; new `test_client_signing_key` 4/4**
  - **Feature:** [F-037](FEATURE-LIST.md#f-037-windows-client-delivery--version-identity-mandatory-gate-and-signed-patching) (seventh slice; feature `In Progress`)
  - **GitHub issue:** [#100](https://github.com/vnvalentin/project0/issues/100)
  - **Architecture:** [ADR 0008](adr/0008-windows-client-delivery-trust-and-rollback.md), decision 3
  - **Operator note:** private-key backup is an operator responsibility; the key exists on one disk and losing it forces a fresh trusted re-release to every tester
  - **Ownership:** implemented by Copilot under the standing Claude-unavailable authorization (trigger recorded in the slice record)
- **Slice:** [149 — Phase 16 (F-037): updater transaction — atomic swap, recovery, and rollback](slices/149-updater-transaction.md) — **delivered; the part that actually replaces the pack, and the part that has to survive being killed halfway through. `native/windows_launcher/updater.go` orders the swap so every interruption point is recoverable (copy staged onto the install volume so the rename is atomic → verify the copy's digest → mark `swap_started` → rename current to `.bak` → rename incoming into place → close the transaction), then recovers on startup: a swap that actually completed is kept, an incomplete one restores the known-good pack, and no-pack-no-backup reports `repair_required`. A corrupt marker reads as absent rather than stranding the tester. Two attempts per version, then `ErrRepairRequired`; a newer version gets a fresh budget. **Hosted in the Go launcher on purpose — the updater must not depend on the artifact it replaces**, since a Godot-hosted updater ships inside the very pack it is patching. `go vet` clean, `go test ./...` ok, 11/11 new tests with interruptions simulated against real on-disk states; GUT suite unchanged (no GDScript touched)**
  - **Feature:** [F-037](FEATURE-LIST.md#f-037-windows-client-delivery--version-identity-mandatory-gate-and-signed-patching) (sixth slice; feature `In Progress`)
  - **GitHub issue:** [#100](https://github.com/vnvalentin/project0/issues/100) (also [#182](https://github.com/vnvalentin/project0/issues/182))
  - **Architecture:** [ADR 0008](adr/0008-windows-client-delivery-trust-and-rollback.md), decisions 4–5
  - **Not yet claimed:** end-to-end self-update. The process orchestration (launch detached, quit, relaunch, post-patch readiness check) and the embedded production key land next, with packaged-Windows runtime evidence
  - **Ownership:** implemented by Copilot under the standing Claude-unavailable authorization (trigger recorded in the slice record)
- **Slice:** [148 — Phase 16 (F-037): HTTPS update staging](slices/148-https-update-staging.md) — **delivered; `client/update_stager.gd` derives the manifest/signature URLs from an HTTPS base (a plaintext base returns `""` and cannot even be addressed, so no downgrade is attempted-then-caught), fetches manifest + detached signature + patch over bounded HTTPS, and stages the patch under `user://` only after it verifies through `UpdateManifest` — re-checking the bytes that actually landed on disk, not the buffer in memory. **Every failure path ends in `discard_staging`**, because the staging directory is the handoff to the updater and anything left in it is something the updater might later treat as ready. New `test_update_stager` 8/8 (real RSA-3072 keys, real files, asserting the staging directory is absent after every refusal); full GUT suite 770/770 across 105/105, exit 0**
  - **Feature:** [F-037](FEATURE-LIST.md#f-037-windows-client-delivery--version-identity-mandatory-gate-and-signed-patching) (fifth slice; feature `In Progress`)
  - **GitHub issue:** [#100](https://github.com/vnvalentin/project0/issues/100)
  - **Architecture:** [ADR 0008](adr/0008-windows-client-delivery-trust-and-rollback.md), decision 4
  - **Known coverage gap:** the HTTPS transport itself is not automatically tested (no HTTPS fixture in the suite); all trust decisions live in the tested static functions it delegates to, and packaged-client runtime evidence remains required before F-037 can be `Implemented`
  - **Ownership:** implemented by Copilot under the standing Claude-unavailable authorization (trigger recorded in the slice record)
- **Slice:** [147 — Phase 16 (F-037): signed update-manifest verifier](slices/147-signed-update-manifest.md) — **delivered; the trust anchor for remote code delivery. `shared/update_manifest.gd` verifies a detached RSA signature over the **raw manifest bytes before parsing them** — verifying a re-serialized copy is a classic signature bypass, since two byte strings can parse to the same object — then validates the fields fail-closed (schema, semver, lowercase 64-hex digest, HTTPS-only URL, positive size) and verifies a downloaded patch against the signed size and a streamed SHA-256 (size first to bound the work; equal-length/wrong-content is explicitly refused). `manifest` is `null` on every non-ok outcome so an unverified document can never be read from, and `key_unusable` is distinct from `unverified` so an operator's broken key is not reported as an attack. New `test_update_manifest` 11/11 using **real RSA-3072 keypairs generated in-test** (genuine tampered-document and foreign-key refusals); full GUT suite 762/762 across 104/104, exit 0. Deliberately not wired to a trusted key yet — a placeholder key would look functional while trusting nothing real**
  - **Feature:** [F-037](FEATURE-LIST.md#f-037-windows-client-delivery--version-identity-mandatory-gate-and-signed-patching) (fourth slice; feature `In Progress`)
  - **GitHub issue:** [#100](https://github.com/vnvalentin/project0/issues/100)
  - **Architecture:** [ADR 0008](adr/0008-windows-client-delivery-trust-and-rollback.md), decision 3
  - **Ownership:** implemented by Copilot under the standing Claude-unavailable authorization (trigger recorded in the slice record)
- **Slice:** [146 — Phase 16 (F-037): live version-gate enforcement](slices/146-version-gate-enforcement.md) — **delivered; **the mandatory pre-auth version gate is now live**. `client/network_client.gd` sends `VersionHandshake.request()` as its first post-connect message; `server/server_main.gd` defers *all* peer admission — town replication, Player spawn, house allocation, and peer cross-replication moved into a new `_admit_peer` — until a handshake is accepted, so a refused client never receives world state at all. A mismatched client gets `CLIENT_OUTDATED` with its required version and manifest URL before a graceful disconnect (so the reliable rejection flushes), a resent handshake cannot re-roll the gate, and a server whose `PROJECT0_REQUIRED_CLIENT_VERSION` is unusable refuses to start instead of rejecting everyone. New `test_version_gate_client_seam` 4/4; full GUT suite 751/751 across 103/103, exit 0, with the socket E2E harnesses unchanged. Runtime-proven on real processes both ways: matching server → exit 0, "passed the version gate", ALL PASS; server requiring 9.9.9 → exit 1, "Refusing peer …: CLIENT_OUTDATED", no Player spawned; malformed requirement → exit 1, never bound**
  - **Feature:** [F-037](FEATURE-LIST.md#f-037-windows-client-delivery--version-identity-mandatory-gate-and-signed-patching) (third slice; feature `In Progress`)
  - **GitHub issue:** [#100](https://github.com/vnvalentin/project0/issues/100)
  - **Architecture:** [ADR 0008](adr/0008-windows-client-delivery-trust-and-rollback.md), decision 2
  - **Known limitation:** a peer that never handshakes holds an idle ENet slot; a pending-handshake timeout is a follow-on
  - **Ownership:** implemented by Copilot under the standing Claude-unavailable authorization (trigger recorded in the slice record)
- **Slice:** [145 — Phase 16 (F-037): pre-auth version handshake contract and required-version resolution](slices/145-version-handshake-contract.md) — **delivered; `shared/version_handshake.gd` (`VersionHandshake`) is the decision the mandatory gate will enforce: it builds the client's first message from `ClientBuildVersion.current()`, resolves the server-owned requirement from `PROJECT0_REQUIRED_CLIENT_VERSION` (defaulting to this build, `""` when the override is malformed so callers fail closed) and an HTTPS-only manifest URL, and evaluates them into `ACCEPTED` / `CLIENT_OUTDATED` / `MALFORMED` / `SERVER_MISCONFIGURED` (reserved `UNSUPPORTED`). Exact-equality comparison — older and newer clients are refused identically — and a rejected client is handed its required version and where to patch. `SERVER_MISCONFIGURED` keeps an operator's bad config from being reported as the player's client being outdated. New `test_version_handshake` 13/13; full GUT suite 747/747 across 102/102, exit 0 on the Linux host. Live enforcement deliberately deferred: the connect lifecycle is a declared shared hot-spot**
  - **Feature:** [F-037](FEATURE-LIST.md#f-037-windows-client-delivery--version-identity-mandatory-gate-and-signed-patching) (second slice; feature `In Progress`)
  - **GitHub issue:** [#100](https://github.com/vnvalentin/project0/issues/100)
  - **Architecture:** [ADR 0008](adr/0008-windows-client-delivery-trust-and-rollback.md), decision 2
  - **Ownership:** implemented by Copilot under the standing Claude-unavailable authorization (trigger recorded in the slice record)
- **Slice:** [144 — Phase 16 (F-037): client build version identity and export-time stamp](slices/144-client-build-version-stamp.md) — **delivered; the first implementation slice of the accepted Phase 16 handoff and the root dependency of every later slice in it. `shared/client_build_version.gd` (`ClientBuildVersion.current()` + fail-closed `is_valid()` semver validation) gives the running client its own build identity from inside the `.pck`, and `scripts/stamp_client_build_version.sh` — run by `export_windows_client.sh` before the Godot export and restored afterward — writes the released version into it, replacing a version that existed only in the ZIP name. Deterministic, idempotent, and fail-closed: six malformed inputs each exit non-zero leaving the contract untouched. New `test_client_build_version` 5/5; full GUT suite 734/734 across 101/101, exit 0 on the Linux host. Validation caught a real CRLF anchoring bug in the stamp guard before merge**
  - **Feature:** [F-037](FEATURE-LIST.md#f-037-windows-client-delivery--version-identity-mandatory-gate-and-signed-patching) (first slice; feature `In Progress`)
  - **GitHub issue:** [#100](https://github.com/vnvalentin/project0/issues/100) (also [#182](https://github.com/vnvalentin/project0/issues/182))
  - **Architecture:** [ADR 0008](adr/0008-windows-client-delivery-trust-and-rollback.md), decision 1
  - **Ownership:** implemented by Copilot under the standing Claude-unavailable authorization (trigger recorded in the slice record)

#### Phase 15 — Biological progression and kinetic systems

- **Slice:** [143 — Phase 15 follow-on (P-016): durable vessel persistence](slices/143-vessel-persistence.md) — **delivered; the second and last Slice 140 follow-on. `VesselProgressionState.to_wire_dict()` (inverse of the existing `from_wire_dict`) + server-only `server/vessel_repository.gd` (`VesselRepository`) over the shared `SqliteStore` seam, mirroring `CanonRepository`: `ensure_schema`, idempotent `save_vessel` upsert by `character_id`, and `load_vessel` revalidated fail-closed against the current tuning (schema/structure/bounds/budget) or not-found. A Character's earned vessel survives a server restart. New `test_vessel_repository` 6/6 over a real `user://` SQLite db (save→restart→identical recovery, trained round-trip, upsert, corrupt-row fail-closed, empty-id refusal); full GUT suite 729/729 across 100/100, exit 0 on the Linux host. Server-only — `shared/`/`client/` never touch the store**
  - **Feature:** [P-016](FEATURE-LIST.md#p-016-biological-progression-and-kinetic-combat-systems) (stays `Implemented`; persistence wiring on the closed gate)
  - **GitHub issue:** [#219](https://github.com/vnvalentin/project0/issues/219) (vessel contract [#223](https://github.com/vnvalentin/project0/issues/223))
  - **Architecture:** [ADR 0006](adr/0006-versioned-embodiment-mechanics-architecture.md)
- **Slice:** [142 — Phase 15 follow-on (P-016): live RPC replication of the EffectiveMechanicsSnapshot](slices/142-effective-mechanics-replication.md) — **delivered; post-exit-gate follow-on that Slice 140 explicitly deferred. `server/server_player_state.gd` creates a durable vessel (its own `EmbodimentProgressionService` + resolved default tuning) and emits `effective_mechanics_ready` at world entry; `server/server_main.gd` replicates it peer-scoped (mirroring the Phase 14 Character-snapshot channel); `client/network_client.gd` validates the untrusted wire fail-closed, retains it, and re-emits it; `client/effective_mechanics_label.gd` renders a HUD readout. Presentation-safe only — raw effective/base numbers + tuning tables never cross. New `test_effective_mechanics_replication` 7/7 + `test_effective_mechanics_label` 5/5; full GUT suite 723/723 across 99/99, exit 0 on the Linux host (+2 scripts, +11 tests). Vessel SQLite persistence remains the outstanding Slice 140 follow-on**
  - **Feature:** [P-016](FEATURE-LIST.md#p-016-biological-progression-and-kinetic-combat-systems) (stays `Implemented`; wiring on the closed gate)
  - **GitHub issue:** [#219](https://github.com/vnvalentin/project0/issues/219) (snapshot contract [#224](https://github.com/vnvalentin/project0/issues/224))
  - **Architecture:** [ADR 0006](adr/0006-versioned-embodiment-mechanics-architecture.md)
- **Slice:** [140 — Phase 15 (P-016-A/G): server progression service composing vessel + subsystems](slices/140-phase15-embodiment-progression-service.md) — **delivered; **closes the Phase 15 exit gate**. `server/embodiment_progression_service.gd` (`EmbodimentProgressionService`) owns vessels/Meridians/Burnouts, accepts deduplicated training/cross-training evidence, resolves magic, and composes the vessel + all five subsystems into one deterministic, presentation-safe `EffectiveMechanicsSnapshot` (hidden numeric state server-side); new `test_embodiment_progression_service` 10/10 (end-to-end); full GUT suite 503/503 across 73/73, exit 0 on the Linux host**
  - **Feature:** [P-016](FEATURE-LIST.md#p-016-biological-progression-and-kinetic-combat-systems) (now `Implemented`)
  - **GitHub issue:** #219 (design sources #224, ADR 0006, SYSTEMS-SPECIFICATION.md)
  - **Architecture:** [ADR 0006](adr/0006-versioned-embodiment-mechanics-architecture.md)
- **Slice:** [139 — Phase 15 (P-016-F): Magic equilibrium](slices/139-phase15-magic-equilibrium.md) — **delivered; the magic tuning namespace on `server/embodiment_tuning.gd` + `shared/magic_equilibrium.gd` — bulk (STR+CON) insulation grounds magic; `resolve` yields CHANNELED/FIZZLE/BACKLASH/REJECTED with a bounded reason, higher tiers demand leaning out, every attempt explicit; new `test_magic_equilibrium` 8/8; full GUT suite 501/501 across 73/73, exit 0 on the Linux host. All five embodiment subsystems now delivered on the P-016-A read-model**
  - **Feature:** [P-016](FEATURE-LIST.md#p-016-biological-progression-and-kinetic-combat-systems)
  - **GitHub issue:** #219 (design source: SYSTEMS-SPECIFICATION.md Magic Equilibrium)
  - **Architecture:** [ADR 0006](adr/0006-versioned-embodiment-mechanics-architecture.md)
- **Slice:** [138 — Phase 15 (P-016-E): Biological Burnout](slices/138-phase15-biological-burnout.md) — **delivered; the burnout tuning namespace on `server/embodiment_tuning.gd` + `shared/burnout_instance.gd` — a temporary modifier (authoritative start/end tick, pathway, source action, tuning version) flattening the affected pathway's effective Control while active + auto-restore + the normative lifecycle transition validator; new `test_burnout_instance` 7/7; full GUT suite 500/500 across 73/73, exit 0 on the Linux host**
  - **Feature:** [P-016](FEATURE-LIST.md#p-016-biological-progression-and-kinetic-combat-systems)
  - **GitHub issue:** #219 (design source: SYSTEMS-SPECIFICATION.md Biological Burnout)
  - **Architecture:** [ADR 0006](adr/0006-versioned-embodiment-mechanics-architecture.md)
- **Slice:** [137 — Phase 15 (P-016-D): Meridian pathways](slices/137-phase15-meridian-pathways.md) — **delivered; the meridian tuning namespace on `server/embodiment_tuning.gd` + `shared/meridian_state.gd` — per-pathway (Impact/Flow/Spark) progress from deduplicated cross-training evidence with a deterministic, idempotent, durable threshold unlock; new `test_meridian_state` 8/8; full GUT suite 501/501 across 73/73, exit 0 on the Linux host**
  - **Feature:** [P-016](FEATURE-LIST.md#p-016-biological-progression-and-kinetic-combat-systems)
  - **GitHub issue:** #219 (design source: SYSTEMS-SPECIFICATION.md Meridian Pathways)
  - **Architecture:** [ADR 0006](adr/0006-versioned-embodiment-mechanics-architecture.md)
- **Slice:** [136 — Phase 15 (P-016-C): Kinetic Flow layer](slices/136-phase15-kinetic-flow.md) — **delivered; the kinetic tuning namespace on `server/embodiment_tuning.gd` + `shared/kinetic_flow.gd` — pure derivation of Volume(←CON)/Control(←DEX)/Output(←STR) + energy-cost inflation from Control/Volume slosh; new `test_kinetic_flow` 6/6; full GUT suite 499/499 across 73/73, exit 0 on the Linux host**
  - **Feature:** [P-016](FEATURE-LIST.md#p-016-biological-progression-and-kinetic-combat-systems)
  - **GitHub issue:** #219 (design source: SYSTEMS-SPECIFICATION.md Kinetic Flow Layer)
  - **Architecture:** [ADR 0006](adr/0006-versioned-embodiment-mechanics-architecture.md)
- **Slice:** [135 — Phase 15 (P-016-B): inverse friction modifier](slices/135-phase15-friction-modifier.md) — **delivered; the friction tuning namespace on `server/embodiment_tuning.gd` + `shared/friction_modifier.gd` — pure derivation of Massive Bulk (high STR + CON) / Fragile Agility (high DEX + low CON) / none profiles + modifier factors from the effective nodes; new `test_friction_modifier` 7/7; full GUT suite 500/500 across 73/73, exit 0 on the Linux host**
  - **Feature:** [P-016](FEATURE-LIST.md#p-016-biological-progression-and-kinetic-combat-systems)
  - **GitHub issue:** #219 (design source: SYSTEMS-SPECIFICATION.md Inverse Biological Friction)
  - **Architecture:** [ADR 0006](adr/0006-versioned-embodiment-mechanics-architecture.md)
- **Slice:** [134 — Phase 15 (P-016-A): effective mechanics snapshot](slices/134-phase15-effective-mechanics-snapshot.md) — **delivered; `shared/effective_mechanics_snapshot.gd` — deterministic derivation of effective nodes from the durable vessel under the current tuning + a presentation-safe normalized graph (never raw numbers) + fail-closed `from_presentation_wire`; new `test_effective_mechanics_snapshot` 8/8; full GUT suite 501/501 across 73/73, exit 0 on the Linux host**
  - **Feature:** [P-016](FEATURE-LIST.md#p-016-biological-progression-and-kinetic-combat-systems)
  - **GitHub issue:** #219 (design source #224)
  - **Architecture:** [ADR 0006](adr/0006-versioned-embodiment-mechanics-architecture.md)
- **Slice:** [133 — Phase 15 (P-016-A): vessel progression state + fixed-budget redistribution](slices/133-phase15-vessel-progression.md) — **delivered; `shared/vessel_progression_state.gd` — durable earned six-node vessel pinned to a `tuning_version` + the ADR-0006 fixed-budget redistribution on `train` (weighted opposition compression, floor clamp + deterministic re-spread, atomic reject-at-capacity); new `test_vessel_progression_state` 11/11; full GUT suite 504/504 across 73/73, exit 0 on the Linux host**
  - **Feature:** [P-016](FEATURE-LIST.md#p-016-biological-progression-and-kinetic-combat-systems)
  - **GitHub issue:** #219 (design source #223)
  - **Architecture:** [ADR 0006](adr/0006-versioned-embodiment-mechanics-architecture.md)
- **Slice:** [132 — Phase 15 (P-016-A): versioned embodiment tuning resolve seam](slices/132-phase15-embodiment-tuning.md) — **delivered; `shared/embodiment_tuning_schema.gd` (shape/bounds/helpers) + `server/embodiment_tuning.gd` (frozen tables behind the sole, fail-closed `resolve(tuning_version)`); subsystems never read tables directly, unknown versions fail closed; new `test_embodiment_tuning` 8/8; full GUT suite 501/501 across 73/73, exit 0 on the Linux host**
  - **Feature:** [P-016](FEATURE-LIST.md#p-016-biological-progression-and-kinetic-combat-systems)
  - **GitHub issue:** #219 (design source #220)
  - **Architecture:** [ADR 0006](adr/0006-versioned-embodiment-mechanics-architecture.md)

#### Phase 14 — NPC generalization and shared Character

- **Slice:** [158 — Player traversal locomotion baseline](slices/158-player-traversal-locomotion.md) — **delivered; jump, dodge, duck, and slide run through the ordered server-authoritative movement seam, with raised-platform landing, low-ceiling posture checks, and dodge damage protection validated on Linux.**
  - **Feature:** [F-036](FEATURE-LIST.md#f-036-phase-14-unified-character-and-npc-generalization)
  - **GitHub issue:** [#229](https://github.com/vnvalentin/project0/issues/229)

- **Slice:** [131 — Phase 14 integration: town NPCs live in server_main + client replication](slices/131-phase14-town-npc-live-replication.md) — **delivered; **closes the Phase 14 exit gate**. `ServerTownNpcManager` instantiated and driven in the running `server_main` (fixed in-town anchors) with town-NPC spawn/position/despawn replication mirroring the monster channel + a cosmetic `client/town_npc.gd`; town NPCs appear and walk route-consistently for connected players. Full cumulative Phase 14 tree (main + slice) 632/632 across 87/87, exit 0 on the Linux host, including the socket E2E harnesses (real `server_main` + `gameplay.tscn`); new `test_town_npc_replication` 7/7**
  - **Feature:** [F-036](FEATURE-LIST.md#f-036-phase-14-unified-character-and-npc-generalization) (now `Implemented`)
  - **GitHub issue:** #227 (design sources #229, #232)
  - **Architecture:** [ADR 0007](adr/0007-unified-character-and-npc-generalization.md)
- **Slice:** [130 — Phase 14 integration: live town-NPC population manager (SpawnAnchor)](slices/130-phase14-town-npc-manager.md) — **delivered; `ServerTownNpcManager` staffs a town's fixed anchors with live `ServerTownNpcState` NPCs and runs population on the `SpawnAnchor` contract — anchors start staffed, a lost occupant is refilled only after a pressure-scaled delay (never an instant clone), sourcing a silent promotion of an ambient NPC or a freshly generated unique identity, never a resurrection; new `test_server_town_npc_manager` 7/7; full GUT suite 500/500 across 73/73, exit 0 on the Linux host**
  - **Feature:** [F-036](FEATURE-LIST.md#f-036-phase-14-unified-character-and-npc-generalization)
  - **GitHub issue:** #227 (design source #232)
  - **Architecture:** [ADR 0007](adr/0007-unified-character-and-npc-generalization.md)
- **Slice:** [129 — Phase 14 integration: live town-NPC state (Character + ActivityRoutine)](slices/129-phase14-town-npc-state.md) — **delivered; `ServerTownNpcState` — a server-owned town NPC that is an AI "villager" Character (shared `CharacterFoundation`) living to an `ActivityRoutine`, its world position a pure function of elapsed ticks (travels between activity locations, free off-screen simulation, route-consistent arrival), interruptible with position freezing, presentation-safe snapshot; new `test_server_town_npc_state` 9/9; full GUT suite 502/502 across 73/73, exit 0 on the Linux host**
  - **Feature:** [F-036](FEATURE-LIST.md#f-036-phase-14-unified-character-and-npc-generalization)
  - **GitHub issue:** #227 (design source #229)
  - **Architecture:** [ADR 0007](adr/0007-unified-character-and-npc-generalization.md)
- **Slice:** [128 — Phase 14 integration: NPC/monster carries the shared CharacterFoundation](slices/128-phase14-npc-character-foundation.md) — **delivered; `ServerMonsterState` carries an AI-controlled baseline `CharacterFoundation` + presentation-safe `character_snapshot()` — the NPC is the same unified Character as the Player, differing only in controller type; new `test_shared_character_player_npc_parity` 4/4 (real Player + monster nodes) + monster combat regression `test_server_monster_state` 10/10 & `test_server_monster_manager` 19/19 unchanged; full GUT suite 493/493 across 73/73, exit 0 on the Linux host**
  - **Feature:** [F-036](FEATURE-LIST.md#f-036-phase-14-unified-character-and-npc-generalization)
  - **GitHub issue:** #227 (design source: Slice 116 handoff)
  - **Architecture:** [ADR 0007](adr/0007-unified-character-and-npc-generalization.md)
- **Slice:** [127 — Phase 14 integration: server-owned Character foundation + snapshot replication](slices/127-phase14-character-foundation-server.md) — **delivered; `ServerPlayerState` creates a baseline humanoid `CharacterFoundation` at world entry, exposes a presentation-safe `character_snapshot()` + `character_snapshot_ready` signal; `server_main` replicates it to the owning client (new peer-scoped RPC mirroring HP); `NetworkClient` store + HUD `VesselLabel`; full GUT suite 502/502 across 74/74, exit 0 on the Linux host — `test_character_foundation_replication` 4/4 (incl. no-raw-numbers invariant, real node) + `test_character_vessel_label` 5/5 + real-scene `test_identity_gate_and_movement` 4/4 + `test_melee_strike_visual_indicator` 9/9**
  - **Feature:** [F-036](FEATURE-LIST.md#f-036-phase-14-unified-character-and-npc-generalization)
  - **GitHub issue:** #227 (design source #230)
  - **Architecture:** [ADR 0007](adr/0007-unified-character-and-npc-generalization.md)
- **Slice:** [126 — Phase 14 integration: Monster HP on shared CombatHealth](slices/126-phase14-monster-health-integration.md) — **delivered; migrated the live Monster HP pool from provisional `MonsterCombatState` to the shared `CombatHealth` contract (behaviour-preserving `ServerMonsterState` seam + one-death/respawn semantics); regression net `test_server_monster_state` 10/10 + `test_server_monster_manager` 19/19 + integration `test_authoritative_melee_strike` 9/9 (real-node runtime evidence) unchanged; full GUT suite 489/489 across 72/72, exit 0 on the Linux host. Player and monster HP now share one contract**
  - **Feature:** [F-036](FEATURE-LIST.md#f-036-phase-14-unified-character-and-npc-generalization)
  - **GitHub issue:** #227 (design source #231)
  - **Architecture:** [ADR 0007](adr/0007-unified-character-and-npc-generalization.md)
- **Slice:** [125 — Phase 14 integration: Player HP on shared CombatHealth](slices/125-phase14-player-health-integration.md) — **delivered; migrated the live Player HP pool from provisional `PlayerVitals` to the shared `CombatHealth` contract (behaviour-preserving public seam + defeat/respawn semantics); regression net `test_server_player_state_damage` 5/5 + integration `test_monster_damages_player` 2/2 (real node/signal runtime evidence) unchanged; full GUT suite 488/488 across 72/72, exit 0 on the Linux host**
  - **Feature:** [F-036](FEATURE-LIST.md#f-036-phase-14-unified-character-and-npc-generalization)
  - **GitHub issue:** #227 (design source #231)
  - **Architecture:** [ADR 0007](adr/0007-unified-character-and-npc-generalization.md)
- **Slice:** [124 — Phase 14 spawn-anchor / NPC population](slices/124-phase14-spawn-anchor.md) — **delivered; `SpawnAnchor` (fixed-anchor staffing: deficit, pressure-scaled replacement delay, promote-ambient-or-generate-new-identity, never resurrect) + 15 public-seam tests; full GUT suite 508/508 across 73/73, exit 0 on the Linux host; completes the Phase 14 shared-contract set (116-124)**
  - **Feature:** [F-036](FEATURE-LIST.md#f-036-phase-14-unified-character-and-npc-generalization)
  - **GitHub issue:** #227 (design source #232)
  - **Architecture:** [ADR 0007](adr/0007-unified-character-and-npc-generalization.md)
- **Slice:** [123 — Phase 14 activity-routine](slices/123-phase14-activity-routine.md) — **delivered; `ActivityRoutine` (pure time→activity resolution over a looping routine, free off-screen simulation, route-consistent arrival, idle/patrol fallback, interrupt/resume) + 16 public-seam tests; full GUT suite 509/509 across 73/73, exit 0 on the Linux host**
  - **Feature:** [F-036](FEATURE-LIST.md#f-036-phase-14-unified-character-and-npc-generalization)
  - **GitHub issue:** #227 (design source #229)
  - **Architecture:** [ADR 0007](adr/0007-unified-character-and-npc-generalization.md)
- **Slice:** [122 — Phase 14 status-effect (resistible / removable)](slices/122-phase14-status-effect.md) — **delivered; `StatusEffect` (deliberate magical/impairment effect, deterministic resistance gate, cleanse/expire lifecycle, no injury system) + 13 public-seam tests; full GUT suite 506/506 across 73/73, exit 0 on the Linux host**
  - **Feature:** [F-036](FEATURE-LIST.md#f-036-phase-14-unified-character-and-npc-generalization)
  - **GitHub issue:** #227 (design source #231)
  - **Architecture:** [ADR 0007](adr/0007-unified-character-and-npc-generalization.md)
- **Slice:** [121 — Phase 14 damage-resolution composition](slices/121-phase14-damage-resolution.md) — **delivered; `DamageResolution` (pure composition of weapon/attribute/technique/mitigation into one damage amount for `CombatHealth`, mitigation-capped, floored at zero) + 12 public-seam tests incl. end-to-end composition; full GUT suite 505/505 across 73/73, exit 0 on the Linux host**
  - **Feature:** [F-036](FEATURE-LIST.md#f-036-phase-14-unified-character-and-npc-generalization)
  - **GitHub issue:** #227 (design source #231)
  - **Architecture:** [ADR 0007](adr/0007-unified-character-and-npc-generalization.md)
- **Slice:** [120 — Phase 14 shared health / defeat / recovery](slices/120-phase14-combat-health.md) — **delivered; `CombatHealth` (shared damage/recovery/defeat pool, presentation fraction, no injury subsystem) + 12 public-seam tests; full GUT suite 549/549 across 77/77, exit 0 on the Linux host**
  - **Feature:** [F-036](FEATURE-LIST.md#f-036-phase-14-unified-character-and-npc-generalization)
  - **GitHub issue:** #227 (design source #231)
  - **Architecture:** [ADR 0007](adr/0007-unified-character-and-npc-generalization.md)
- **Slice:** [119 — Phase 14 technique readiness & proficiency](slices/119-phase14-technique-contract.md) — **delivered; `TechniqueContract` (multidimensional readiness, per-node shortfalls, proficiency reliability, mastery/teaching gates) + 11 public-seam tests; full GUT suite 537/537 across 76/76, exit 0 on the Linux host**
  - **Feature:** [F-036](FEATURE-LIST.md#f-036-phase-14-unified-character-and-npc-generalization)
  - **GitHub issue:** #227 (design source #230, #234)
  - **Architecture:** [ADR 0007](adr/0007-unified-character-and-npc-generalization.md)
- **Slice:** [118 — Phase 14 item & equipment effectiveness](slices/118-phase14-item-equipment.md) — **delivered; `ItemContract` (slots/category/binding, item+class proficiency effectiveness curve, mastery proc, tradeability) + 12 public-seam tests; full GUT suite 526/526 across 75/75, exit 0 on the Linux host**
  - **Feature:** [F-036](FEATURE-LIST.md#f-036-phase-14-unified-character-and-npc-generalization)
  - **GitHub issue:** #227 (design source #233)
  - **Architecture:** [ADR 0007](adr/0007-unified-character-and-npc-generalization.md)
- **Slice:** [117 — Phase 14 Character alignment & disposition](slices/117-phase14-character-alignment.md) — **delivered; `CharacterAlignment` contract (morality/chaos axes, deceptive label, relationship-driven disposition, lawful-under-authority restraint) + 12 public-seam tests; full GUT suite 514/514 across 74/74, exit 0 on the Linux host**
  - **Feature:** [F-036](FEATURE-LIST.md#f-036-phase-14-unified-character-and-npc-generalization)
  - **GitHub issue:** #227 (design source #228)
  - **Architecture:** [ADR 0007](adr/0007-unified-character-and-npc-generalization.md)
- **Slice:** [116 — Phase 14 Character foundation handoff](slices/116-phase14-character-foundation-handoff.md) — **delivered; unified `CharacterFoundation` contract + 9 public-seam tests; full GUT suite 502/502 across 73/73, exit 0 on the Linux host**
  - **Feature:** [F-036](FEATURE-LIST.md#f-036-phase-14-unified-character-and-npc-generalization)
  - **GitHub issue:** #227
  - **Architecture:** [ADR 0007](adr/0007-unified-character-and-npc-generalization.md)

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

#### Phase 7 — Multi-peer Player replication

- **Slice:** [086 — Multi-peer Character replication](slices/086-multipeer-character-replication.md) — **delivered; ServerPlayerState emits `character_bound` at world entry, server_main broadcasts `receive_remote_player_identity` to every other peer and seeds late-joiners, NetworkClient caches+relays it, and RemotePlayer renders a billboarded name label; GUT 401/401 across 59 scripts + login-handoff e2e ALL PASS on Linux; closes the Phase 10 multi-peer Character replication follow-up**
  - **Feature:** [F-004](FEATURE-LIST.md#f-004-multi-peer-player-replication)
  - **Planning ticket:** [Multi-peer Player replication](../.scratch/game-vision/issues/13-multi-peer-player-replication.md)

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

#### Phase 13 — Delivery workflow capabilities

- **Slice:** [178 — Reality page phase bars use real Outcome-label completion](slices/178-reality-page-outcome-percentages.md) — **delivered; `/` and `/detail` now report identical active-phase percentages from the same `phase_milestones()` source**
  - **Feature:** [F-025](FEATURE-LIST.md#f-025-project-flow-visual-management-dashboard)
  - **Tech debt:** none identified
  - **Planning ticket:** [Dashboard restructure map](https://github.com/vnvalentin/project0/issues/374)

- **Slice:** [177 — Dashboard per-slice Goal alignment](slices/177-dashboard-per-slice-goal-alignment.md) — **delivered; each slice row shows its own resolved Goal (via linked issue's `Parent goal: #N`) instead of its phase's full goal list; 23 slices resolved real Goals, rest correctly show no linked goal**
  - **Feature:** [F-025](FEATURE-LIST.md#f-025-project-flow-visual-management-dashboard)
  - **Tech debt:** none identified
  - **Planning ticket:** [Dashboard restructure map](https://github.com/vnvalentin/project0/issues/374)

- **Slice:** [176 — Dashboard Phase/Outcome/Slice/Goal roadmap rebuild](slices/176-dashboard-phase-outcome-roadmap.md) — **delivered; `/detail` rebuilt around live GitHub Phase-milestone/Outcome-label data, retiring `.scratch` goal maps, the old traceability summary, phase/slice tables, and the standalone milestone section; `render`/`render_exec`/`render_tests`/`render_telemetry` all smoke-tested against live data with no errors**
  - **Feature:** [F-025](FEATURE-LIST.md#f-025-project-flow-visual-management-dashboard)
  - **Tech debt:** none identified
  - **Planning ticket:** [Dashboard restructure map](https://github.com/vnvalentin/project0/issues/374) (decisions [#376](https://github.com/vnvalentin/project0/issues/376), [#377](https://github.com/vnvalentin/project0/issues/377), [#378](https://github.com/vnvalentin/project0/issues/378), [#379](https://github.com/vnvalentin/project0/issues/379), prototype [#380](https://github.com/vnvalentin/project0/issues/380))
  - **Decision:** no new ADR; implements the Phase=milestone / Track-renamed-Outcome=label convention decided on the map

- **Slice:** [165 — Dashboard telemetry page](slices/165-dashboard-telemetry-page.md) — **delivered; /telemetry page live, manual e2e HTTP check confirmed counters + filter, record-sync 0 errors — closes out the telemetry pipeline route**
  - **Feature:** [F-038](FEATURE-LIST.md#f-038-cross-cutting-telemetry-pipeline-envelope-transport-storage-dashboard)
  - **Tech debt:** none identified
  - **Planning ticket:** [telemetry wayfinder map](https://github.com/vnvalentin/project0/issues/282) (decision [#290](https://github.com/vnvalentin/project0/issues/290)), [slice route](https://github.com/vnvalentin/project0/issues/328)
  - **Decision:** no new ADR; implements the dashboard page decided in the telemetry map, closing the route

- **Slice:** [164 — Combat-outcome telemetry emission](slices/164-combat-outcome-telemetry.md) — **delivered; 6-event family live in server_main.gd, 111 scripts/811/811 tests on Linux, record-sync 0 errors, manual dump confirmed correct combat rows**
  - **Feature:** [F-038](FEATURE-LIST.md#f-038-cross-cutting-telemetry-pipeline-envelope-transport-storage-dashboard)
  - **Tech debt:** none identified
  - **Planning ticket:** [telemetry wayfinder map](https://github.com/vnvalentin/project0/issues/282) (decision [#286](https://github.com/vnvalentin/project0/issues/286)), [slice route](https://github.com/vnvalentin/project0/issues/328)
  - **Decision:** no new ADR; wires the combat-outcome family decided in the telemetry map into the live emission point established in Slice 163

- **Slice:** [163 — Connection-lifecycle telemetry emission](slices/163-connection-lifecycle-telemetry.md) — **delivered; 6-event family live in server_main.gd, 111 scripts/811/811 tests on Linux, record-sync 0 errors, manual e2e confirmed correct rows**
  - **Feature:** [F-038](FEATURE-LIST.md#f-038-cross-cutting-telemetry-pipeline-envelope-transport-storage-dashboard)
  - **Tech debt:** none identified
  - **Planning ticket:** [telemetry wayfinder map](https://github.com/vnvalentin/project0/issues/282) (decision [#285](https://github.com/vnvalentin/project0/issues/285)), [slice route](https://github.com/vnvalentin/project0/issues/328)
  - **Decision:** no new ADR; wires the connection-lifecycle family decided in the telemetry map into a live emission point

- **Slice:** [162 — Live telemetry RPC wiring](slices/162-telemetry-rpc-wiring.md) — **delivered; live RPC + boot-wired sink/limiter + ingest service, 111 scripts/811/811 tests on Linux, record-sync 0 errors**
  - **Feature:** [F-038](FEATURE-LIST.md#f-038-cross-cutting-telemetry-pipeline-envelope-transport-storage-dashboard)
  - **Tech debt:** none identified
  - **Planning ticket:** [telemetry wayfinder map](https://github.com/vnvalentin/project0/issues/282) (decision [#284](https://github.com/vnvalentin/project0/issues/284)), [slice route](https://github.com/vnvalentin/project0/issues/328)
  - **Decision:** no new ADR; wires Slice 161's contracts into the live client/server RPC path

- **Slice:** [161 — Telemetry transport contracts](slices/161-telemetry-transport-contracts.md) — **delivered; client batch queue + server rate limiter, 14/14 focused tests on Windows, full suite 805/805 on Linux, record-sync 0 errors**
  - **Feature:** [F-038](FEATURE-LIST.md#f-038-cross-cutting-telemetry-pipeline-envelope-transport-storage-dashboard)
  - **Tech debt:** none identified
  - **Planning ticket:** [telemetry wayfinder map](https://github.com/vnvalentin/project0/issues/282) (decision [#284](https://github.com/vnvalentin/project0/issues/284)), [slice route](https://github.com/vnvalentin/project0/issues/328)
  - **Decision:** no new ADR; mirrors the version-handshake contract-then-enforcement precedent (Slices 145/146)

- **Slice:** [160 — Telemetry sink + dedicated database](slices/160-telemetry-sink-database.md) — **delivered; server/telemetry_sink.gd schema+emit+retention, 108 scripts/791/791 tests on Linux, record-sync 0 errors**
  - **Feature:** [F-038](FEATURE-LIST.md#f-038-cross-cutting-telemetry-pipeline-envelope-transport-storage-dashboard)
  - **Tech debt:** none identified
  - **Planning ticket:** [telemetry wayfinder map](https://github.com/vnvalentin/project0/issues/282) (decisions [#287](https://github.com/vnvalentin/project0/issues/287), [#288](https://github.com/vnvalentin/project0/issues/288)), [slice route](https://github.com/vnvalentin/project0/issues/328)
  - **Decision:** no new ADR; implements the storage engine/schema/retention decided in the telemetry map

- **Slice:** [159 — Telemetry envelope + validation](slices/159-telemetry-envelope-validation.md) — **delivered; shared/telemetry_event.gd build/validate, 11/11 focused tests, full suite 785/785, record-sync 0 errors**
  - **Feature:** [F-038](FEATURE-LIST.md#f-038-cross-cutting-telemetry-pipeline-envelope-transport-storage-dashboard)
  - **Tech debt:** none identified
  - **Planning ticket:** [telemetry wayfinder map](https://github.com/vnvalentin/project0/issues/282) (decision [#283](https://github.com/vnvalentin/project0/issues/283)), [slice route](https://github.com/vnvalentin/project0/issues/328)
  - **Decision:** no new ADR; implements the envelope decided in the telemetry map

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

- **Slice:** [102 — Full-stack CI validation gate](slices/102-ci-validation-pipeline.md) — **delivered; workflow YAML parsed and every new job's command validated directly**
  - **Feature:** [F-005](FEATURE-LIST.md#f-005-automated-validation-gate-and-test-telemetry)
  - **Tech debt:** none identified
  - **Planning ticket:** [Full CI/CD pipeline for all servers and the client package](../.scratch/game-vision/map.md) (Delivery workflow / CI-CD)
  - **Decision:** no new ADR; extends the existing F-005 validation gate to the non-Godot components

- **Slice:** [103 — Linux-hosted Windows client package build](slices/103-linux-client-package-build.md) — **delivered; full cross-build executed on okami, artifacts and manifest verified**
  - **Feature:** [F-002](FEATURE-LIST.md#f-002-portable-windows-client-package)
  - **Tech debt:** [DT-011](TECHNICAL-DEBT-TRACKER.md#dt-011-client-export-filter-ships-the-test-framework-and-build-artifacts) raised
  - **Planning ticket:** [Full CI/CD pipeline for all servers and the client package](../.scratch/game-vision/map.md) (Delivery workflow / CI-CD)
  - **Decision:** no new ADR; makes the existing F-002 package reproducible from a clean checkout

- **Slice:** [111 — Dashboard issue traceability detail](slices/111-dashboard-issue-traceability-detail.md) — **delivered; `/detail` now shows GitHub Issue traceability totals, parent goal issues, child planning issues, missing slice links, and the new/unresearched status for goal folders without `map.md`; stale hardcoded delivery-roadmap prose removed from this screen**
  - **Feature:** [F-025](FEATURE-LIST.md#f-025-project-flow-visual-management-dashboard)
  - **GitHub issue:** #206
  - **Validation:** `python -m py_compile dashboard/app.py` exit 0; focused render check exit 0 with traceability heading, goal heading, hidden old roadmap, `zone-sharding` new/unresearched, `95/95` child count, and `15/15` goal count all true; `scripts/check_record_sync.sh` exit 0

- **Slice:** [112 — Reality page Goal source of truth](slices/112-reality-goal-source-of-truth.md) — **delivered; `/` now uses GitHub Issues as the visible source of truth by rendering only parent Goal issues, grouped with their child issue states and completion percentage**
  - **Feature:** [F-025](FEATURE-LIST.md#f-025-project-flow-visual-management-dashboard)
  - **GitHub issue:** #207
  - **Validation:** `python -m py_compile dashboard/app.py` exit 0; focused Reality render assertions exit 0 with exactly 15 goal cards, percent/open/closed child counts present, non-goal workflow issues absent, child issue cards absent, and the summary tile relabeled to open goal child issues; `scripts/check_record_sync.sh` exit 0

- **Slice:** [113 — Dashboard apps source layout](slices/113-dashboard-apps-source-layout.md) — **delivered; dashboard compose defaults to a dedicated `./repo` clone and the host-standard app directory is `/apps/project0/dashboard`, so the container no longer depends on a home-directory checkout or stale `/data/code/project0` mirror**
  - **Feature:** [F-025](FEATURE-LIST.md#f-025-project-flow-visual-management-dashboard)
  - **GitHub issue:** #211
  - **Validation:** `bash -n scripts/run_gut_validation.sh` exit 0; `python -m py_compile dashboard/app.py` exit 0; dashboard render checks passed locally; host rollout validated `/apps/project0/dashboard`, `/apps/project0/dashboard/repo`, `GET /`, `GET /detail`, and `GET /health`

- **Slice:** [114 — Goal target coverage cards](slices/114-goal-target-coverage-cards.md) — **delivered; Reality page Goal cards now show `Target coverage` as resolved child planning issues over total child issues, with GitHub closed/open child counts still visible separately**
  - **Feature:** [F-025](FEATURE-LIST.md#f-025-project-flow-visual-management-dashboard)
  - **GitHub issue:** #214
  - **Validation:** `python -m py_compile dashboard/app.py` exit 0; focused Reality render assertions exit 0 with 15 Goal cards, `Target coverage`, percent, open/closed labels, and nonzero coverage samples; `scripts/check_record_sync.sh` exit 0

- **Slice:** [115 — Goal What Good Looks Like criteria](slices/115-goal-good-looks-like-criteria.md) — **delivered; every researched `.scratch` goal map now has a customer-outcome WGL checklist, parent GitHub Goal issues were mirrored from those maps, and dashboard target coverage parses those criteria instead of treating child issue completion as goal closure**
  - **Features:** [F-025](FEATURE-LIST.md#f-025-project-flow-visual-management-dashboard), [P-004](FEATURE-LIST.md#p-004-agent-assisted-delivery-orchestration)
  - **GitHub issue:** #215
  - **Validation:** `python -m py_compile dashboard/app.py` exit 0; focused Reality render assertions exit 0 (`zone-sharding` 0%, `basic-monsters` 75%, `world-scale` 100%); parent Goal issue mirror updated 14 WGL maps with no failures; `scripts/check_record_sync.sh` exit 0

#### Phase 12 — Authoritative runtime and action input

- **Slice:** [166 — Nakama v1 deployment foundation](slices/166-nakama-v1-deployment-foundation.md) — **delivered; opt-in Nakama/PostgreSQL compose profile, private Console/admin posture, host-side secrets/config runbook, backup-before-migration rule, and static validation seam; Linux record-sync 0 errors and full GUT 811/811**
  - **Feature:** [F-039](FEATURE-LIST.md#f-039-nakama-v1-entry-and-realtime-foundation)
  - **GitHub issue:** [#355](https://github.com/vnvalentin/project0/issues/355)
  - **Planning ticket:** [Nakama v1 implementation Goal](https://github.com/vnvalentin/project0/issues/354), [Wayfinder map](https://github.com/vnvalentin/project0/issues/336)
  - **Decision:** no new ADR; implements the deployment posture decided in [#343](https://github.com/vnvalentin/project0/issues/343) without changing auth, Character, gameplay, or Canon authority.

- **Slice:** [167 — Nakama Godot auth and session entry](slices/167-nakama-godot-auth-session-entry.md) — **delivered; feature-flagged Godot Nakama HTTP auth/session seam, account-gate login/register path, NetworkConfig endpoint/key controls, and in-memory Nakama Account identity state; Linux record-sync 0 errors and full GUT 826/826 tests passed**
  - **Feature:** [F-039](FEATURE-LIST.md#f-039-nakama-v1-entry-and-realtime-foundation)
  - **GitHub issue:** [#356](https://github.com/vnvalentin/project0/issues/356)
  - **Planning ticket:** [Nakama v1 implementation Goal](https://github.com/vnvalentin/project0/issues/354), [Wayfinder map](https://github.com/vnvalentin/project0/issues/336)
  - **Decision:** no new ADR; implements the auth/session entry decided in [#340](https://github.com/vnvalentin/project0/issues/340) without moving Character, gameplay, or Canon authority.

- **Slice:** [168 — Project0 Character service keyed by Nakama user ID](slices/168-nakama-character-service.md) — **delivered; idempotent Nakama-user-id Account materialization with non-login PBKDF sentinels plus CharacterService Nakama session binding while preserving Project0-owned Character rules; okami validation passed 831 tests / 2585 asserts**
  - **Feature:** [F-039](FEATURE-LIST.md#f-039-nakama-v1-entry-and-realtime-foundation)
  - **GitHub issue:** [#357](https://github.com/vnvalentin/project0/issues/357)
  - **Planning ticket:** [Nakama v1 implementation Goal](https://github.com/vnvalentin/project0/issues/354), [Wayfinder map](https://github.com/vnvalentin/project0/issues/336)
  - **Decision:** no new ADR; extends the accepted Nakama Account boundary from [#340](https://github.com/vnvalentin/project0/issues/340) without moving world-entry or Canon authority.

- **Slice:** [169 — Project0 world-entry ticket contract for Nakama sessions](slices/169-nakama-world-entry-ticket.md) — **delivered; server-only selected-Character world-entry ticket issue/consume contract for Nakama-bound sessions with replay, expiry, wrong-audience, and invalidation coverage; okami validation passed 114 scripts / 836 tests / 2617 asserts**
  - **Feature:** [F-039](FEATURE-LIST.md#f-039-nakama-v1-entry-and-realtime-foundation)
  - **GitHub issue:** [#358](https://github.com/vnvalentin/project0/issues/358)
  - **Planning ticket:** [Nakama v1 implementation Goal](https://github.com/vnvalentin/project0/issues/354), [Wayfinder map](https://github.com/vnvalentin/project0/issues/336)
  - **Decision:** no new ADR; wraps the accepted assertion contract for Nakama world entry without changing gameplay or Canon authority.

- **Slice:** [170 — Nakama socket gameplay bridge protocol contract](slices/170-nakama-gameplay-bridge-protocol.md) — **delivered; transport-neutral identity-bound input/state/presence/error envelopes before live Nakama socket wiring; okami validation passed 115 scripts / 841 tests / 2633 asserts**
  - **Feature:** [F-039](FEATURE-LIST.md#f-039-nakama-v1-entry-and-realtime-foundation)
  - **GitHub issue:** [#359](https://github.com/vnvalentin/project0/issues/359)
  - **Planning ticket:** [Nakama v1 implementation Goal](https://github.com/vnvalentin/project0/issues/354), [Wayfinder map](https://github.com/vnvalentin/project0/issues/336)
  - **Decision:** no new ADR; defines the bridge contract without changing transport, simulation, Character, or Canon authority.

- **Slice:** [175 — Nakama Character and world-entry client path](slices/175-nakama-character-world-entry.md) — **delivered; presents the Nakama bearer session for server validation, then reuses existing Character CRUD and world-entry RPC seams; okami validation passed 117 scripts / 849 tests / 2645 asserts**
  - **Feature:** [F-039](FEATURE-LIST.md#f-039-nakama-v1-entry-and-realtime-foundation)
  - **GitHub issue:** [#371](https://github.com/vnvalentin/project0/issues/371)
  - **Planning ticket:** [Nakama v1 implementation Goal](https://github.com/vnvalentin/project0/issues/354), [Wayfinder map](https://github.com/vnvalentin/project0/issues/336)
  - **Decision:** no new ADR; reuses existing server-owned auth/Character/world-entry seams without trusting client identity.

- **Slice:** [173 — Server-side Nakama session validation seam](slices/173-nakama-session-validation.md) — **delivered; validates Nakama sessions server-side before binding identity into Project0 Character/session authority; okami validation passed 117 scripts / 849 tests / 2645 asserts**
  - **Feature:** [F-039](FEATURE-LIST.md#f-039-nakama-v1-entry-and-realtime-foundation)
  - **GitHub issue:** [#381](https://github.com/vnvalentin/project0/issues/381)
  - **Planning ticket:** [Nakama v1 implementation Goal](https://github.com/vnvalentin/project0/issues/354), [Wayfinder map](https://github.com/vnvalentin/project0/issues/336)
  - **Decision:** no new ADR; adds server-side Nakama validation without trusting client identity or changing Canon authority.

- **Slice:** [172 — Nakama v1 smoke and operations gate](slices/172-nakama-v1-smoke-ops-gate.md) — **delivered; manifest-backed static deployment validation and explicit bounded live Nakama health/API probing; okami validation passed 116 scripts / 844 tests / 2633 asserts**
  - **Feature:** [F-039](FEATURE-LIST.md#f-039-nakama-v1-entry-and-realtime-foundation)
  - **GitHub issue:** [#361](https://github.com/vnvalentin/project0/issues/361)
  - **Planning ticket:** [Nakama v1 implementation Goal](https://github.com/vnvalentin/project0/issues/354), [Wayfinder map](https://github.com/vnvalentin/project0/issues/336)
  - **Decision:** no new ADR; adds an operational gate without provisioning, secret exposure, or claims about unwired player flows.

- **Slice:** [171 — Default shared playtest world routing and presence](slices/171-nakama-shared-world-routing.md) — **delivered; one shared-world route and server-authored presence snapshots over the existing reliable RPC seam; okami validation passed 844 tests / 2633 asserts**
  - **Feature:** [F-039](FEATURE-LIST.md#f-039-nakama-v1-entry-and-realtime-foundation)
  - **GitHub issue:** [#360](https://github.com/vnvalentin/project0/issues/360)
  - **Planning ticket:** [Nakama v1 implementation Goal](https://github.com/vnvalentin/project0/issues/354), [Wayfinder map](https://github.com/vnvalentin/project0/issues/336)
  - **Decision:** no new ADR; implements shared-world/presence scope without automatic matchmaking or changing gameplay/Canon authority.

- **Slice:** [141 — Phase 12 (IP-015): second authoritative action kind — Heavy Strike](slices/141-heavy-strike-action.md) — **delivered; `shared/combat_contracts.gd` adds `ACTION_KIND_HEAVY_STRIKE` + a data-driven `HEAVY_GREATSWORD` archetype (windup 12, reach 3.0 yd, arc 120°, heavier locomotion, 3 targets) + `is_supported_action_kind`/`archetype_for_action`; `server/server_player_state.gd` accepts any supported kind and selects its archetype per swing, so the whole existing action machine + reach/arc test resolves both kinds — the server now resolves a bounded action set beyond the first melee seam. New `test_heavy_strike_action` 7/7; melee regression `test_melee_combat_contracts` 21/21 + integration `test_authoritative_melee_strike` 9/9 unchanged; full cumulative tree 712/712 across 97/97, exit 0 on the Linux host**
  - **Feature:** [IP-015](FEATURE-LIST.md#ip-015-authoritative-action-input)
  - **GitHub issue:** [#69](https://github.com/vnvalentin/project0/issues/69) (IP-015 continuation); design source melee-combat issue 03 ([#143](https://github.com/vnvalentin/project0/issues/143))
- **Slice:** [085 — Remove in-process login from the game server](slices/085-remove-game-in-process-login.md) — **delivered; server/login_runtime.gd build_assertion_only_services builds the game graph with NO AuthService (SessionRegistry + CharacterService + LoginGateway only); server/login_gateway.gd now holds a SessionRegistry directly for session ops with AuthService optional (additive third constructor arg — login process + all existing gateway/auth tests unchanged); server/server_main.gd uses the assertion-only builder, drops the PROJECT0_GAME_ASSERTION_ONLY opt-out + the AuthService handle, and clears sessions via the gateway; tests/integration/test_login_runtime.gd adds an assertion-only case (no auth, refuses accounts, accepts the assertion path) and test_login_assertion_handoff.gd wires its game side via the assertion-only builder; validated on Linux GUT 58/58, boot logs "assertion-only game server", scripts/test_login_handoff_e2e.gd ALL PASS (world entry "Handoff Hero") with the game process building no AuthService**
- **Slice:** [084 — Login-split cutover: split on by default](slices/084-login-split-cutover.md) — **delivered; the login split is now the canonical topology — shared/network_config.gd client_login_split_enabled() defaults ON (PROJECT0_CLIENT_LOGIN_SPLIT=0 selects the legacy single-connection flow) and server/server_main.gd runs the game server assertion-only by default (PROJECT0_GAME_ASSERTION_ONLY=0 re-enables in-process login for a combined single-process run); tests/unit/test_network_config_client_split.gd updated for the new default; safe now because nothing is deployed and no client is configured; validated on Linux GUT 58/58, headless boot logs assertion-only mode: true by default / false with =0, and scripts/test_login_handoff_e2e.gd ALL PASS with the new default (world_entry ok, bound Player "Handoff Hero")**
- **Slice:** [083 — One-command split launcher with shared-secret management](slices/083-split-launcher-shared-secret.md) — **delivered; deploy/game-server/run-split.sh (`up`/`down`) requires-or-generates a shared PROJECT0_ASSERTION_SECRET — the piece a bare `docker compose up` cannot manage safely (mismatched ephemeral keys silently break the handoff) — then brings up the base + split overlay under the login-split profile and waits for both containers healthy; deliberately changes no code env-var default so single-process source-run dev and the tester guide keep working; proven on Linux: `run-split.sh up` generated a secret and reached both-healthy (exit 0), the handoff harness reported world_entry: ok ("Handoff Hero"), `run-split.sh down` cleaned up; GUT 58/58 unaffected**
- **Slice:** [082 — Containerized login-split e2e (compose split overlay + two-container handoff)](slices/082-containerized-login-split-e2e.md) — **delivered; deploy/game-server/docker-compose.split.yml sets PROJECT0_GAME_ASSERTION_ONLY=1 on the game server so `-f docker-compose.yml -f docker-compose.split.yml --profile login-split up` runs the split topology (game accounts-disabled beside the login container, both sharing PROJECT0_ASSERTION_SECRET); default `docker compose up` unchanged; validated on Linux via compose config and a real two-container run — both healthy (~10s), game logged assertion-only mode: true, and scripts/login_handoff_client_harness.gd against the published ports (login 19998, game 19999) reported world_entry: ok / "Handoff Hero" (register+select on the login container, world entry on the assertion-only game container); GUT 58/58 unaffected**
- **Slice:** [081 — Deploy the standalone login server via docker-compose (opt-in profile)](slices/081-deploy-login-server-compose.md) — **delivered; deploy/game-server/docker-compose.yml gains a `login-server` service gated behind the `login-split` profile that reuses the game-server image and overrides the entrypoint to run server/login_server_main.gd on its own UDP port (19998→9998), accounts DB, and health file, plus a PROJECT0_ASSERTION_SECRET passthrough (empty default) on both services so the split shares one secret; the default `docker compose up` topology is unchanged; validated on Linux via docker compose config (default = game-server only; login-split adds login-server with the correct entrypoint/port/env) and a real container run that reached Docker health `healthy` in ~10s (Login server listening, health file status healthy), GUT 58/58 unaffected**
- **Slice:** [080 — One-time Canon migration into a dedicated store on first split boot](slices/080-canon-migration-on-split-boot.md) — **delivered; server/canon_repository.gd list_all_records (verbatim rows oldest-first) + restore_record (insert preserving created_at, validate, idempotent/conflict); server/server_main.gd copies all Canon from the accounts store into a newly-empty dedicated canon store before canonicalizing the town, only when a dedicated store is selected and empty (source read-only, re-boot skips); tests/integration/test_canon_store_split.gd adds created_at-preservation + source-intact, idempotency, and conflict cases; validated GUT 58/58 + a three-boot runtime check on Linux (shared seed → Migrated 1 Canon sector then idempotent town → re-boot skips)**
- **Slice:** [079 — Optional dedicated Canon store (opt-in canon/accounts DB split)](slices/079-optional-dedicated-canon-store.md) — **delivered; server/server_main.gd opens a dedicated Canon SqliteStore at PROJECT0_CANON_DB_PATH when set (fail-closed on open failure) and backs CanonRepository with it; unset keeps the Slice 045 shared accounts handle so existing combined deployments are untouched (no migration, no data movement); tests/integration/test_canon_store_split.gd proves canon lands only in the canon store and accounts only in the accounts store, while the shared default colocates both; validated GUT 58/58 + headless boot on Linux (split logs canon db: split_canon.db with both files created; unset logs shared:shared_acc.db)**
- **Slice:** [078 — Wire login-screen gates to the login process (opt-in)](slices/078-wire-gates-to-login-process.md) — **delivered; shared/network_config.gd client_login_split_enabled() (PROJECT0_CLIENT_LOGIN_SPLIT=1, default off); client/account_gate.gd connects to the login port when the split is enabled; client/character_gate.gd calls perform_login_to_game_handoff on select and reports handoff failures while success flows through the existing world_entry transition; validated GUT 57/57 + client UI smoke passed on Linux, seam already proven e2e by 077**
- **Slice:** [077 — Client login→game handoff seam](slices/077-client-login-handoff-seam.md) — **delivered; client/network_client.gd perform_login_to_game_handoff(game_host, game_port) — poll-based, bounded coroutine that requests a signed assertion, hands off to the game process (disconnect -> connect -> present -> enter world), emitting login_to_game_handoff_finished; the e2e harness drives Phase 2 through the production seam (ALL PASS on Linux, world_entry==ok as Handoff Hero); GUT 56/56 unaffected; reusable by the login-screen scenes (wired in 078)**
  - **Feature:** [P-014](FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime) (login-boundary decision: reusable client cutover seam)
  - **Public seam:** `client/network_client.gd` (`perform_login_to_game_handoff`, `login_to_game_handoff_finished`)
  - **Planning ticket:** [login-boundary decision](../.scratch/container-platform/issues/02-account-login-service-boundary.md)
  - **Decision:** no new ADR; reuses the enrollment revocation seam behind the audited job model; body-based key (base64 not path-safe)

- **Slice:** [063 — Operator control plane: audited mint-invite action](slices/063-operator-mint-invite-action.md) — **delivered; POST /invites reuses the enrollment store to mint a single-use invite as an audited job; secret code in the response only, never audited; 32 operator pytest tests; GUT unaffected**
  - **Feature:** [P-014](FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime) (operator control-plane decision: reuse the enrollment invite seam through the job/audit model)
  - **Public seam:** `infra/operator/invites.py`, `infra/operator/operations.py` (`mint_invite`), `infra/operator/app.py` (`POST /invites`)
  - **Planning ticket:** [operator control-plane decision](../.scratch/container-platform/issues/04-operator-control-plane-and-telemetry.md)
  - **Decision:** no new ADR; reuses the enrollment invite seam behind the audited job model; secret-redaction invariant enforced by test

- **Slice:** [062 — Operator control plane: job/audit model + service restart action](slices/062-operator-restart-action.md) — **delivered; audited restart job lifecycle + GET /jobs; allowlisted, token-authed, fail-closed; 24 operator pytest tests; GUT unaffected**
  - **Feature:** [P-014](FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime) (operator control-plane decision: first mutating action behind the job/audit model)
  - **Public seam:** `infra/operator/jobs.py`, `infra/operator/control.py`, `infra/operator/operations.py`, `infra/operator/app.py` (`POST /services/{name}/restart`, `GET /jobs`)
  - **Planning ticket:** [operator control-plane decision](../.scratch/container-platform/issues/04-operator-control-plane-and-telemetry.md)
  - **Decision:** no new ADR; implements the accepted decision's job lifecycle + audit + allowlisting; live systemd-restart privilege is an ops prerequisite (validated against a fake controller)

- **Slice:** [061 — Operator control plane: read-only status service](slices/061-operator-status-service.md) — **delivered; private, operator-token-authed FastAPI status service (allowlisted systemd/docker inspector, loopback-only, no mutation); 13 pytest tests + enrollment unregressed (68 total); GUT unaffected**
  - **Feature:** [P-014](FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime) (operator control-plane decision: read-only foundation)
  - **Public seam:** `infra/operator/` (`config.py`, `services.py`, `app.py`, `asgi.py`, `project0-operator.service`)
  - **Planning ticket:** [operator control-plane decision](../.scratch/container-platform/issues/04-operator-control-plane-and-telemetry.md)
  - **Decision:** no new ADR; implements the accepted operator control-plane decision (private, allowlisted, token-authed); Python-only, pytest-validated

- **Slice:** [060 — Assertion-backed session establishment in the login gateway](slices/060-assertion-session-binding.md) — **delivered; issue/establish session assertions wired into the gateway (Slice 059 seams); additive, e2e green; GUT 359/359 across 49/49**
  - **Feature:** [P-014](FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime) (login-boundary decision: the assertion mechanism the game server uses to trust the login authority)
  - **Public seam:** `server/login_gateway.gd` (`set_assertion_seams`, `issue_account_assertion`, `issue_character_assertion`, `establish_session_from_assertion`); `server/server_main.gd` (issuer/validator construction from `PROJECT0_ASSERTION_SECRET`)
  - **Planning ticket:** [login-boundary decision](../.scratch/container-platform/issues/02-account-login-service-boundary.md)
  - **Decision:** no new ADR; implements the accepted login-boundary assertion mechanism (HMAC shared-secret per Slice 059)

- **Slice:** [059 — Signed session assertion contract, issuer, and validator](slices/059-session-assertions.md) — **delivered; shared `SessionAssertion` + server-only HMAC-SHA256 issuer/validator; full rejection matrix tested; GUT 352/352 across 48/48; no wiring/behavior change yet**
  - **Feature:** [P-014](FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime) (login-boundary decision: the signed assertion the game server validates)
  - **Public seam:** `shared/session_assertion.gd` (`SessionAssertion`); `server/assertion_issuer.gd` (`AssertionIssuer`); `server/assertion_validator.gd` (`AssertionValidator`)
  - **Planning ticket:** [login-boundary decision](../.scratch/container-platform/issues/02-account-login-service-boundary.md)
  - **Decision:** no new ADR; HMAC-SHA256 shared-secret assertions at the home-hosted trust level, consistent with the existing Crypto usage

- **Slice:** [058 — In-process login gateway seam over AuthService/CharacterService](slices/058-login-gateway-seam.md) — **delivered; single `/root/LoginGateway` facade (pure delegation), RPC dispatch rerouted through it; GUT 330/330 across 46/46, e2e harnesses green; no behavior change**
  - **Feature:** [P-014](FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime) (login-boundary decision step 1: extract the login interface)
  - **Public seam:** `server/login_gateway.gd` (`LoginGateway`); `server/server_main.gd` (`/root/LoginGateway`); `client/network_client.gd` login/character/enter-world RPC receivers
  - **Planning ticket:** [login-boundary decision](../.scratch/container-platform/issues/02-account-login-service-boundary.md)
  - **Decision:** no new ADR; implements the accepted login-boundary decision without deviation

- **Slice:** [057 — Game-server persistent data boundary and SQLite backup/restore](slices/057-game-server-persistence-boundary.md) — **delivered; host-persistent data under /var/lib/project0, durability across container replacement, consistent SQLite backup/restore, native untouched**
  - **Feature:** [P-014](FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime) (persistence boundary; login/game DB split lands with the login-service extraction)
  - **Public seam:** `deploy/game-server/docker-compose.yml` (host bind mounts), `deploy/game-server/Dockerfile` (sqlite3), `deploy/game-server/backup.sh`, `deploy/game-server/restore.sh`
  - **Planning ticket:** [persistence decision](../.scratch/container-platform/issues/03-persistence-and-data-ownership.md)
  - **Decision:** no new ADR; implements the accepted persistence decision (`/var/lib/project0`, `/var/backups/project0`, consistent backup)

- **Slice:** [056 — Game-server container image and run-beside-native](slices/056-game-server-container-image.md) — **delivered; OCI image builds and boots the authoritative server headless beside the native server on an isolated port; healthy; graceful SIGTERM stop; native service untouched**
  - **Feature:** [P-014](FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime) (container image; runtime cutover remains later work)
  - **Public seam:** `deploy/game-server/` (Dockerfile, entrypoint.sh, docker-compose.yml), repo `.dockerignore`/`.gitattributes`
  - **Planning ticket:** [container-platform map](../.scratch/container-platform/map.md), [runtime-boundary decision](../.scratch/container-platform/issues/01-runtime-boundary-and-container-adapter.md)
  - **Decision:** no new ADR; implements the accepted runtime-boundary decision (OCI, systemd supervision, `/apps/project0`, `/var/lib/project0`, UDP 9999, non-root)

- **Slice:** [055 — Server fixed-tick and health snapshot contract](slices/055-server-fixed-tick-and-health-contract.md) — **delivered; pure, server-only `ServerHealth` contract seam; authoritative Linux gate 326/326 across 45/45 scripts, exit 0; record sync exit 0**
  - **Feature:** [P-014](FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime) (first foundation slice; the container runtime itself remains later work)
  - **Public seam:** `server/server_health.gd` (`resolve_tick_rate`, `build_snapshot`, bounded 20-30 Hz tick, versioned fail-closed health snapshot)
  - **Planning ticket:** [container-platform map](../.scratch/container-platform/map.md), [runtime-boundary decision](../.scratch/container-platform/issues/01-runtime-boundary-and-container-adapter.md)
  - **Decision:** no new ADR; implements CLAUDE.md Runtime Ownership and the accepted runtime-boundary decision

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
  - **Planning ticket:** [player-accounts issue 03](../.scratch/player-accounts/issues/03-research-godot-persistence-sqlite.md), [player-accounts issue 06](../.scratch/player-accounts/issues/06-account-character-persistence-design.md) (the persistence-mechanism decision was made in the player-accounts design track; this slice is Wave 4, the shared build-once foundation both Phase 9 Canon and Phase 10 accounts consume)
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
- **Slice:** [095 — Canon entity GUIDs + mutation target-existence enforcement](slices/095-canon-entity-guids.md) — **delivered; stable, restart-safe entity identity + fail-closed target existence check**
  - **Feature:** [P-013](FEATURE-LIST.md#p-013-dynamic-world-mutation-tracking) (second slice)
  - **Tech debt:** none identified
  - **Planning ticket:** [Canon persistence issue](../.scratch/game-vision/issues/05-define-canon-persistence.md)
  - **Public seam:** `shared/canon_entity_guid.gd` (pure, deterministic SHA-256 identity for structures + spawn points) consumed by `server/canon_mutation_repository.gd` (`apply_mutation` rejects a `target_not_found` mutation before any write); no RPC, replay, or gameplay-authorization code
  - **Validation:** full GUT on the Linux host passed 462/462 tests across 68/68 scripts, exit 0 (up from 453/67); `scripts/check_record_sync.sh` passed with 0 errors and 6 pre-existing warnings
- **Slice:** [096 — Canon mutation intent DTO + server-authoritative resolution service](slices/096-canon-mutation-intent-service.md) — **delivered; server-authoritative intent→event resolution seam**
  - **Feature:** [P-013](FEATURE-LIST.md#p-013-dynamic-world-mutation-tracking) (third slice)
  - **Tech debt:** none identified
  - **Planning ticket:** [Canon persistence issue](../.scratch/game-vision/issues/05-define-canon-persistence.md)
  - **Public seam:** `shared/canon_mutation_intent.gd` (pure client→server intent contract) + `server/canon_mutation_service.gd` (`resolve_intent` stamps server-owned actor/event_id/tick, applies via `server/canon_mutation_repository.gd`); the `@rpc` transport + headless e2e are Slice 097
  - **Validation:** full GUT on the Linux host passed 482/482 tests across 70/70 scripts, exit 0 (up from 462/68); `scripts/check_record_sync.sh` passed with 0 errors and 6 pre-existing warnings
- **Slice:** [097 — Canon mutation intent RPC transport + headless round-trip e2e](slices/097-canon-mutation-rpc-transport.md) — **delivered; mutation intent on the wire + live repository/service in `server_main`**
  - **Feature:** [P-013](FEATURE-LIST.md#p-013-dynamic-world-mutation-tracking) (fourth slice)
  - **Tech debt:** none identified
  - **Planning ticket:** [Canon persistence issue](../.scratch/game-vision/issues/05-define-canon-persistence.md)
  - **Public seam:** `client/network_client.gd` (`submit_canon_mutation_intent` + the two `@rpc` relays) + `server/server_main.gd` (live `CanonMutationRepository`/`CanonMutationService`, resolves per authenticated peer); runtime-proven by `scripts/test_canon_mutation_rpc_e2e.gd`
  - **Validation:** full GUT on the Linux host passed 482/482 tests across 70/70 scripts, exit 0; `scripts/test_canon_mutation_rpc_e2e.gd` printed ALL PASS (real ENet round-trip); `scripts/check_record_sync.sh` passed with 0 errors and 6 pre-existing warnings
- **Slice:** [098 — Canon sector mutation replay: server replicates the effective blueprint](slices/098-canon-sector-mutation-replay.md) — **delivered; server-authoritative replay of the mutation log into the replicated sector**
  - **Feature:** [P-013](FEATURE-LIST.md#p-013-dynamic-world-mutation-tracking) (fifth slice)
  - **Tech debt:** none identified
  - **Planning ticket:** [Canon persistence issue](../.scratch/game-vision/issues/05-define-canon-persistence.md)
  - **Public seam:** `shared/canon_sector_resolver.gd` (`resolve_effective_blueprint`) consumed by `server/server_main.gd` (`_effective_blueprint_for`, applied at both sector-replication points); no client change, no RPC signature change
  - **Validation:** full GUT on the Linux host passed 493/493 tests across 72/72 scripts, exit 0 (up from 482/70); the melee e2e printed ALL PASS (effective-blueprint replication path renders the hub); `scripts/check_record_sync.sh` passed with 0 errors and 6 pre-existing warnings

#### Phase 11 — Public game access

- **Slice:** [100 — Public HTTPS account registration](slices/100-public-account-registration.md) — **delivered; registration/login pytest 8/8 and full enrollment pytest 120/120 passed**
  - **Feature/debt:** [P-024](FEATURE-LIST.md#p-024-public-game-access-via-opnsense-native-wireguard), resolved [DT-010](TECHNICAL-DEBT-TRACKER.md#dt-010-no-public-https-account-registration-surface-for-the-wan-client)

- **Slice:** [099 — Public authentication abuse controls](slices/099-public-auth-abuse-controls.md) — **delivered; focused pytest 7/7 and full enrollment pytest 119/119 passed**
  - **Feature/debt:** [P-024](FEATURE-LIST.md#p-024-public-game-access-via-opnsense-native-wireguard), resolved [DT-009](TECHNICAL-DEBT-TRACKER.md#dt-009-public-login-on-the-enrollment-service-has-no-rate-limiting-lockout-or-anti-enumeration)

- **Slice:** [092 — Auth-gated onboarding C-launcher: Windows launcher login + redeem-with-assertion + tunnel bring-up](slices/092-launcher-login-redeem-assertion.md) — **delivered; validated on Windows via `go test ./native/windows_launcher/` (12/12, up from 6). Live WAN tunnel bring-up user-pending.**   - **Feature:** [F-035](FEATURE-LIST.md#f-035-secure-windows-tunnel-enrollment-and-credential-storage), under [P-024](FEATURE-LIST.md#p-024-public-game-access-via-opnsense-native-wireguard)   - **Planning ticket:** [ADR 0004](adr/0004-auth-gated-tunnel-provisioning.md), [SLICE-REGISTRY.md](slices/SLICE-REGISTRY.md) (092)   - **Decision:** implements [ADR 0004](adr/0004-auth-gated-tunnel-provisioning.md) self-service provisioning at the launcher; no new ADR
- **Slice:** [093 — Auth-gated onboarding C-client-wiring: wire account/character gates to HTTPS + tunnel](slices/093-client-https-login-wiring.md) — **delivered; validated on the Linux host in an isolated git worktree of commit 230cd06 (GUT 436/436 across 64/64 scripts, exit 0). Live WAN client runtime run user-pending.**
  - **Feature:** [P-024](FEATURE-LIST.md#p-024-public-game-access-via-opnsense-native-wireguard)
  - **Tech debt:** `open` [DT-010](TECHNICAL-DEBT-TRACKER.md#dt-010-no-public-https-account-registration-surface-for-the-wan-client) — no public HTTPS `/register` surface yet; register disabled in WAN mode
  - **Planning ticket:** [ADR 0005](adr/0005-character-selection-over-https.md), [SLICE-REGISTRY.md](slices/SLICE-REGISTRY.md) (093)
  - **Decision:** implements [ADR 0005](adr/0005-character-selection-over-https.md) (Option A), client UI/tunnel wiring; no new ADR
- **Slice:** [091 — Auth-gated onboarding C-client-seam: Godot `EnrollmentHttpClient`](slices/091-client-https-auth-character-seam.md) — **delivered; validated on the Linux host (GUT 432/432 across 63/63 scripts, exit 0, two consecutive runs)**
  - **Feature:** [P-024](FEATURE-LIST.md#p-024-public-game-access-via-opnsense-native-wireguard)
  - **Planning ticket:** [ADR 0005](adr/0005-character-selection-over-https.md), [SLICE-REGISTRY.md](slices/SLICE-REGISTRY.md) (091; 092 launcher, 093 client UI/tunnel wiring)
  - **Decision:** implements [ADR 0005](adr/0005-character-selection-over-https.md) (Option A), client-consumer seam; no new ADR
- **Slice:** [090 — Auth-gated onboarding C-server: HTTPS character endpoints](slices/090-https-character-endpoints.md) — **delivered; validated on the Linux host in an isolated git worktree of commit 362387f (GUT 423/423, enrollment pytest 112/112)**
  - **Feature:** [P-024](FEATURE-LIST.md#p-024-public-game-access-via-opnsense-native-wireguard)
  - **Tech debt:** `open` [DT-009](TECHNICAL-DEBT-TRACKER.md#dt-009-public-login-on-the-enrollment-service-has-no-rate-limiting-lockout-or-anti-enumeration) — widened to the new public character surface (restated, not re-opened)
  - **Planning ticket:** [ADR 0005](adr/0005-character-selection-over-https.md), [SLICE-REGISTRY.md](slices/SLICE-REGISTRY.md) (090, first of the Option-A 090–092 arc)
  - **Decision:** implements [ADR 0005](adr/0005-character-selection-over-https.md) (Option A)
- **Slice:** [089 — Auth-gated onboarding B: `/redeem` signed-assertion + idempotent per-account peer lifecycle](slices/089-auth-gated-onboarding-peer-provisioning.md) — **delivered; validated on the Linux host in an isolated git worktree of commit 65ccc54 (GUT 420/420, enrollment pytest 96/96)**
  - **Feature:** [P-024](FEATURE-LIST.md#p-024-public-game-access-via-opnsense-native-wireguard)
  - **Tech debt:** `open` [DT-009](TECHNICAL-DEBT-TRACKER.md#dt-009-public-login-on-the-enrollment-service-has-no-rate-limiting-lockout-or-anti-enumeration) — restated, not re-opened (public-`/login` rate-limiting)
  - **Planning ticket:** [ADR 0004](adr/0004-auth-gated-tunnel-provisioning.md), [SLICE-REGISTRY.md](slices/SLICE-REGISTRY.md) (089, second of the 088–090 ADR 0004 follow-up sequence)
  - **Decision:** implements [ADR 0004](adr/0004-auth-gated-tunnel-provisioning.md) follow-up (B), sub-decision 3; no new ADR
- **Slice:** [088 — Auth-gated onboarding A: HTTPS /login delegation](slices/088-auth-gated-onboarding-login-delegation.md) — **delivered; validated on the Linux host in an isolated git worktree of commit d732ff6**
  - **Feature:** [P-024](FEATURE-LIST.md#p-024-public-game-access-via-opnsense-native-wireguard)
  - **Tech debt:** `open` [DT-009](TECHNICAL-DEBT-TRACKER.md#dt-009-public-login-on-the-enrollment-service-has-no-rate-limiting-lockout-or-anti-enumeration) — public-`/login` rate-limiting/anti-enumeration filed as a named, tracked liability (not silently deferred)
  - **Planning ticket:** [ADR 0004](adr/0004-auth-gated-tunnel-provisioning.md), [SLICE-REGISTRY.md](slices/SLICE-REGISTRY.md) (088, first of the 088–090 ADR 0004 follow-up sequence)
  - **Decision:** implements [ADR 0004](adr/0004-auth-gated-tunnel-provisioning.md) follow-up (A); no new ADR
  - **Public seam:** `server/login_loopback_http_endpoint.gd` (`LoginLoopbackHttpEndpoint`, wired from `server/login_server_main.gd`), `shared/network_config.gd`'s `resolve_login_http_port()`, `infra/enrollment/login_client.py` (`LoginAuthorityClient`/`RealLoginAuthorityClient`), and `infra/enrollment/app.py`'s `POST /login`
  - **Validation:** `GODOT_BIN=godot bash scripts/run_gut_validation.sh` on the Linux host — `validation-summary.json` status `passed`, exit 0, scripts_expected/ran 62/62, Run Summary 415 tests, 415 passing, 1511 asserts, 0 failing (includes the new `tests/integration/test_login_loopback_http_endpoint.gd`); `.venv-enrollment/bin/python -m pytest infra/enrollment/tests -q` on the Linux host — 70 passed, exit 0, also reproduced on Windows (70 passed, exit 0). Two defects caught before merge and fixed — see the slice record's Root-cause learning section.
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

#### Phase 10 — Player accounts and characters

- **Slice:** [087 — Login-session resume (in-world Character Select without re-login)](slices/087-login-session-resume.md) — **delivered; the login→game handoff also fetches a bounded account resume token (server-owned `PROJECT0_RESUME_TTL_SECONDS`, default 1h, clamped), and `NetworkClient.perform_return_to_character_select` re-establishes a login session from it so the in-world Character Select button returns to the roster without re-login (falling back to the login screen on expiry); GUT 407/407 across 60 scripts + login-handoff e2e ALL PASS on Linux; Windows GUI confirmed**
  - **Feature:** [F-034](FEATURE-LIST.md#f-034-client-login-and-character-selection-screens) (extends the [P-014](FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime) assertion mechanism)
  - **Planning ticket:** [login-boundary decision](../.scratch/container-platform/issues/02-account-login-service-boundary.md)
  - **Decision:** no new ADR; reuses the accepted HMAC assertion seams (`issue_account_assertion`, `establish_session_from_assertion`) with a bounded resume TTL

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
- **Slice:** [044 — Client login and character selection UI](slices/044-client-login-character-ui.md) — **delivered; server validation and Windows GUI lifecycle confirmed**
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

- [x] Delivered — Telemetry envelope + validation (Phase 13,
  [F-038](FEATURE-LIST.md#f-038-cross-cutting-telemetry-pipeline-envelope-transport-storage-dashboard),
  [Slice 159](slices/159-telemetry-envelope-validation.md),
  [#329](https://github.com/vnvalentin/project0/issues/329)):
  `shared/telemetry_event.gd` provides the shared envelope and validation
  contract per the telemetry map's decisions
  ([#282](https://github.com/vnvalentin/project0/issues/282),
  [#283](https://github.com/vnvalentin/project0/issues/283)).
- [x] Delivered — Telemetry sink + dedicated database (Phase 13,
  [F-038](FEATURE-LIST.md#f-038-cross-cutting-telemetry-pipeline-envelope-transport-storage-dashboard),
  [Slice 160](slices/160-telemetry-sink-database.md),
  [#332](https://github.com/vnvalentin/project0/issues/332)):
  `server/telemetry_sink.gd` provides the `telemetry.db` schema, validated
  writes, and retention/row-ceiling enforcement per decisions
  [#287](https://github.com/vnvalentin/project0/issues/287)/[#288](https://github.com/vnvalentin/project0/issues/288).
- [x] Delivered — Telemetry transport contracts (Phase 13,
  [F-038](FEATURE-LIST.md#f-038-cross-cutting-telemetry-pipeline-envelope-transport-storage-dashboard),
  [Slice 161](slices/161-telemetry-transport-contracts.md),
  [#334](https://github.com/vnvalentin/project0/issues/334)):
  `client/telemetry_batch_queue.gd` + `server/telemetry_rate_limiter.gd`
  implement the batching/rate-limiting shape decided in
  [#284](https://github.com/vnvalentin/project0/issues/284); RPC/scene-tree
  wiring is a follow-up slice.
- [x] Delivered — Live telemetry RPC wiring (Phase 13,
  [F-038](FEATURE-LIST.md#f-038-cross-cutting-telemetry-pipeline-envelope-transport-storage-dashboard),
  [Slice 162](slices/162-telemetry-rpc-wiring.md),
  [#345](https://github.com/vnvalentin/project0/issues/345)): the live
  `receive_client_telemetry_batch_on_server` RPC, boot-wired sink/rate
  limiter, and `server/telemetry_ingest_service.gd`'s untrusted-input-safe
  ingest orchestration.
- [x] Delivered — Connection-lifecycle telemetry emission (Phase 13,
  [F-038](FEATURE-LIST.md#f-038-cross-cutting-telemetry-pipeline-envelope-transport-storage-dashboard),
  [Slice 163](slices/163-connection-lifecycle-telemetry.md),
  [#347](https://github.com/vnvalentin/project0/issues/347)): the 6-event
  connection-lifecycle family from
  [#285](https://github.com/vnvalentin/project0/issues/285) is live in
  `server_main.gd`, superseding its matching `print()` sites.
- [x] Delivered — Combat-outcome telemetry emission (Phase 13,
  [F-038](FEATURE-LIST.md#f-038-cross-cutting-telemetry-pipeline-envelope-transport-storage-dashboard),
  [Slice 164](slices/164-combat-outcome-telemetry.md),
  [#351](https://github.com/vnvalentin/project0/issues/351)): the 6-event
  combat-outcome family from
  [#286](https://github.com/vnvalentin/project0/issues/286) is live in
  `server_main.gd`, superseding its matching `print()` sites.
- [x] Delivered — Dashboard telemetry page (Phase 13,
  [F-038](FEATURE-LIST.md#f-038-cross-cutting-telemetry-pipeline-envelope-transport-storage-dashboard),
  [Slice 165](slices/165-dashboard-telemetry-page.md),
  [#353](https://github.com/vnvalentin/project0/issues/353)): the
  `/telemetry` page in `dashboard/app.py`, decided in
  [#290](https://github.com/vnvalentin/project0/issues/290), closes out the
  telemetry pipeline's original route ([#328](https://github.com/vnvalentin/project0/issues/328)).
  Remaining fog (client-UI taxonomy, network-quality stats, andon
  thresholds, login/auth family, rollup) stays unticketed until the map is
  redrawn.
- [x] Delivered — Nakama v1 deployment foundation (Phase 12,
  [F-039](FEATURE-LIST.md#f-039-nakama-v1-entry-and-realtime-foundation),
  [Slice 166](slices/166-nakama-v1-deployment-foundation.md),
  [#355](https://github.com/vnvalentin/project0/issues/355)): optional
  Nakama/PostgreSQL compose profile, private Console/admin posture,
  host-side secrets/config runbook, backup-before-migration rule, and static
  validation foundation.

- [x] Delivered — Phase 14 unified Character foundation ([F-036](FEATURE-LIST.md#f-036-phase-14-unified-character-and-npc-generalization),
  [Slice 116](slices/116-phase14-character-foundation-handoff.md),
  [#227](https://github.com/vnvalentin/project0/issues/227)); the shared
  `CharacterFoundation` contract is implemented and GUT-validated. Equipment,
  techniques, movement, combat, disposition, and spawning remain as follow-up
  slices under F-036.

- [x] Done — Public-authentication abuse controls (Phase 11,
  [DT-009](TECHNICAL-DEBT-TRACKER.md#dt-009-public-login-on-the-enrollment-service-has-no-rate-limiting-lockout-or-anti-enumeration)):
  [Slice 099](slices/099-public-auth-abuse-controls.md) implements bounded
  rate limiting, lockout, and anti-enumeration for public `/login` and
  `/characters/*`.
- [x] Done — Public HTTPS account registration (Phase 11,
  [DT-010](TECHNICAL-DEBT-TRACKER.md#dt-010-no-public-https-account-registration-surface-for-the-wan-client)):
  [Slice 100](slices/100-public-account-registration.md) loopback-delegates
  registration to the login authority, applies DT-009 controls, and re-enables
  the WAN registration path.
- [x] Done — Auth-gated real-WAN onboarding (Phase 11,
  [P-024](FEATURE-LIST.md#p-024-public-game-access-via-opnsense-native-wireguard)):
  the six checks in the [F-035 runbook](f035-secure-launcher-validation-runbook.md)
  passed from a real off-LAN Windows client on 2026-09-16.
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
- [x] Done — Canon persistence (Phase 9): the durable sector and
  canonicalization seam is delivered (Slices 045/047) on the shared engine
  ([Slice 038](slices/038-shared-sqlite-persistence-foundation.md), F-029 —
  `server/sqlite_store.gd`), and the first mutation slice landed (Slice 050 —
  `server/canon_mutation_repository.gd`: append-only, idempotent, optimistic
  per-sector revision), so
  [P-011](FEATURE-LIST.md#p-011-canonical-history-archive) and
  [P-012](FEATURE-LIST.md#p-012-one-time-blueprint-canonicalization) are
  `Implemented` and [P-013](FEATURE-LIST.md#p-013-dynamic-world-mutation-tracking)
  is `Implemented`. Slices 095-098 delivered stable server-owned entity GUIDs
  (`shared/canon_entity_guid.gd`) and target-existence enforcement in
  `apply_mutation`. Remaining P-013 work (physical-event verification, actor
  authorization, and non-geometry mutation kinds like loot/defeat_leader) and
  the JIT boundary path continue as follow-up slices, resolving the open
  event-model questions in
  [game-vision issue 05](../.scratch/game-vision/issues/05-define-canon-persistence.md).
- [ ] Queued — Containerized fixed-tick server runtime (Phase 12, in progress):
  [P-014](FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)
  is now `in-progress` — its runtime boundary is decided by the
  [container-platform map](../.scratch/container-platform/map.md) and
  [Slice 055](slices/055-server-fixed-tick-and-health-contract.md) delivered the
  bounded fixed-tick + fail-closed health contract foundation. Remaining P-014
  work: the container image under `/apps/project0`, tick-loop wiring, and
  run-beside-native equivalence per the migration decision.
- [~] In progress — Server deployment path (Phase 12, [P-014](FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)):
  [Slice 101](slices/101-server-deployment-pipeline.md) adds an opt-in
  commit-archive deployment path with native, Docker candidate, and Docker
  split modes. Ordinary client builds remain client-only.
- [x] Done — Full CI/CD pipeline (Phase 13 + Phase 12): [Slice 102](slices/102-ci-validation-pipeline.md)
  expands the [F-005](FEATURE-LIST.md#f-005-automated-validation-gate-and-test-telemetry)
  gate to record-sync, the Python enrollment/operator suites, the wgnetstack
  build, and the Windows launcher tests. [Slice 103](slices/103-linux-client-package-build.md)
  makes the Windows client package reproducible from a Linux runner.
  [Slice 104](slices/104-registry-driven-deploy.md) adds registry-driven
  all-server deployment on tag. Remaining operator actions: register the
  self-hosted runner on the deployment host and run one tag deploy to prove the
  mutating path, which has no runtime evidence yet.
- [ ] Queued — Remaining delivery workflow capabilities (Phase 13): Remote-SSH
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
- [ ] In progress — Basic Monsters map (Phase 12 handoff, pre-slice design):
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
- [x] Done — Public game access via WireGuard (Phase 11): the first
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
- [x] Done — Secure Windows tunnel enrollment and credential storage (Phase
  11): [F-035](FEATURE-LIST.md#f-035-secure-windows-tunnel-enrollment-and-credential-storage)
  and [Slice 054](slices/054-secure-windows-tunnel-enrollment.md) replace the
  temporary embedded-key WAN verifier with invite redemption, client-generated
  keys, Windows DPAPI protection, automatic tunnel startup, and operator
  revocation. The six real-WAN checks passed on 2026-09-16.
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
- [x] Ready — Player accounts and characters, data layer (Phase 10): design
  complete (`.scratch/player-accounts/spec.md`, all six tickets resolved,
  `CONTEXT.md` reconciled). The Wave 4 shared SQLite foundation
  ([Slice 038](slices/038-shared-sqlite-persistence-foundation.md), F-029)
  and the `accounts`/`characters` schema and repository on top of it
  ([Slice 039](slices/039-accounts-characters-repository.md), F-030) are now
  delivered.
- [x] In progress — Player accounts and characters, auth + session (Phase 10):
  the register/login ENet RPC seam, PBKDF2-HMAC-SHA256 hashing (off the main
  thread), and the opaque in-memory `SessionRegistry`
  ([Slice 040](slices/040-account-auth-session.md), F-031) are now delivered,
  additive to the existing always-playable connect lifecycle (auth is not yet
  mandatory for world entry).
- [x] In progress — Player accounts and characters, Character CRUD (Phase 10):
  session-gated `list_characters`/`create_character`/`select_character`/
  `delete_character` over ENet ([Slice 042](slices/042-character-crud-rpc.md),
  F-032) are delivered — every operation is scoped to the peer's session
  account (the client never supplies an `account_id`), enforcing the 5-cap,
  global live-name uniqueness, and ownership. Still queued, unscoped: client
  login/character screens replacing `identity_gate.tscn` (spec slice 5), and
  Character -> Player `start_for_peer` instantiation (spec slice 6). Self-serve
  registration behind the Phase 11 WireGuard gate; up to 5 globally-unique,
  soft-deletable Characters per Account.
- [x] In progress — Player accounts and characters, world entry (Phase 10):
  the server-side selected-Character world-entry binding
  ([Slice 043](slices/043-character-world-entry.md), F-033) is delivered —
  `get_selected_character` resolves the session's selection and
  `bind_character` instantiates the Player as it, additive to the connect-time
  spawn. Still queued, GUI-confirmed: the client login/register/character
  screens replacing `identity_gate.tscn` (spec slice 5, Slice 044), and the
  optional mandatory-auth hard-flip.