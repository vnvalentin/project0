# Project0 Systems Architecture

This document is the normative implementation contract for Project0, a
networked 3D 3/4-isometric action adventure built with Godot 4.x. Requirement
terms `MUST`, `MUST NOT`, `SHOULD`, and `MAY` are binding in the RFC sense.
When this document conflicts with an implementation convenience, this document
wins unless an accepted ADR deliberately supersedes it.

Repository delivery and safety rules remain authoritative in [AGENTS.md](AGENTS.md),
[CONTEXT.md](CONTEXT.md), the
[Engineering Constitution](docs/ENGINEERING-CONSTITUTION.md), and the
[development workflow](docs/DEVELOPMENT-WORKFLOW.md). The cross-system ownership
decision is recorded by
[ADR 0002](docs/adr/0002-authoritative-mechanics-and-progression.md).

## Current Reality And Target Contract

The following distinction MUST remain explicit in code, tests, and delivery
records:

- **Implemented now:** identity and movement foundations, server-authoritative
	movement and peer replication, bounded client prediction/reconciliation, a
	version-one sector blueprint validator, and asynchronous in-memory
	provisional sector requests. See [FEATURE-LIST.md](docs/FEATURE-LIST.md).
- **Normative target, not implemented:** the biological vessel, progression,
	Kinetic nodes, Meridians, Burnout, magic equilibrium, combat resolution,
	progression persistence, sector-boundary triggering, geometry translation,
	quest-target schema fields, and SQLite Canon storage/mutation.
- Slice 008 currently accepts a bounded subset of structural sector data. Any
	future starting-position or quest-target fields require an explicit schema
	version, validation, compatibility tests, and a delivery slice. Their mention
	below MUST NOT be read as a claim that they are accepted today.

No future-target structure in this document authorizes placeholder runtime
loops or speculative production code. Each capability MUST be delivered as a
bounded SDD/BDD/TDD slice at a public seam.

## Non-Negotiable Design Laws

1. **The mind is never stat-gated.** If a player deduces a valid puzzle
	 solution, the authoritative interaction executes it unconditionally. The
	 server MUST NOT require an INT, WIS, Perception, Focus, Logic, Intelligence,
	 dialogue, or hidden-roll threshold to accept the correct solution.
2. **Stats modify embodiment, not reasoning.** Attributes may alter physical or
	 spatial affordances, resource efficiency, and execution windows. High Mental
	 Focus may slow or extend the action window after pulling a puzzle lever so
	 the Player has longer to cross a closing gate. Low Focus still permits the
	 solution and alternative physics, such as smashing a nearby pillar and
	 walking across it.
3. **The server owns outcomes.** Clients send intents and render predictions.
	 Only the headless server accepts actions, calculates combat and progression,
	 unlocks Meridians, applies or expires Burnout, resolves magic, and commits
	 world mutations.
4. **Persistent and effective state are separate.** Temporary effects MUST NOT
	 overwrite earned vessel values, training evidence, Meridian unlocks, or
	 other durable state.
5. **The LLM proposes; it never authorizes.** Ollama output is untrusted
	 provisional data until strict validation. Validated data is still not Canon
	 until an atomic server-owned persistence operation succeeds.
6. **Balance is versioned data.** Final thresholds, curves, opposing weights,
	 durations, and multipliers MUST live in a bounded, versioned, server-owned
	 tuning resource. They MUST NOT be scattered as magic numbers through client
	 or server scripts.

## Mind Versus Tool Architecture

Every structural system MUST preserve a hard boundary between human judgment
and the embodied Player that executes that judgment.

### The Player's Domain: The Mind

The human player alone is responsible for:

- observing the environment and deciding which details matter;
- recognizing and interpreting enemy telegraph animations;
- calculating combat position, spacing, direction, and timing;
- decoding clues and deducing logical puzzle solutions;
- selecting dialogue or faction intent.

The game MUST NOT roll against an attribute to perform these acts, auto-solve
them, replace them with a character knowledge check, or reject a correct answer
because a number is low. An authoritative server may still validate physical
facts such as reach, mechanism state, sequence order, or whether the target
exists. Those checks validate the world interaction, not the human's intellect.

### The Player's Domain: The Tool

The Player's body and equipment execute the human's choice. Vessel attributes
and derived state MAY modify only physical, spatial, sensory-presentation, and
mechanical execution properties, including:

- movement distance, acceleration, mass, collision response, and buoyancy;
- stamina/energy capacity, cost, regeneration, and recovery;
- action windup, active duration, recovery, invulnerability frames, and slide
	 distance;
- the duration of an already-triggered environmental execution window;
- the visibility or intensity of authored environmental evidence;
- strike force, carry capacity, health, stagger, and concentration efficiency.

A modifier MUST act through an explicit, inspectable world or execution rule.
It MUST NOT become a disguised permission check for reasoning.

### Puzzle And Perception Rules

WIS/Perception MUST NOT auto-solve a puzzle. It MAY select among authored
presentation tiers for supplemental environmental evidence. For example, high
WIS may cause the local client to render a subtle crack in a floor tile so the
human can infer that it marks a hidden spike trap. The cue MUST NOT label the answer,
automatically avoid the trap, or be the only way to submit a solution the
player has independently discovered.

Mental Focus MAY expand a real-time execution window after the solution is put
into motion. A lever can, for example, produce an illustrative three-second
slow-motion presentation/window so the Player has more time to cross a closing
gate. In multiplayer, the server MUST represent the actual allowance in
authoritative ticks; a client MAY render approved local time dilation but MUST
NOT alter server `Engine.time_scale`, other Players, or cooldown truth. Low
Focus preserves the same valid lever solution and permits physical alternatives
such as using brute force to tip a stone pillar over the gap.

### Combat Reading And Execution Rules

Enemy intent begins as an authoritative action state replicated early enough
for the client to render its authored telegraph. The human must read that
animation, choose position/timing, and press dodge. Stats MUST NOT auto-dodge,
identify a safe direction, or decide whether the human recognized the attack.

After input, the server validates ordinary physical action state and computes
the dodge profile. Effective Dexterity and Metabolism determine bounded
properties such as invulnerability frames and slide distance. A low value does
not prohibit an otherwise legal attempt; it produces a less forgiving physical
tool. Whether the attack ultimately connects follows authoritative timing,
collision, and the derived execution profile, never a hidden intellect or
success roll.

## Runtime Ownership

### Headless Server

The Godot server runs authoritatively, ultimately in its isolated headless
container and fixed simulation tick. It MUST own:

- peer identity and Player ownership;
- monotonic action ordering, replay protection, cooldowns, and state machines;
- vessel redistribution and progression evidence;
- all effective-stat, Metabolism, Mental Focus, perceptual-cue eligibility, and
	 environmental/execution-profile derivation;
- stamina, health, stagger, Kinetic energy, Meridian, Burnout, and magic state;
- collision queries, hit resolution, damage, impulse, and permanent physical
	world events;
- sector request orchestration, blueprint validation, Canon writes, and Canon
	mutation authorization;
- authoritative timestamps/ticks, tuning versions, schema versions, rejection
	reasons, and audit telemetry.

The server MUST reject non-finite numbers, values outside schema bounds,
unknown enum values, stale or duplicate sequences, impossible transitions,
wrong-owner references, future timestamps, incompatible schema/tuning versions,
and client-supplied outcome fields.

### Local Client

The client MAY:

- sample controls and submit compact intents;
- predict reversible locomotion, animation, camera, VFX, and input feedback;
- display replicated base/effective stats, resources, cooldowns, and outcomes;
- render server-approved authored perception cues and enemy telegraphs without
	 interpreting or acting on them for the human;
- interpolate remote Players and reconcile its local prediction to server state.

The client MUST NOT award training, redistribute vessel points, calculate a
trusted hit, claim damage, unlock a Meridian, end Burnout, restore stamina,
approve a spell, write Canon, or directly contact Ollama or SQLite. Predicted
feedback MUST be disposable and visibly corrected when rejected.

### Shared Contracts

`shared/` owns versioned value contracts, enums, bounded parsing, and pure
deterministic helpers that both processes must interpret identically. Shared
code MUST NOT imply shared authority. Secrets, database handles, Ollama access,
authoritative clocks, and mutable progression repositories remain server-only.

## Six-Node Biological Vessel

The persistent vessel is a six-axis spider/radar graph with a fixed total area
budget. It contains exactly these core attributes:

| Node | Meaning | Evidence that may train it | Governs |
| --- | --- | --- | --- |
| `STR` | Strength; muscle density | Using heavy weapons, including a 40 lb hammer | Mass carry capacity and physical strike power |
| `DEX` | Dexterity; reflexes and flexibility | Fencing with rapiers and rapid fist combinations | Execution frames and step distances |
| `CON` | Constitution; durability | Absorbing valid damage | Raw physical health pool |
| `INT` | Intelligence; analytical logic expressed through mechanism handling | Operating complex dungeon mechanisms | Physical mechanism analysis/handling and timing assistance, never puzzle correctness |
| `WIS` | Wisdom; spatial perception | Exploring validated hidden tiles and layout corners | Spatial awareness and embodied traversal affordances, never discovery truth or solution acceptance |
| `CHA` | Charisma; internal presence | Interacting with faction leaders and imposing intent | Strength/duration of expressed faction intent, never access to an idea the player already chose |

`MET` is not a seventh core vessel node, and there is no independent Logic or
Perception node. In friction and combat execution contracts, `MET` means
**Metabolism**, a derived physiological value computed from vessel, Kinetic,
status, and tuning inputs. **Mental Focus** is a separate derived value named
`mental_focus`; it may expand execution windows or affect concentration
efficiency. Neither derived value may decide whether an intellectual answer,
dialogue intent, clue interpretation, or puzzle solution is correct.

### Fixed-Budget Redistribution

An accepted training gain pulls one graph vector outward and deterministically
compresses opposing vectors so the configured total vessel budget is preserved.
The server MUST:

1. validate progression evidence and deduplicate its event id;
2. load the event's versioned gain curve and opposition-weight row;
3. apply the bounded gain to its target node;
4. redistribute the required amount across eligible opposing nodes using the
	 configured deterministic weights and floor rules;
5. normalize once to the exact configured budget using deterministic rounding;
6. reject the transaction if any value is non-finite, negative, above its
	 configured bound, or cannot preserve the budget;
7. commit the complete vessel revision atomically and replicate the result.

The spider chart is a view of authoritative values, not a client-editable input.
Training counters do not themselves grant points; they are server evidence used
by a versioned progression rule. Final budgets, gains, weights, caps, and
thresholds are tuning data, not architectural constants.

## Inverse Biological Friction

Over-training has mandatory opportunity costs computed from effective vessel
state. Trigger conditions and curves are versioned tuning data.

### Massive Bulk: High STR And High CON

Muscle density and skeletal frames thicken. The derived modifier set MUST:

- shrink dodge distance;
- increase weapon-animation wind-down and recovery frames;
- remove surface buoyancy so the Player sinks directly to the water floor-bed;
- drain stamina rapidly while the Player marches along that floor-bed.

### Fragile Agility: High DEX And High MET (Metabolism)

The Player sheds structural mass for reflex velocity. The derived modifier set
MUST:

- regenerate stamina almost instantly;
- permit a brief, bounded skip across a water surface before sinking;
- reduce physical stun/stagger resistance to effectively zero;
- turn even a valid stray-trap hit into a catastrophic prolonged stagger.

When multiple profiles or temporary effects overlap, the server MUST combine
them in a documented deterministic order from the tuning version. The client
MUST render the replicated result, not independently select the winning curve.

## Kinetic Flow Layer

Kinetic state contains three derived nodes:

- **Kinetic Volume** is internal energy capacity, backed tightly by `CON`.
	High Volume provides a large reservoir. When Control is low, energy sloshes
	inefficiently and inflates authoritative stamina/energy action costs.
- **Kinetic Control** is surgical force efficiency, backed heavily by `DEX`.
	High Control can bypass fluid drag and sustain long vertical or horizontal
	wall-runs for a small energy cost.
- **Kinetic Output** is explosive venting capability, driven by `STR`. It can
	convert a basic action into a directional cataclysm; for example, a falling
	vertical leap may transfer momentum into a supersonic ground slam that
	shatters adjacent eligible grid colliders.

Every Kinetic action MUST resolve from authoritative position, velocity,
environment contacts, current energy, effective nodes, active status, and
tuning version. Destructive output MUST target server-owned collider ids and
emit validated physical mutation events; clients cannot name arbitrary objects
to destroy.

## Meridian Pathways

Repeated, server-observed cross-training can permanently burn a Meridian
channel between vessel nodes:

- **Impact Meridian (`STR + CON`)** directs Volume into muscle frames and can
	temporarily harden skin density enough to parry a mountain-cleaving blow
	bare-handed.
- **Flow Meridian (`DEX + WIS`)** directs Control through nervous pathways,
	enabling water-resistance manipulation and double-jump air-weight
	redistribution.
- **Spark Meridian (`STR + DEX`)** directs Output into velocity acceleration,
	producing momentum multipliers from authoritative weapon-weight vectors.

Meridian progress MUST be driven by deduplicated cross-training evidence, not
raw client counters. Unlock evaluation MUST be deterministic and idempotent:
replaying the same evidence cannot increment progress or emit a second unlock.
Unlocks are durable; activation costs, effects, and temporary status remain
runtime state. Final evidence requirements and thresholds belong to tuning.

## Biological Burnout

Pushing maximum Output through one pathway is an **Overload Surge**. Once the
server accepts the Surge, the targeted pathway enters Burnout from internal
friction. During its cooldown, effective `DEX` and Kinetic Control for the
affected pathway are flattened to zero.

Burnout MUST be represented as a temporary modifier with authoritative start
tick, end tick, pathway, source action, and tuning version. It MUST NOT write
zero into persistent vessel DEX, training history, or the unmodified Kinetic
derivation inputs. The server expires Burnout on its simulation clock, derives
the restored effective values, and replicates the transition. A client claim
that a cooldown ended, was shortened, or targets another pathway is invalid.

Normative lifecycle:

```text
READY -> SURGE_VALIDATING -> ACTIVE_SURGE -> BURNED_OUT -> RECOVERED -> READY
						 |                    |
						 +---- REJECTED <-----+
```

Only the server may enter `ACTIVE_SURGE`, `BURNED_OUT`, or `RECOVERED`.
Disconnect/reconnect MUST recover active Burnout from authoritative state rather
than clearing it.

## Magic Equilibrium And Opportunity Cost

Magic requires bodily equilibrium. Muscle mass and physical bulk act as an
electrical insulator that grounds magical currents. A hyper-bulked Brute
Juggernaut cannot channel magical configurations successfully. Depending on the
validated spell/tuning contract, an attempt MUST resolve as either `FIZZLE` or
`BACKLASH`, never as a client-selected success.

High-tier magic requires physical space on the vessel scale. The Player must
organically lean out, exchanging brute-force armor and force thresholds for
precise concentration. The server computes equilibrium eligibility from the
authoritative vessel, effective modifiers, status, requested spell tier, and
tuning version. This architecture defines no spell list, mana constants, or
final threshold. Failure MUST be explicit and replicated with a bounded reason;
it MUST NOT silently consume an accepted request without an outcome.

## Versioned Data Contracts

All identifiers are opaque stable strings unless a narrower server-owned type
is introduced. All numeric fields MUST be finite and bounded by the matching
schema/tuning version. Dictionaries received over the network or from Ollama
are untrusted until parsed into validated typed state.

### `VesselProgressionState`

| Field | Type | Rule |
| --- | --- | --- |
| `schema_version` | integer | Supported positive version |
| `tuning_version` | string | Must resolve to immutable server tuning |
| `player_id` | string | Must match server-owned Player identity |
| `revision` | integer | Monotonic server revision |
| `base_nodes` | map of six enum keys to number | Exactly STR/DEX/CON/INT/WIS/CHA; finite, bounded, fixed total budget |
| `training_totals` | map of evidence kind to number | Server-derived, non-negative, bounded |
| `applied_event_ids` | durable dedup reference | Prevents repeated progression application |

### `EffectiveMechanicsSnapshot`

| Field | Type | Rule |
| --- | --- | --- |
| `source_revision` | integer | Vessel revision used for derivation |
| `server_tick` | integer | Authoritative tick |
| `effective_nodes` | six-node map | Derived, never persisted over base nodes |
| `metabolism` | number | Derived physiological MET used by regeneration and physical execution profiles |
| `mental_focus` | number | Separate derived Focus value; never a puzzle correctness input |
| `modifiers` | typed map | Dodge, recovery, buoyancy, stagger, stamina, traversal, armor, and magic effects |
| `active_effect_ids` | array of strings | Server-known status references only |

### `PerceptualCueState`

| Field | Type | Rule |
| --- | --- | --- |
| `cue_id` | string | References authored environmental evidence, never a generated answer |
| `world_object_id` | string | Must resolve to an authoritative object visible to the Player |
| `presentation_tier` | enum | Server-selected bounded visual/audio intensity tier |
| `eligible_player_id` | string | Owning recipient; must match the replicated peer |
| `source_revision` | integer | Effective-state/world revision used for eligibility |
| `expires_at_tick` | nullable integer | Server-owned when the cue is temporary |

The client may render this state but cannot promote its tier. Cue eligibility
MUST NOT mutate puzzle state or identify a solution.

### `ExecutionProfile`

| Field | Type | Rule |
| --- | --- | --- |
| `profile_id` | string | Server-generated result identity |
| `action_id` | string | Accepted authoritative action |
| `effective_dexterity` | number | Snapshot input, never supplied by the client |
| `effective_metabolism` | number | Snapshot input, distinct from Mental Focus |
| `invulnerability_start_tick`, `invulnerability_end_tick` | integers | Bounded authoritative interval; end is not before start |
| `movement_distance` | number | Finite, bounded physical displacement allowance |
| `recovery_end_tick` | integer | Authoritative action recovery boundary |
| `source_revision` | integer | Effective-state and tuning provenance |

Execution-profile fields are results. A client intent may request `DODGE` and a
direction but MUST NOT submit trusted invulnerability frames, slide distance,
or recovery timing.

### `KineticState`

| Field | Type | Rule |
| --- | --- | --- |
| `volume_capacity` | number | Derived primarily from CON |
| `control_efficiency` | number | Derived primarily from DEX; effective value may be zeroed by Burnout |
| `output_limit` | number | Derived primarily from STR |
| `energy_current` | number | Server-owned, between zero and current capacity |
| `derivation_revision` | integer | Matches effective snapshot/tuning inputs |

### `MeridianState`

| Field | Type | Rule |
| --- | --- | --- |
| `pathway` | enum | `IMPACT`, `FLOW`, or `SPARK` |
| `progress` | number | Server-derived from accepted cross-training evidence |
| `unlocked` | boolean | Monotonic durable transition |
| `unlocked_by_event_id` | nullable string | Required exactly when unlocked |
| `revision` | integer | Monotonic and idempotent |

### `BurnoutInstance`

| Field | Type | Rule |
| --- | --- | --- |
| `burnout_id` | string | Server-generated idempotency key |
| `pathway` | Meridian enum | Path actually overloaded |
| `source_action_id` | string | Accepted Overload Surge result |
| `start_tick`, `end_tick` | integers | Server ticks; end strictly after start |
| `state` | enum | `BURNED_OUT` or `RECOVERED` in replicated state |
| `tuning_version` | string | Immutable rule source |

### `ActionIntent` And `ActionResolution`

`ActionIntent` contains `schema_version`, `player_id`, `sequence`,
`client_tick`, `action_kind`, bounded directional/target inputs, and an optional
prediction id. It MUST NOT contain trusted damage, success, progression,
cooldown, unlock, or mutation results.

`ActionResolution` contains the server action id/tick, acknowledged sequence,
`ACCEPTED` or `REJECTED`, a bounded reason enum, authoritative resource costs,
state transitions, an optional execution-profile id, hit/impulse/mutation
references, progression-event ids, and the resulting revision. Duplicate
intents return or reference the original resolution and MUST NOT apply effects
twice.

### `ProgressionEvidenceEvent`

Fields are `event_id`, `player_id`, authoritative `server_tick`, `kind`,
validated source/action/world references, bounded magnitude, target node(s),
and `tuning_version`. The server emits these only after the underlying event is
accepted. Self-damage, repeated mechanism toggling, synthetic movement, and
other farming patterns MUST be constrained by future event-specific rules and
observable rejection reasons.

### `MagicChannelAttempt` And `MagicChannelResult`

The attempt contains intent identity, spell configuration id/tier, sequence,
and bounded targeting input. The result contains authoritative equilibrium
inputs/revision, resource cost, and one outcome: `CHANNELED`, `FIZZLE`,
`BACKLASH`, or `REJECTED`, with a reason enum. Clients cannot submit equilibrium
scores or choose the failure mode.

### `CanonMutationEvent`

Fields are `event_id`, `sector_id`, stable target GUID, mutation kind, bounded
payload, causing Player/action id, authoritative tick, expected Canon revision,
and schema version. The server MUST verify the target exists, the physical event
occurred, the mutation is allowed, and the expected revision matches. Applying
an event is transactional and idempotent.

## Intent Validation And Resolution

For every gameplay intent, the server MUST validate in this order:

1. supported schema and tuning version;
2. authenticated peer owns the referenced Player;
3. sequence is monotonic or a recognized idempotent replay;
4. fields, enums, vectors, and magnitudes are finite and bounded;
5. action exists and is legal in the current state;
6. authoritative timing, cooldown, resources, equipment, and status permit it;
7. authoritative position, environment, target, collision, and line/range rules
	 permit it;
8. requested transition is valid for the action state machine;
9. resulting effects can commit atomically.

Normative action lifecycle:

```text
RECEIVED -> VALIDATING -> ACCEPTED -> RESOLVING -> COMMITTED -> REPLICATED
									|           |           |
									+-------> REJECTED <-----+
```

Rejection is a first-class result. A rejected intent MUST have no partial
combat, progression, resource, unlock, or Canon side effect. Transport retries
MUST use stable idempotency identity. Client clocks may inform prediction but
never authorize cooldown or range.

## JIT Generation And Permanent Canon

The server requests a new sector asynchronously only when authoritative player
proximity reaches an unexplored boundary. The live multiplayer loop MUST remain
responsive while generation is pending or fails.

The server-side integration posts a strict JSON structural request to local
Ollama at `127.0.0.1:11434`, targeting Llama-3-8B on the NVIDIA Tesla P100. The
model returns data dictionaries, never scripts or executable scene content.
The target schema covers bounded tile coordinates, starting positions, and
quest-target placements. Every field requires explicit kind, cardinality,
bounds, referential, and cross-field validation before use.

Current Slice 008 validation covers versioned bounded sector coordinates and
floor/wall/corridor tiles. Current Slice 009 stores accepted provisional results
in memory. Starting positions, quest targets, geometry, SQLite storage, and
Canon mutation remain future versions/slices.

Normative sector lifecycle:

```text
UNKNOWN -> REQUESTED -> PROVISIONAL -> VALIDATED -> CANONICALIZING -> CANON
							|              |              |
							+----------> FAILED <----------+
CANON -> MUTATION_VALIDATING -> CANON (new revision)
```

The first validated blueprint for a coordinate becomes frozen historical Canon
only after a successful atomic insert into the server-owned SQLite database.
Coordinate uniqueness MUST prevent competing first writes. Retries MUST return
the existing Canon row or a deterministic conflict outcome, never replace it.
After canonicalization, only validated physical player events, such as
destroying a bridge or clearing a faction camp, may create permanent mutations.
An LLM regeneration MUST NOT rewrite existing Canon.

## Persistence And Versioning

- Canon SQLite migrations, repositories, transactions, and backups are
	server-only and require their own SDD/ADR and rollback evidence.
- Future durable Player progression requires a separately designed
	server-owned repository; this document does not claim a backing store exists.
- Persisted records MUST carry schema and tuning provenance sufficient for
	deterministic load/migration. Unsupported versions fail closed with an
	observable recovery path; they are not guessed into the newest shape.
- Canon blueprint insertion and each mutation commit MUST be atomic. A failure
	leaves no partial durable record and does not publish a successful result.
- Stable ids and expected revisions provide idempotency and optimistic conflict
	detection across retries and reconnects.

## Telemetry And Andon Signals

Future public seams MUST emit structured, bounded telemetry for:

- action accepted/rejected, reason, latency, sequence, and tuning version;
- perceptual cue eligibility/tier and execution-profile revision without
	 recording inferred player knowledge;
- progression evidence accepted/rejected/deduplicated and vessel revision;
- friction profile activation and effective-modifier revision;
- Meridian progress/unlock and duplicate suppression;
- Surge, Burnout start/expiry, and impossible transition rejection;
- magic channel outcome, equilibrium rejection reason, and backlash/fizzle;
- sector request, timeout/transport/schema outcome, correlation id, and queue
	duration;
- Canon insert, duplicate/conflict, mutation, transaction rollback, and
	revision mismatch.

Stop the line on non-finite state, budget drift, a client-authored outcome,
duplicate side effects, base-state mutation by a temporary effect, an
unauthorized world mutation, provisional data presented as Canon, incompatible
versions, missing validation evidence, or authoritative/client divergence that
does not reconcile within its tested bound.

Telemetry MUST avoid prompts containing sensitive player text, secrets, raw
database handles, and unbounded payloads.

## Implementation Placement

- `server/`: authoritative action resolution, progression evidence and vessel
	services, derived Metabolism/Focus and execution profiles,
	Kinetic/Meridian/Burnout state, perceptual-cue eligibility, magic validation,
	boundary detection, Canon repositories/migrations, and mutation transactions.
- `client/`: input adapters, prediction buffers, animation/rendering, HUD and
	radar visualization, authored cue/telegraph presentation, local time-dilation
	presentation, interpolation, rejection feedback, and reconciliation.
- `shared/`: versioned schemas, enums, validated value objects, tuning-resource
	shapes, deterministic pure derivation helpers, and network DTO parsing.
- `tests/unit/`: pure schema, derivation, fixed-budget, modifier-order,
	idempotency, and transition tests.
- `tests/integration/`: client-intent/server-result contracts, adversarial RPC
	validation, reconnect/cooldown behavior, async generation, and persistence
	transaction boundaries.

Use strict GDScript 2.0 static types. Prefer typed Resources/RefCounted value
objects and explicit result enums over loosely shaped Dictionaries after an
input boundary. Do not create one subclass per weapon or effect when a bounded
data-driven archetype and authoritative resolver can express the variation.

## Required Test Seams

Each future implementation slice MUST start with a public-seam failing test and
cover its normal path, highest-risk edge, rejection path, and idempotent replay.
At minimum, the complete system requires evidence that:

- correct puzzle solutions succeed across low/high INT, WIS, Metabolism, and
	Mental Focus states;
- WIS changes only authored clue presentation while the human retains
	observation and deduction responsibility;
- dodge input remains attemptable across valid builds while authoritative
	DEX/Metabolism changes invulnerability frames and slide distance;
- vessel gains preserve the fixed budget and deterministic opposition rules;
- invalid or duplicated progression evidence cannot grant state twice;
- bulk and fragile-agility penalties produce their required traversal,
	recovery, stamina, buoyancy, and stagger consequences;
- Kinetic costs reflect Volume/Control and destructive Output cannot target an
	ineligible collider;
- Meridian unlocks are permanent and idempotent;
- Burnout zeros only effective pathway DEX/Control and restores by server tick
	without changing persistent values;
- magic equilibrium produces deterministic channel/fizzle/backlash outcomes;
- duplicate/stale/impossible action intents have no side effects;
- predicted client feedback reconciles to accepted and rejected server results;
- malformed or incompatible LLM JSON never creates gameplay state;
- a provisional sector is not Canon, first-write Canon is immutable, and
	mutation replay is idempotent and revision-checked.

Run the narrowest GUT seam first, then `scripts/run_gut_validation.sh`. Runtime,
container, database, or physical-client claims require evidence in the matching
environment; unit tests alone do not prove them.

## Explicitly Open Design Space

This contract deliberately does not choose final formulas, thresholds,
durations, combat content, spell catalogs, UI, art, audio, inventory, equipment
persistence, enemy AI, PvP rules, or production hit geometry. The five decision
tickets under `.scratch/melee-combat/` remain open. Their eventual decisions
MUST conform to this authority and state model and MUST be delivered through
the repository workflow rather than embedded here as unvalidated assumptions.
