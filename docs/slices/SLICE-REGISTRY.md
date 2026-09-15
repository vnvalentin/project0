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

Next free slice: **077** (verify against `docs/slices/` before reserving).

> Collision history: on 2026-09-13 the interactive and autonomous workstreams
> each allocated 027 and 028. Resolved by renumbering the **interactive** slices
> — the collision slice 028→030 and the village 027→031 — leaving the autonomous
> CLI slices at their original 027/028. Going forward, run parallel autonomous
> work in the 100–199 block to avoid a repeat.
