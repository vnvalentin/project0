# Vision-to-Play Vertical Slice

Status: proposed; design and prototype only
Parent vision: [#495](https://github.com/vnvalentin/project0/issues/495)
Parent map: [Project0 Master Game Vision](map.md)

## User outcome

Two players can form a Party, enter one shared location, use movement as a
physical problem-solving language, complete a cooperative environmental
objective, receive a meaningful authoritative reward, and leave a persistent
world consequence that is visible when the location is revisited.

This is the smallest proof that the new vision is a game rather than only an
architecture: the Party, Mind versus Tool, traversal, semantic blueprint,
server authority, item, and Canon pillars all meet at one observable loop.

## Hypothesis

If a fixture-backed semantic blueprint can drive a deterministic location and
its puzzle state, then a Party can experience the intended gameplay loop before
we choose a live model runtime, message bus, persistence product, or final map
builder. The result will show which contracts are real and which assumptions
need revision.

## Scope

- A Party with two Characters and explicit membership/presence distinction.
- One bounded location represented by a portable semantic World blueprint.
- One cooperative environmental puzzle with at least two traversal approaches.
- At least two traversal actions chosen from jump, dodge, slide, swim, crawl,
  climb, or another existing movement capability.
- Server-authoritative movement, puzzle state, completion, reward, and world
  mutation.
- One meaningful item or material reward represented as an owned item instance.
- One revisit path that exposes the resulting world mutation.
- Fixture-backed DM or blueprint proposals; live LLM inference is not required.
- Focused public-seam tests and a bounded runtime or integration check.

## Explicit non-goals

- No live World, Party, or Personal DM service.
- No final LLM prompt, model, vector store, message bus, or database choice.
- No complete quest graph, dungeon generator, crafting system, home builder,
  town builder, faction simulation, or settlement economy.
- No new sharding, streaming, or production-scale capacity work.
- No replacement of existing Character, movement, account, or multiplayer
  contracts unless the prototype falsifies them.
- No stat gate that prevents a player from understanding or attempting the
  puzzle. Character state may change execution timing, distance, cost, or risk.

## Domain boundary

The slice crosses these boundaries:

- **Party:** membership, presence, shared participation, and encounter scope.
- **World blueprint:** semantic location intent, puzzle relationships, and
  bounded builder inputs.
- **Traversal:** player-directed movement actions and their physical profile.
- **Authority:** validation and deterministic resolution of movement, puzzle,
  reward, and mutation outcomes.
- **Items:** owned item-instance creation and reward attribution.
- **Canon:** accepted location state plus an idempotent world mutation.

## Public seam

The implementation handoff must expose a technology-neutral flow equivalent to:

```text
Party intent -> proposal/blueprint validation -> deterministic location
-> traversal and interaction intents -> authoritative puzzle resolution
-> item/reward mutation -> persistent world event -> revisit projection
```

The seam must make correlation, actor, Party, location revision, input order,
accepted outcome, rejection reason, and idempotency observable. It must not
require an LLM to run during a frame or allow a client to author an outcome.

## Safety and authority invariants

- The server owns Party membership, presence, movement outcome, puzzle state,
  item ownership, reward attribution, and world mutation.
- A disconnected Character does not silently become a Party leaver.
- A reward is granted at most once for one accepted puzzle completion.
- Replayed or reordered intents cannot create duplicate rewards or mutations.
- A blueprint or DM proposal cannot bypass schema, spatial, or gameplay
  validation.
- A player can solve the puzzle through observation and reasoning; attributes
  and equipment modify execution rather than permission.
- A revisit observes the accepted mutation and never reloads the pre-mutation
  state as authoritative truth.
- Failure or timeout leaves the Party and Canon in a recoverable state.

## Acceptance scenarios

### Shared traversal puzzle

Given two Characters are present in the same Party location, when they use
movement and interaction intents to manipulate the puzzle, then the
server-authoritative state reflects only valid physical interactions and both
clients observe the same result.

### Mind versus Tool

Given one Character has a different movement profile from the other, when both
attempt the same puzzle solution, then neither is blocked from understanding or
attempting it; only execution timing, distance, cost, or risk differs.

### Reward idempotency

Given the Party completes the puzzle, when the completion intent or network
message is repeated, then exactly one accepted reward item instance is created
and attributed according to the agreed reward rule.

### Persistent consequence

Given the Party completes the puzzle and causes a location mutation, when a
Character leaves and later revisits, then the location presents the mutated
state and does not regenerate the original state over it.

### Presence and reconnect

Given one Party member disconnects during or after the encounter, when that
Character reconnects, then Party membership and the accepted shared outcome
remain distinct and the Character receives the authoritative current state.

### Proposal failure

Given a malformed or physically invalid blueprint proposal, when it reaches
validation, then it is rejected or replaced by a bounded fixture fallback
without changing gameplay state or interrupting the multiplayer loop.

## Evidence required before promotion

- A resolved domain decision for Party encounter participation and reward
  attribution.
- A resolved blueprint and mutation contract with no renderer or storage
  dependency.
- A focused public-seam test for each acceptance scenario.
- A runtime or integration proof showing two clients receive the same accepted
  puzzle, reward, and revisit state.
- Validation evidence recorded in the eventual slice record.
- Updated Feature List, Project Tracker, and any relevant debt record only when
  the capability is promoted from prototype to implementation.

## Delivery stages

1. **Design:** resolve Party participation, puzzle state, reward ownership,
   mutation identity, and revisit behavior.
2. **Prototype:** run the loop with fixtures and existing movement seams; record
   what feels correct or fails.
3. **Contract:** write the stable public seam and failure/idempotency rules.
4. **Implementation handoff:** create the smallest implementation issue and
   slice record only after the contract is resolved.
5. **Evidence:** validate two-client behavior, reconnect, duplicate delivery,
   malformed proposal, and revisit persistence.

## Known dependencies

- Existing authoritative movement and locomotion contracts.
- Existing Party domain direction and Character/Vessel contracts.
- Existing World blueprint and provisional generation work.
- Existing item/content research before expanding reward and crafting rules.
- Telemetry correlation work for durable evidence across reconnect and relogin.

## Learning questions

- What is the smallest Party decision that must be shared versus personal?
- Does a puzzle mutation belong to the location, Party, World, or an explicit
  combination of scopes?
- Which traversal actions create genuine reasoning opportunities rather than
  cosmetic movement variety?
- What makes a reward meaningful without prematurely defining the full item or
  crafting economy?
- Which context must a Party DM eventually receive, and what can remain local?
