# Slice & Feature Number Registry

Single source of truth for slice-number (and new feature-id) allocation, to
prevent collisions when more than one agent works this repository in parallel.

Created after two agents independently allocated **Slice 027 and 028** on
2026-09-13 — a classic "read the max, pick the next" race with no shared lock,
which produced duplicate slice files and duplicate tracker entries.

## Allocation rule

1. **One integrator owns allocation.** Exactly one agent/role assigns slice
   numbers and owns the delivery trackers (`docs/PROJECT-TRACKER.md`,
   `docs/FEATURE-LIST.md`). Parallel workers do **not** invent slice or feature
   numbers — they receive them from the integrator (or from their reserved
   block, below).
2. **Reserve before you create.** Before writing a `docs/slices/NNN-*.md`,
   append a row to the Allocations table below. The next free number is the
   invariant `max(existing docs/slices/ numbers, this table) + 1`. Reserving is
   one small commit; if two workers race, the second sees the first's row (or
   its file) and takes the next number.
3. **New feature ids** (`F-<n>`) follow the same reserve-first rule: take the
   next unused `F-` number and record it in `FEATURE-LIST.md`.

## Reserved blocks (only needed when a parallel autonomous worker is running)

If a second, autonomous agent (e.g. a long-running `claude -p` loop) runs
alongside interactive work, give it a reserved block **and disjoint files** so
the two can never collide:

| Block | Workstream |
| --- | --- |
| 001–099 | Primary / interactive gameplay slices (the default). |
| 100–199 | Reserved for a parallel autonomous worker (e.g. the WAN/infra loop). |

Within a block, allocation stays sequential.

## Allocations

Slices 001–026 are the linear delivery history (see `docs/slices/`). The
contended range and everything after it is tracked explicitly:

| Slice | Title | Workstream |
| --- | --- | --- |
| 027 | Agent-assisted delivery orchestration (P-004) | autonomous CLI |
| 028 | WireGuard remote-access infrastructure foundation (P-024) | autonomous CLI |
| 029 | Authoritative monster melee damage and death broadcast (IP-023) | autonomous CLI |
| 030 | Server-side wall and building collision (F-027) | interactive |
| 031 | Bigger rural village with NPC and leader housing (F-026) | interactive |
| 032 | wgnetstack netstack bridge, Linux prototype (P-024) | autonomous CLI |
| 033 | Client monster replication and rendering (IP-023) | interactive |
| 034 | wgnetstack in-client GDExtension + tunnel integration, Linux (P-024) | interactive |
| 035 | wgnetstack Windows DLL cross-compile + client repackage (P-024) | autonomous CLI |
| 036 | Imperial world-scale measurement contract — WorldScale (F-028) | interactive |
| 037 | World-scale constant relabel: meters → yards (F-028) | interactive |
| 038 | Shared server-owned SQLite persistence foundation, Wave 4 (F-029) | interactive |
| 039 | Accounts and characters persistence repository (F-030) | interactive |
| 040 | Account authentication and session, server (F-031) | interactive |
| 041 | DT-006 remaining-smoke-test GUT migration (interactive) | interactive |
| 042 | Character CRUD over the wire, server (F-032) | interactive |
| 043 | Character world entry, server binding (F-033) | interactive |
| 044 | Client login and character selection UI (F-033, F-034) | interactive |
| 045 | Canon sector persistence and one-time blueprint canonicalization (P-011, P-012) | interactive |
| 046 | Authoritative sector-boundary detection for JIT generation (IP-008) | interactive |
| 047 | JIT result canonicalization and sector replication (IP-008, P-011, P-012) | interactive |
| 048 | WireGuard invite-code enrollment service, logic + tests (P-024, issue 04) | interactive |
| 049 | WireGuard peer revocation/ban lifecycle, logic + tests (P-024, issue 06) | interactive |
| 050 | Canon mutation persistence: dynamic world mutation tracking (P-013) | interactive |
| 051 | Hardware-accelerated local inference: env config + bounded request telemetry (P-009) | interactive |
| 052 | F-026 LLM town generation ON at server boot (opt-in flag) | interactive |
| 053 | F-026 derive monster exclusion from town bounds | interactive |
| 054 | Secure Windows tunnel enrollment and credential storage (P-024, F-035) | interactive |
| 055 | Server fixed-tick and health snapshot contract (P-014) | interactive |
| 056 | Game-server container image and run-beside-native (P-014) | interactive |
| 057 | Game-server persistent data boundary and SQLite backup/restore (P-014) | interactive |
| 058 | In-process login gateway seam over AuthService/CharacterService (P-014) | interactive |
| 059 | Signed session assertion contract, issuer, and validator (P-014) | interactive |
| 060 | Assertion-backed session establishment in the login gateway (P-014) | interactive |
| 061 | Operator control plane: read-only status service (P-014) | interactive |
| 062 | Operator control plane: job/audit model + service restart action (P-014) | interactive |
| 063 | Operator control plane: audited mint-invite action (P-014) | interactive |
| 064 | Operator control plane: audited revoke-peer action (P-014) | interactive |
| 065 | Operator control plane: durable SQLite audit sink (P-014) | interactive |
| 066 | Operator control plane: audited start/stop lifecycle actions (P-014) | interactive |
| 067 | Server runtime health file + container HEALTHCHECK (P-014) | interactive |
| 068 | Login runtime extraction + standalone login-server process (P-014) | interactive |
| 069 | Assertion handoff seams: request from login, present to game (P-014) | interactive |
| 070 | Deploy + supervise the standalone login server (systemd + operator allowlist) (P-014) | interactive |
| 071 | Shared assertion secret across the game + login units (P-014) | interactive |
| 072 | Login-endpoint config: NetworkConfig.resolve_login_port + login server unifies on it (P-014) | interactive |
| 073 | Login->game handoff e2e: client authenticates on login process, presents assertion to game process (P-014) | interactive |
| 074 | Signed Character snapshot in the session assertion (contract + issuer) (P-014) | interactive |
| 075 | Cross-DB world entry: bind Player from the assertion snapshot (P-014) | interactive |
| 076 | Game server assertion-only mode: refuse account-authority RPCs (opt-in) (P-014) | interactive |
| 077 | Client login->game handoff seam (NetworkClient.perform_login_to_game_handoff) (P-014) | interactive |
| 078 | Wire login-screen gates to the login process (opt-in client flag) (P-014) | interactive |
| 079 | Optional dedicated Canon store: opt-in canon/accounts DB split on the game server (P-014) | interactive |
| 080 | One-time Canon migration into a dedicated store on first split boot (P-014) | interactive |
| 081 | Deploy the standalone login server via docker-compose (opt-in profile) (P-014) | interactive |
| 082 | Containerized login-split e2e: compose split overlay + two-container handoff proof (P-014) | interactive |
| 083 | One-command split launcher with shared-secret management (run-split.sh) (P-014) | interactive |
| 084 | Login-split cutover: split on by default (client split + game assertion-only) (P-014) | interactive |
| 085 | Remove in-process login from the game server (assertion-only login graph, no AuthService) (P-014) | interactive |
| 086 | Multi-peer Character replication: label remote Players with their bound Character (F-004) | interactive |
| 087 | Login-session resume: in-world Character Select without re-login (F-034) | interactive |
| 088 | Auth-gated onboarding A: HTTPS /login on the enrollment service, delegating credential verification to the login authority and returning a signed session assertion (P-024, ADR 0004) | interactive |
| 089 | Auth-gated onboarding B: /redeem accepts a signed assertion + idempotent per-account peer lifecycle and aging/deprovision (P-024, ADR 0004) | interactive |
| 090 | Auth-gated onboarding C-server: HTTPS character endpoints (list/create/delete/select + issue-character-assertion) on the enrollment service, loopback-delegated + account-scoped (P-024, ADR 0004, ADR 0005) | interactive |
| 091 | Auth-gated onboarding C-client-seam: Godot EnrollmentHttpClient (HTTPS login + character list/create/select/delete seam) (P-024, ADR 0005) | interactive |
| 092 | Auth-gated onboarding C-launcher: Windows launcher login + redeem-with-assertion + tunnel bring-up (P-024, ADR 0004, F-035) | interactive |
| 093 | Auth-gated onboarding C-client-wiring: wire account/character gates to EnrollmentHttpClient + tunnel + present character assertion (runtime-validated) (P-024, ADR 0005) | interactive |
| 094 | Reality dashboard truthfulness and delivery-record reconciliation (F-025) | interactive |
| 095 | Canon entity GUIDs + mutation target-existence enforcement (P-013) | interactive |
| 096 | Canon mutation intent DTO + server-authoritative resolution service (P-013) | interactive |
| 097 | Canon mutation intent RPC transport + headless round-trip e2e (P-013) | interactive |
| 098 | Canon sector mutation replay: server replicates the effective blueprint (P-013) | interactive |
| 099 | Public authentication abuse controls: bounded rate limiting and lockout (DT-009) | interactive |
| 100 | Public HTTPS account registration delegated to the login authority (DT-010) | interactive |
| 101 | Server deployment path in the current deployment pipeline (P-014) | interactive |
| 102 | Full-stack CI validation gate: record-sync, Python, Go, launcher jobs (F-005) | interactive |
| 103 | Linux-hosted Windows client package build (F-002) | interactive |
| 104 | Registry-driven all-server deployment on tag (P-014) | interactive |
| 105 | Container images for every service, published to GHCR (F-002, P-014) | interactive |
| 106 | Container runtime cutover: compose stack deployed by image tag (P-014) | interactive |
| 107 | Drive the engine at the contracted authoritative tick rate (DT-013) | interactive |
| 108 | Retire the git-archive deploy path (P-014) | interactive |
| 109 | Host-assumption sweep and post-deploy smoke checks (P-014) | interactive |
| 110 | Ship the Linux wgnetstack GDExtension in the server image (DT-014) | interactive |
| 111 | Dashboard issue traceability detail (F-025) | interactive |
| 112 | Reality page Goal source of truth (F-025) | interactive |
| 113 | Dashboard apps source layout (F-025) | interactive |
| 114 | Goal target coverage cards (F-025) | interactive |
| 115 | Goal What Good Looks Like criteria (F-025, P-004) | interactive |
| 116 | Phase 14 Character foundation handoff (#227, F-036) | interactive |
| 117 | Phase 14 Character alignment & disposition contract (#227, #228, F-036) | interactive |
| 118 | Phase 14 item & equipment effectiveness contract (#227, #233, F-036) | interactive |
| 119 | Phase 14 technique readiness & proficiency contract (#227, #230, #234, F-036) | interactive |
| 120 | Phase 14 shared health / defeat / recovery contract (#227, #231, F-036) | interactive |
| 121 | Phase 14 damage-resolution composition contract (#227, #231, F-036) | interactive |
| 122 | Phase 14 status-effect (resistible/removable) contract (#227, #231, F-036) | interactive |
| 123 | Phase 14 activity-routine (idle/patrol fallback, off-screen simulation) contract (#227, #229, F-036) | interactive |
| 124 | Phase 14 spawn-anchor (pressure-delayed replacement, promote/generate) contract (#227, #232, F-036) | interactive |
| 125 | Phase 14 integration: Player HP on the shared CombatHealth contract (#227, #231, F-036) | interactive |
| 126 | Phase 14 integration: Monster HP on the shared CombatHealth contract (#227, #231, F-036) | interactive |
| 127 | Phase 14 integration: server-owned Character foundation + presentation-snapshot replication (#227, #230, F-036) | interactive |
| 128 | Phase 14 integration: NPC/monster carries the shared CharacterFoundation (Player/NPC parity) (#227, F-036) | interactive |
| 129 | Phase 14 integration: live town-NPC state (Character + ActivityRoutine, route-consistent position) (#227, #229, F-036) | interactive |
| 130 | Phase 14 integration: live town-NPC population manager (SpawnAnchor pressure/replacement/significance) (#227, #232, F-036) | interactive |
| 131 | Phase 14 integration: town NPCs live in server_main + client replication/rendering (closes exit gate) (#227, #229, #232, F-036) | interactive |
| 132 | Phase 15 P-016-A: versioned embodiment tuning resolve seam (#219, #220, P-016) | interactive |
| 133 | Phase 15 P-016-A: vessel progression state + fixed-budget redistribution (#219, #223, P-016) | interactive |
| 134 | Phase 15 P-016-A: effective mechanics snapshot (derived, presentation-safe read-model) (#219, #224, P-016) | interactive |
| 135 | Phase 15 P-016-B: inverse friction modifier (Massive Bulk / Fragile Agility) (#219, P-016) | interactive |
| 136 | Phase 15 P-016-C: Kinetic Flow layer (Volume/Control/Output) (#219, P-016) | interactive |
| 137 | Phase 15 P-016-D: Meridian pathways (dedup cross-training evidence, idempotent unlock) (#219, P-016) | interactive |

Next free slice: **138** (verify against `docs/slices/` before reserving).

> Collision history: on 2026-09-13 the interactive and autonomous workstreams
> each allocated 027 and 028. Resolved by renumbering the **interactive** slices
> — the collision slice 028→030 and the village 027→031 — leaving the autonomous
> CLI slices at their original 027/028. Going forward, run parallel autonomous
> work in the 100–199 block to avoid a repeat.
