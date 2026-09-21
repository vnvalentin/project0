# Project0 Hoshin

Status: active strategic alignment record

## Purpose

This record groups the existing delivery backlog into five top-level Hoshin
anchors. It does not replace the product Vision, GitHub Goals and Features,
phase exit gates, or technical-debt records. Delivery status remains owned by
the linked records and GitHub issues.

**Parent vision:** [#495](https://github.com/vnvalentin/project0/issues/495)

## Scope

- **User outcome:** direct the current backlog toward a playable, operable,
  persistent cooperative action-adventure.
- **Affected boundary:** strategic planning only; no runtime behavior,
  authority rule, delivery status, or implementation priority is changed here.
- **Non-goals:** allocating Features or Slices, closing issues, revising phase
  gates, or choosing implementation technologies.
- **Unacceptable outcome:** treating aspiration or design work as delivered
  product capability.

## Strategic Baseline

The authority, Character, Canon, progression, Nakama entry, telemetry-pipeline,
and operator-console foundations are delivered to varying degrees. The forward
backlog is primarily constrained by unproven release recovery, operational
correlation and mutation evidence, unresolved content ownership contracts,
unchartered cooperative/construction contracts, and unmeasured scale needs.

The latest local GUT telemetry is not green: it reports 125 of 126 scripts run
because the local `godot-sqlite` extension is unavailable. This is an
environmental validation constraint until a native-enabled validation run
confirms or refutes an application defect.

## Hoshin 1: Trusted Tester Access

**Aspiration:** Any tester can safely obtain, launch, update, and enter a
compatible client.

**Current condition:** Signed packaging, first-install evidence, LAN/WAN
onboarding, and version identity are delivered. Live update/rollback recovery
and controller parity remain incomplete.

**Top-level acceptance criteria:**

- A fresh Windows tester completes download, verification, install, and entry
  without an unauthenticated gameplay path.
- The server rejects an incompatible client version before world entry.
- A live signed update, interrupted-swap recovery, failed-readiness rollback,
  and repair route each have repeatable evidence.
- Every supported named player action is usable through the supported
  controller path and proven in a packaged-client playtest.

| Theme | Big Problem | Measurable Completion Metric |
| --- | --- | --- |
| Release continuity | The release path has not been proven through live upgrade and recovery failures. | Four repeatable evidence runs pass: install, signed update, interrupted-swap recovery, and rollback. |
| Input parity | Controller input remains an unproven interaction path. | 100% of supported named player actions have binding coverage and one packaged-client controller proof. |

**Primary alignment:** Vision Goal A; Phase 16; historical Track A.

## Hoshin 2: Reliable, Observable Authority

**Aspiration:** Operators can release, observe, recover, and control every
authority without weakening server ownership or public-access boundaries.

**Current condition:** The authoritative runtime, Nakama route, telemetry
pipeline, and operator-console foundation exist. Production deployment
mutation/rollback has not been rehearsed, service correlation is incomplete,
and DT-012 remains open.

**Top-level acceptance criteria:**

- A production-like backup, replace, health-gate, and rollback rehearsal
  succeeds with retained evidence.
- Operators can trace one session across login, world entry, action/combat,
  and disconnect through queryable correlated records.
- Bounded operator actions require independent authentication, create audit
  records, and are proven through their recovery paths.
- The login/game release boundary is split with compatibility evidence, or
  DT-012 is permanently accepted with documented compensating controls.

| Theme | Big Problem | Measurable Completion Metric |
| --- | --- | --- |
| Reversible operations | The deployment path exists but its mutation and recovery path is unproven. | One full production-like backup, replace, health-gate, rollback rehearsal exits successfully with a retained run record. |
| Operational truth | Telemetry cannot yet provide a complete correlated operational narrative. | One session is queryable across four lifecycle stages: login, entry, action/combat, and disconnect. |
| Release-boundary isolation | The publicly exposed login authority shares an image and release cadence with simulation. | DT-012 is closed by independent compatibility-tested images or accepted permanently with a recorded compensating control. |

**Primary alignment:** Vision Goals B and G; Phases 12 and 17; historical
Tracks B and E.

## Hoshin 3: Authoritative Content And Semantic World

**Aspiration:** Players receive meaningful quests, items, and world proposals
whose effects are validated, durable, and server-owned.

**Current condition:** Character, progression, Canon, and the first
server-only normalized World-directive validator are available. Item, inventory,
equipment, loot, quest, and content-operations ownership contracts remain in
the design gate.

**Top-level acceptance criteria:**

- A bounded player vertical slice proves authoritative item acquisition,
  equipment/use, quest reward, and recovery after restart.
- Every semantic proposal is accepted, rejected, or deterministically falls
  back before a builder or Canon write receives it.
- Content activation is versioned, inspectable, auditable, and reversible.
- The complete vertical slice produces a durable Canon consequence with public
  seam evidence.

| Theme | Big Problem | Measurable Completion Metric |
| --- | --- | --- |
| Owned content transactions | The lifecycle for definitions, owned instances, inventory, loot, and rewards is unsettled. | An approved contract and prototype prove atomic server-side grant, transfer, equip, consume, and recovery. |
| Validated semantic proposals | DM/LLM proposals need deterministic normalization before builder or Canon use. | Fixture-backed replay proves every input is accepted, rejected, or deterministically falls back. |
| Content activation | Quests and live content lack a versioned staging and rollback boundary. | One staged content activation is versioned, audited, reversible, and public-seam tested. |

**Primary alignment:** Vision Goals C and E; Phase 19; historical Track C.

## Hoshin 4: Cooperative, Player-Shaped World

**Aspiration:** One to five Characters form durable Parties, solve shared
encounters, and leave governed persistent places in the world.

**Current condition:** Multi-peer authority, shared Character, progression, and
Canon foundations are delivered. Party lifecycle and shared-encounter decisions
remain open; construction has not reached a resolved ownership and spatial
validation contract.

**Top-level acceptance criteria:**

- A Party vertical slice proves membership, consent, shared encounter/reward,
  persistent consequence, and a presentation-safe Party HUD.
- Party membership supports invitation, acceptance, leaving/removal, leadership
  succession, and offline members without duplicating Character authority.
- A construction vertical slice proves authorized placement, persistence,
  restart recovery, ownership rejection, and overlap rejection.

| Theme | Big Problem | Measurable Completion Metric |
| --- | --- | --- |
| Party lifecycle and encounter authority | Membership, presence, combined techniques, and shared rewards lack one authoritative contract. | A versioned contract supports invite, accept, leave/removal, offline member handling, and one server-resolved shared encounter. |
| Governed construction | Construction lacks ownership, spatial-validation, Canon, and permission rules. | One authorized build/change persists through restart, rejects invalid ownership or overlap, and emits an audit/history record. |

**Primary alignment:** Vision Goals D and F; historical Track F.

## Hoshin 5: Evidence-Led Scale And Resilience

**Aspiration:** The world grows only when measured capacity requires it, with
explicit ownership and recoverable handoffs rather than speculative sharding.

**Current condition:** Scale is research-first. A `zone-sharding` planning map
exists, while the tracker and roadmap still describe it as absent; no validated
capacity threshold, ownership model, handoff contract, or recovery proof exists.

**Top-level acceptance criteria:**

- Repeatable load evidence defines the current safe capacity and an explicit
  trigger for partitioning.
- The tracker, roadmap, planning map, and linked GitHub Goal agree on the
  research entry condition.
- If partitioning is justified, an ADR and prototype prove one owner per
  mutable fact, version-compatible persistence, bounded handoff, and recovery.
- If partitioning is not justified, the measured limit and a non-sharding
  mitigation are recorded as the decision outcome.

| Theme | Big Problem | Measurable Completion Metric |
| --- | --- | --- |
| Capacity truth | The project has no measured saturation threshold to justify a scale boundary. | Repeatable load evidence establishes a safe capacity envelope and an explicit partitioning trigger. |
| Ownership-preserving partitioning | A future zone split could duplicate authority or lose Canon consistency. | A recovery-tested prototype proves one owner per mutable fact and no lost or double-applied state across handoff. |

**Primary alignment:** Vision Goal H; Phase 18; historical Track D.

## Governance And Sequencing

1. Advance Hoshin 1's post-release recovery proof and Hoshin 2's correlation
   decision in parallel.
2. Complete Hoshin 2's production mutation/rollback evidence before increasing
   operational blast radius.
3. Resolve Hoshin 3's item ownership model before inventory, equipment, quest
   rewards, or content activation slices are allocated.
4. Charter Hoshin 4's Party contract after Hoshin 3 stabilizes the relevant
   Character, technique, and item contracts; charter construction after Party
   ownership boundaries are clear.
5. Keep Hoshin 5 research-first until measured evidence justifies a scale
   boundary.

## Sources Of Truth

- [Master Game Vision](.scratch/game-vision/map.md)
- [Roadmap Reassessment](docs/ROADMAP-REASSESSMENT.md)
- [Project Tracker](docs/PROJECT-TRACKER.md)
- [Technical Debt Tracker](docs/TECHNICAL-DEBT-TRACKER.md)
- [Feature List](docs/FEATURE-LIST.md)
- [Systems Specification](docs/SYSTEMS-SPECIFICATION.md)