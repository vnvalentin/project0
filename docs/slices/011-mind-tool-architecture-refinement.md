# Slice 011: Mind versus Tool architecture refinement
GitHub issue: #95

Status: complete

Tracker context: Phase 7 - Delivery workflow capabilities; refines
[F-007](../FEATURE-LIST.md#f-007-living-architecture-anchor) and constrains
[P-016](../FEATURE-LIST.md#p-016-biological-progression-and-kinetic-combat-systems).

Planning ticket: [Mind versus Tool architecture refinement](../../.scratch/game-vision/issues/18-mind-tool-architecture-refinement.md).

## SDD

Goal: make the player-intellect/Player-body separation explicit and correct the
derived-state vocabulary without changing the six-node vessel.

Public seam: root `CLAUDE.md` and
[ADR 0002](../adr/0002-authoritative-mechanics-and-progression.md).

Invariants:

- Correct reasoning is never gated by INT, WIS, Perception, Logic, Focus, or
  any hidden roll.
- Perception modifiers may expose authored sensory evidence but never select an
  answer or conceal the only logically necessary fact.
- `metabolism` and `mental_focus` are separate derived values; neither is a
  seventh vessel node.
- Combat stats modify execution physics after an input, not whether the human
  was allowed to recognize or attempt the action.

## BDD

### Environmental clue

Given an authored hidden-trap clue exists
When a replicated perception modifier crosses its tuning threshold
Then the client may render a subtle floor crack, but the system does not label,
solve, or automatically avoid the trap for the player.

### Correct puzzle solution

Given the human has deduced a valid mechanism sequence
When the server validates the physical interaction and world state
Then the solution executes without an attribute or hidden-roll check.

### Combat response

Given the human reads a boss telegraph and submits dodge input
When the server validates the action
Then effective Dexterity and Metabolism determine bounded invulnerability frames
and slide distance, but no stat decides whether the input may be attempted.

### Focus and alternative physics

Given a lever starts a closing-gate challenge
When the action resolves
Then Mental Focus may expand the execution window, while low Focus preserves
the same solution and permits alternatives such as tipping a stone pillar over
the gap.

## Validation

Focused documentation check:

```bash
required=("Mind Versus Tool Architecture" "The Player's Domain: The Mind" "The Player's Domain: The Tool" "enemy telegraph" "calculating combat position" "subtle crack" "hidden spike trap" "three-second" "closing gate" "stone pillar" "Metabolism" 'mental_focus' "invulnerability frames" "slide distance" "PerceptualCueState" "ExecutionProfile" "effective_metabolism"); for term in "${required[@]}"; do grep -Fq -- "$term" CLAUDE.md || { printf 'missing: %s\n' "$term"; exit 1; }; done; grep -Fq 'derived Metabolism' docs/adr/0002-authoritative-mechanics-and-progression.md && grep -Fq 'Mental Focus is a separate derived value' docs/adr/0002-authoritative-mechanics-and-progression.md && ! grep -Fq 'MET means **Mental Focus**' CLAUDE.md docs/adr/0002-authoritative-mechanics-and-progression.md && ! grep -Fq '`mental_focus` | number | Derived MET' CLAUDE.md && ! grep -nE '\{\{[^}]*\}\}' CLAUDE.md docs/slices/011-mind-tool-architecture-refinement.md .scratch/game-vision/issues/18-mind-tool-architecture-refinement.md
```

Result: PASS, exit 0. Slice 011 local Markdown links resolve.

Full regression: `scripts/run_gut_validation.sh` passed 23/23 tests and 70
assertions with exit 0. `build/validation/gut.xml` reports 23 tests and zero
failures; `build/validation/validation-summary.json` reports `status: passed`
and `exit_code: 0`.

Review outcome: accepted. Mind and Tool responsibilities are explicit;
Metabolism and Mental Focus are distinct derived values; no seventh vessel node
or intellectual permission check was introduced.

## ADR decision

No new ADR. This slice corrects and sharpens the terminology in accepted ADR
0002 without changing its server-authority or persistent/effective-state
decision.

## Non-goals

No gameplay implementation, tuning formulas, balance constants, assets,
database changes, or resolution of `.scratch/melee-combat/` tickets.
