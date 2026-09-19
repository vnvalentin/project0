# Roadmap Reassessment: Wayfinder Learning

Status: active
Date: 2026-09-19 (refreshed; original 2026-09-18)
Governing issue: [#318](https://github.com/vnvalentin/project0/issues/318)

## 2026-09-19 refresh

Since the original grouping, Track A closed most of its scope (Slices
144-157 delivered the version gate, signed manifest, updater transaction,
trusted signing key, patch hosting, launcher orchestration, and the public
release/download pipeline), and Phase 14 gained an unplanned but in-scope
follow-on (Slice 158, player traversal locomotion, issue #229). Two new
Wayfinder goal clusters also opened GitHub issues without a corresponding
outcome bucket: telemetry/observability (#282, #289, #328, #332) and Party
coordination (#319, #323-325). Track C's item/loot/quest/content-ops frontier
also went from "chart first" to four maps mid-`grilling` (#302-315). This
refresh keeps the A-D structure, updates each track's status against that
evidence, and adds Tracks E and F so the new issues have an owning outcome
before they accumulate more child issues.

## Why the phase model changed

Phases 0–15 describe the historical build-up of the playable runtime: identity,
network authority, generated world, Canon persistence, public access, shared
Character state, and biological progression. Their exit evidence remains valid
and their numbers remain stable so existing slices, ADRs, and validation history
do not become ambiguous.

The newer Wayfinder work exposed a different planning boundary. A map is a
decision system, not a delivery phase: some maps are handoff-ready, some are
still fog, and research can change the shape of the next product capability.
The roadmap therefore groups future work by the customer outcome it enables,
not by the order in which implementation files happened to change.

## New forward phase model

### A. Trusted tester access and client delivery

**Outcome:** a new or returning tester can obtain the right Windows client,
choose LAN or WAN deliberately, onboard safely, and reach the game with a
server-enforced compatible build.

**Includes:** Phase 16's version gate, signed full-pack update, launcher
transaction and rollback, controller parity, the client-download-page map, and
the remaining packaged-Windows evidence. The download page is part of this
outcome, not a separate infrastructure phase.

**Status (2026-09-19): nearly closed.** The gate (Slice 146), signed manifest
(147), HTTPS staging (148), updater transaction (149), trusted signing key
(150), export-metadata exclusion (151, closes DT-015), patch hosting (152),
launcher orchestration (153), signed download/staging (154), the
`CLIENT_OUTDATED` handoff (155), the release-publishes-downloads pipeline
(156), and the visible-package/stable-directory follow-on (157, in-progress)
are delivered or in flight. Remaining gap: end-to-end packaged-Windows runtime
evidence for first install and a live update/rollback, plus the
controller-integration slices (#118-120) which have not started.

**Exit evidence:** public download surface, reproducible release manifest,
packaged-client runtime proof for first install and update/rollback, explicit
LAN/WAN onboarding, controller parity, and no unauthenticated path into
gameplay.

### B. Reliable runtime and operator confidence

**Outcome:** the deployed authorities can be released, observed, repaired, and
controlled without weakening gameplay or public-access boundaries.

**Includes:** the remaining Phase 12 runtime mutation/rollback evidence, DT-012
login-image separation decision, the server-admin-console map, health/ops
contracts, audit, bounded operator actions, and deployment rollback.

**Status (2026-09-19): blocked on decisions, not code.** Slices 101/104/106/
108/109/110 delivered the deployment path, container cutover, and image
packaging; the mutating registry-driven deploy path (backup/replace/restart/
health-gate/rollback) is still unexercised against production. DT-012 (login
shares the game image) remains open. The server-admin-console map has nine
unresolved `grilling` questions (#166-174) and zero allocated slices — it is
the long pole for this track, not implementation effort.

**Exit evidence:** independent release boundaries where justified, production
mutation-path rehearsal, versioned ops snapshots, authenticated/audited control
actions, and an executable recovery path.

### C. Authoritative content and player-facing game systems

**Outcome:** players can acquire, equip, use, and progress through authored or
generated content whose mutable state remains server-owned, validated, and
durable.

**Includes:** the EQEmu-informed frontiers for item definitions versus owned
instances, inventory/equipment/loot, quest content and runtime, and content
operations. The research does not authorize copying EQ-specific classes, UI,
or unbounded script globals. Existing Character, vessel, Canon, and authority
contracts remain the boundary.

**Entry gate:** each frontier gets its own Wayfinder map and What Good Looks
Like criteria before implementation slices or new feature IDs are created.

**Status (2026-09-19): actively chartering, no implementation slices yet.**
Four maps are open and mid-`grilling`: item ownership/loot lifecycle (#302),
equipment/inventory/loot experience (#303), quest content and runtime (#304),
and game-content operations/backend boundaries (#305). Each has a prototype
issue (#307 equipment/inventory/loot, #313 dialogue/journal/quest) and 2-4
unresolved decision issues (#308-312, #314-315). None has produced a
handoff-ready spec yet — do not allocate a slice number or feature id against
any of these until a spec/ADR closes its map, per the entry gate above.

**Exit evidence:** versioned content contracts, atomic server-side mutation and
reward transactions, typed persistent progress, validated staged activation,
operator inspection/reload boundaries, and public-seam tests.

### D. World scale and bounded simulation expansion

**Outcome:** the world can grow beyond one authoritative runtime without
silently changing ownership, persistence, or player handoff semantics.

**Includes:** zone-sharding research, future world-builder/mobile-object worker
contracts from the container-platform map, and only the process splits justified
by measured load or isolation needs.

**Entry gate:** `zone-sharding` must gain a map, research findings, an ownership
and cross-shard handoff model, and an ADR before implementation work is created.

**Status (2026-09-19): still gated.** `zone-sharding` has a Goal issue (#204)
and one seed issue (#205) but still no `.scratch/zone-sharding/map.md` — the
entry gate remains open. Do not treat #205 as an allocated slice; it is
research scaffolding only.

**Exit evidence:** explicit shard ownership, bounded cross-shard handoff,
version-compatible persistence/worker contracts, failure recovery, and measured
capacity evidence.

### E. Telemetry and operational observability

**Outcome:** every server (game, login, enrollment) emits a correlated,
queryable record of client interactions, connections, combat, and network
events, so B's admin console and future balance/ops decisions have real data
instead of log-scraping.

**Includes:** the telemetry-pipeline map (#282), the correlation/session
identity research that map depends on (#289), the implementation-slice route
derived from it (#328), and its first slice — a telemetry sink plus dedicated
database (#332, Slice 160).

**Entry gate:** #289's correlation/session identity model must be decided
before #328's slice route is finalized; a telemetry sink that cannot
correlate events across reconnect/relogin is not worth persisting.

**Exit evidence:** a durable, queryable telemetry store separate from
gameplay persistence, a stable correlation/session identity, and at least one
consumer (the admin console in Track B, or an ops query) reading real data.

**Relationship to B:** this track supplies the data B's operator console
consumes. Chart E's correlation model before B's console spec locks its
telemetry-content decisions, or the console will be redesigned around
whatever E decides later.

### F. Party coordination and shared encounters

**Outcome:** multiple players can form a party, coordinate in a shared
encounter (formation, combined techniques, mentorship/observational
learning), and see that coordination reflected in a dedicated HUD — without
weakening per-Character server authority.

**Includes:** the Party Coordination and Shared Encounter Design Map (#319),
its open `grilling` decisions on combined techniques (#324) and
mentorship/observational learning (#323), and the Party HUD/formation
prototype (#325).

**Entry gate:** same as Track C — a handoff-ready spec and ADR before any
slice or feature id is allocated. This track is downstream of Track C's
Character/technique contracts (F-036, P-016) and should not fork them.

**Exit evidence:** a versioned party-membership and shared-encounter contract,
combined-technique resolution that stays within existing action/technique
authority, and a presentation-safe party HUD.

## GitHub source of truth

Each track A-F is also a GitHub milestone on this repo, and every issue listed
under a track's "Includes" is assigned to that milestone:

| Track | Milestone |
| --- | --- |
| A | [Track A: Trusted tester access and client delivery](https://github.com/vnvalentin/project0/milestone/1) |
| B | [Track B: Reliable runtime and operator confidence](https://github.com/vnvalentin/project0/milestone/2) |
| C | [Track C: Authoritative content and player-facing game systems](https://github.com/vnvalentin/project0/milestone/3) |
| D | [Track D: World scale and bounded simulation expansion](https://github.com/vnvalentin/project0/milestone/4) |
| E | [Track E: Telemetry and operational observability](https://github.com/vnvalentin/project0/milestone/5) |
| F | [Track F: Party coordination and shared encounters](https://github.com/vnvalentin/project0/milestone/6) |

The milestone's open/closed issue counts are the live completion signal; this
file stays the narrative (outcome, scope, entry gate, exit evidence). When a
new issue is opened under one of these outcomes, assign its milestone at
creation time so the milestone counts and this document do not drift apart.
The Project0 Flow dashboard renders these milestones directly (Reality page
"Outcome tracks" bars, `/detail` "Outcome tracks" cards) — do not hand-edit a
parallel roadmap block in `dashboard/app.py`; add/remove issues from the
milestone instead.

## Reclassification rules

- Existing phase numbers and completed exit gates are historical evidence; do
  not renumber them again.
- Phase 16 work is retained under A. The download-page map is folded into that
  outcome when its map decisions become slices.
- Phase 12 and Phase 17 work are coordinated under B, but their existing slice
  ownership remains unchanged until a slice is delivered.
- The EQEmu research is discovery input for C, not an implementation commitment
  and not a new feature by itself.
- Phase 18 remains research-first under D; it has no implementation slices.
- A Wayfinder map's completion is not a phase exit. A resolved task becomes a
  feature only after the normal records-first handoff and validation gates.
- Telemetry (#282, #289, #328, #332) is a new Track E, not folded into B —
  B consumes E's data but does not own its schema or correlation model.
- Party coordination (#319, #323-325) is a new Track F, downstream of C's
  Character/technique contracts; it does not get its own Character or
  technique fork.

## Immediate order

1. Close A: capture packaged-Windows first-install and update/rollback
   runtime evidence, land Slice 157's remaining evidence, then start the
   controller-integration slices (#118-120) and the download-page follow-ups.
2. Close B's production mutation/rollback evidence on the existing deploy
   path, decide DT-012, and resolve the nine open server-admin-console
   questions (#166-174) into a capstone spec before allocating any console
   slice.
3. Decide E's correlation/session identity model (#289) before locking B's
   console telemetry-content decisions, then implement the Slice 160
   telemetry sink (#332) so B and future balance work have real data instead
   of ad hoc log-scraping.
4. Resolve C's four open maps (#302-305) to handoff-ready specs, item/loot
   first since equipment and quest reward transactions depend on its
   ownership model, before allocating any implementation slice or feature id.
5. Chart F only after C's Character/technique contracts are stable; a party
   contract built against a moving Character contract will need rework.
6. Keep D in research until zone-sharding gains a map (`.scratch/zone-sharding/
   map.md`) and C plus measured runtime evidence show which scale boundary is
   actually needed.

## Non-goals

This reassessment does not create application code, invent new feature IDs,
declare unresolved maps complete, or replace the detailed SDD/BDD/TDD records
for individual slices. It is a roadmap and ownership correction only.