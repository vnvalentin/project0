# Project0 Master Game Vision

Status: charter refreshed; domain maps and delivery gates remain open
Governing issue: [#495](https://github.com/vnvalentin/project0/issues/495)

This map captures the intended game outcome and the order in which the idea can
be made real. It is deliberately technology-neutral. Existing Godot, Nakama,
Ollama, storage, container, and deployment choices are current experiments or
implementation context, not commitments made by this vision.

## Player promise

Project0 is a persistent cooperative action-adventure in which players inhabit
an evolving world, make consequential choices, solve problems with their own
judgment, develop physically distinct Characters, form lasting Parties, build
places of their own, and experience personal and shared stories shaped by a
hierarchy of Dungeon Masters.

The world is not only generated for players to visit. It is a foundation they
can explore, alter, inhabit, build upon, and eventually help govern.

## What Good Looks Like

- [x] The product promise and technology-neutral design principles are
	recorded.
- [x] The DM Guild, Party, Character, content, world-building, Canon,
	construction, spatial, and traversal goals are named.
- [ ] A bounded Party traversal vertical slice proves shared problem solving,
	authoritative reward, and persistent consequence.
- [ ] Each future goal has a resolved domain map, public seam, non-goals, and
	evidence plan before implementation slices are allocated.
- [ ] The validated vertical slice is promoted through the normal Feature List,
	Project Tracker, and slice-record workflow.

## Core design principles

### Mind versus Tool

The player is responsible for observation, deduction, positioning, timing,
telegraph reading, and puzzle solving. Character attributes and equipment
change how a correct choice executes physically; they never act as permission
slips for understanding, choosing, or solving an action.

### Semantic intent versus deterministic execution

Language models and Dungeon Masters provide context, meaning, structure,
variety, and proposals. Deterministic authoritative systems validate and
execute physics, combat, movement, inventory, construction, multiplayer state,
timing, and persistence.

No model-generated proposal is gameplay truth until it passes the relevant
validation and authority boundary.

### Persistent consequence

World, Party, Character, item, construction, quest, faction, and encounter
changes must have explicit ownership, history, revision, and recovery rules.
Generated content becomes durable only through an authoritative Canon process.

### Player-shaped world

Generated places are starting conditions. Player actions can reveal, destroy,
repair, build, occupy, govern, or transform those places. Later players should
encounter meaningful consequences without receiving contradictory or unsafe
state.

### Replaceable technology

The vision names capabilities and guarantees, not specific databases, message
buses, renderers, map editors, model runtimes, or deployment products. A
technology earns adoption by satisfying a resolved domain contract and its
validation evidence.

## Experience pillars

### 1. DM Guild campaign architecture

- The World DM maintains global timeline, factions, macro-events, world
	bulletins, and cross-player consequences.
- The Party DM maintains shared campaign goals, party history, relationships,
	reputation, shared assets, and cooperative encounters.
- The Personal DM maintains a Character's personal arc, memories, companions,
	and immediate narrative context.
- DMs can propose quests, encounters, puzzles, items, locations, faction
	changes, and convergence opportunities.
- A shared authoritative world prevents separate narrative contexts from
	becoming separate contradictory realities.
- Personal, Party, and World context is spatially and narratively scoped so
	memory remains relevant and bounded.

### 2. Party and shared encounters

Detailed planning map: [Goal D Party campaign and shared encounters](../party-coordination/map.md).

A Party is a persistent cooperative relationship between one to five
Characters. Membership, consent, leadership, roster history, and Party
presence are distinct concepts.

The Party system should support invitations, acceptance, leaving, removal,
succession, offline members, shared objectives, synchronized encounters,
asynchronous downtime, formation, combined techniques, mentorship, shared
facilities, and a dedicated Party HUD without erasing individual Character
identity, progression, inventory, or personal choices.

### 3. Character embodiment and progression

The six-node Vessel and its derived kinetic flow create a biological spider
graph rather than independent stat bars. Strength, Dexterity, Constitution,
Intelligence, Wisdom, and Charisma have interconnected opportunity costs.

Kinetic Volume, Control, and Output, Meridian pathways, friction, burnout,
magic equilibrium, equipment mass, buoyancy, stagger, recovery, and movement
should make different builds feel physically different while preserving the
Mind versus Tool rule.

Movement is also a player language for exploration and puzzle solving. Jumping,
swimming, dodging, sliding, crawling, climbing, wall-running, falling, and
other traversal actions should let players read spaces, discover routes,
manipulate hazards, reach mechanisms, evade threats, and solve environmental
problems through physical experimentation. Attributes and equipment modify the
distance, timing, stamina, control, risk, and recovery of these actions; they do
not decide whether the player is allowed to try a meaningful traversal idea.

### 4. Items, equipment, inventory, and crafting

The game needs a durable item ecosystem with distinct item definitions and
owned item instances. Items may have identity, provenance, materials, history,
condition, lore, bounded mechanical properties, and relationships to quests,
factions, Characters, or Parties.

Inventory and equipment must support ownership, capacity, transfer, trade,
durability, containers, quest binding, Party storage, recovery, and atomic
authoritative mutation. Crafting should combine materials, tools, stations,
techniques, recipes, experimentation, quality, defects, and player intent.

Generated item identity and variation are proposals; valid costs, properties,
effects, and transactions are deterministic and authoritative.

### 5. Semantic world building

Detailed planning map: [Goal E DM Guild and semantic world pipeline](../dm-guild/map.md).

The world-building tool is a portable structured world blueprint. It expresses
rooms, regions, relationships, landmarks, themes, puzzle intent, entity roles,
biomes, seeds, constraints, and other semantic structure without requiring the
LLM to know a renderer's private format.

Replaceable builders interpret that blueprint into geometry, collision,
navigation, entities, presentation, and runtime state. A blueprint may support
runtime generation, editor review, offline previews, test fixtures, and future
export pipelines.

### 6. Persistent JIT Canon

New world content is requested asynchronously near unexplored boundaries. A
proposal is validated, built, and committed to the World Canon before it is
treated as durable truth. Re-entry loads the accepted result and applies
authoritative mutations such as destroyed bridges, cleared camps, construction,
faction changes, and defeated bosses.

The required capability is a replaceable Canon persistence service, not a
particular storage product. It must support revisions, mutations, event history,
spatial and quest context, concurrency, inspection, recovery, and migration.

### 7. Player homes, buildings, and towns

Detailed planning map: [Goal F player-shaped world](../player-construction/map.md).

Players can claim, design, construct, modify, expand, repair, share, abandon,
and govern persistent places. A home can grow into a shared homestead, Party
base, settlement, village, or town.

Construction must coexist with generated terrain and Canon, support ownership
and permissions, validate occupancy and access, provide materials and crafting
hooks, and allow NPCs, services, factions, quests, and trade to respond to
player-built places.

### 8. Spatial awareness

The world needs a replaceable spatial indexing capability for generated
structure overlap, nearby entities, area effects, event triggers, multiplayer
interest filtering, DM context selection, streaming, and future zone boundaries.

The index is not authority. It accelerates queries over authoritative state and
must handle bounds, moving entities, negative coordinates, sector boundaries,
verticality, deterministic ordering, and rebuild or validation after recovery.

Scale research map: [Goal H scale and bounded simulation expansion](../zone-sharding/map.md).

## Authority boundary

```text
Player or Party intent
				|
				v
Personal, Party, or World DM proposal
				|
				v
Schema, policy, spatial, and domain validation
				|
				v
Authoritative deterministic execution
				|
				v
Canon, Character, Party, item, quest, and construction state
				|
				v
Client presentation and narrative context
```

## Delivery structure

The goal is not to implement every pillar at once. Each goal must pass through
the same progression:

1. **Charter:** agree on player outcome, vocabulary, invariants, and non-goals.
2. **Domain map:** resolve ownership, lifecycle, edge cases, and dependencies.
3. **Contract:** define the technology-neutral public seam and accepted data.
4. **Prototype:** test the uncertain experience or state model cheaply.
5. **Handoff:** record SDD/BDD/TDD, safety rules, validation, and rollback.
6. **Slice:** implement the smallest public-seam capability.
7. **Evidence:** run focused and full validation, then synchronize feature and
	 tracker records.

No new feature ID or implementation slice should be created merely because a
vision idea exists.

## Delivery goals

The A-H labels below are canonical for future planning. The existing roadmap's
historical Track A-F labels remain valid references for already-created
milestones, issues, and slices; their crosswalk is maintained in
[ROADMAP-REASSESSMENT.md](../../docs/ROADMAP-REASSESSMENT.md).

### Goal A - Trusted access and playable client

Complete the remaining packaged-client, onboarding, update, rollback, and
controller evidence. This is the access foundation for real playtests.

### Goal B - Reliable authoritative runtime

Complete production mutation and rollback evidence, operational boundaries,
health, audit, and bounded operator control without weakening gameplay
authority.

### Goal C - Authoritative content systems

Resolve item ownership, inventory, equipment, loot, crafting, quest, dialogue,
content activation, and content-operations maps before allocating slices. The
existing Character, Vessel, Canon, and authority contracts remain the boundary.

### Goal D - Party campaign and shared encounters

Resolve persistent Party lifecycle, shared campaign state, asynchronous
downtime, convergence, formations, combined techniques, mentorship, and Party
presentation. This depends on stable Character and technique contracts.

### Goal E - DM Guild and semantic world pipeline

Define the World, Party, and Personal DM responsibilities; structured semantic
blueprints; proposal validation; context retrieval; world bulletins; event
publication; and deterministic builder interfaces. This goal includes quests,
dungeons, puzzles, faction behavior, generated artifacts, and adaptive
environmental direction.

### Goal F - Player-shaped world

Define construction, homes, buildings, towns, ownership, permissions, spatial
validation, materials, construction state, NPC response, settlement growth,
and interaction with generated Canon.

### Goal G - Telemetry and operational observability

Provide correlated records for sessions, connections, actions, combat,
encounters, DM proposals, Canon mutations, and failures so the runtime and
future balance work can be understood from real evidence.

### Goal H - Scale and bounded simulation expansion

Research spatial ownership, streaming, workers, process boundaries, and future
zone handoff only after measured need and a resolved ownership model. Do not
choose sharding technology as a substitute for domain decisions.

## Current sequencing

1. Finish the existing trusted-client and runtime evidence already in flight.
2. Resolve telemetry identity and persistence so later operations have useful
	 evidence.
3. Use the [Vision-to-Play Vertical Slice](vertical-slice.md) to resolve the
	 smallest Party, traversal, blueprint, reward, and mutation contracts.
4. Finish the content maps, beginning with item ownership and crafting
	 foundations.
5. Resolve the Party campaign map against the stable Character and technique
	 contracts.
6. Resolve the DM Guild and semantic world-builder contracts.
7. Resolve player construction and settlement growth against Canon, spatial,
	 item, and Party contracts.
8. Keep scale and sharding research-first until measured runtime evidence
	 requires it.

These are planning dependencies, not technology commitments. The sequence can
change when a prototype or validation result falsifies an assumption.

## Existing evidence and related records

- Historical foundation and early handoffs remain under the
	[game-vision issue records](issues/01-close-foundation-gate.md)
	and their neighboring records.
- Current outcome sequencing is maintained in
	[ROADMAP-REASSESSMENT.md](../../docs/ROADMAP-REASSESSMENT.md).
- Current domain vocabulary is maintained in
	[CONTEXT.md](../../CONTEXT.md).
- Party, content, telemetry, runtime, and scale research remain separate maps
	or GitHub planning threads until their contracts converge.

## Explicit non-goals

- No technology is selected by this charter.
- No LLM is allowed to own authoritative gameplay state.
- No generated content bypasses validation or persistence rules.
- No stat or model output replaces player reasoning.
- No new feature or slice is considered ready without a domain map and public
	seam.
- No final art, production-scale balancing, or global MMO scale is implied by
	the vision.
