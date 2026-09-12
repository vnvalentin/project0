# Slice 010: Core mechanics architecture contract

Status: complete

Tracker context: Phase 7 - Delivery workflow capabilities; implements the
living architecture anchor and defines the contract for future Phase 10 and
Phase 12 work.

Planning ticket: [Core mechanics architecture contract](../../.scratch/game-vision/issues/17-core-mechanics-architecture.md).

## SDD

Goal: make the complete combat, biological progression, kinetic, magic, and
Canon rules available as a normative root architecture contract before those
systems are implemented.

Public seam: root `CLAUDE.md`, linked from the delivery records and governed by
[ADR 0002](../adr/0002-authoritative-mechanics-and-progression.md).

Safety invariants:

- Player reasoning and correct puzzle solutions are never stat-gated.
- The server alone owns accepted combat, progression, magic, cooldown, and
  persisted world outcomes.
- Temporary modifiers never overwrite earned vessel or progression state.
- LLM output is untrusted and cannot become Canon before server validation and
  atomic persistence.

Rollback: revert this documentation-only slice. No runtime data or migration is
created.

## BDD

### Correct puzzle solution

Given a player has deduced a valid puzzle solution
When the corresponding physical interaction reaches the authoritative server
Then the solution executes regardless of vessel attributes, while stats may
only alter physical affordances or the execution window.

### Untrusted client outcome

Given a client submits an action or progression intent
When it also claims resulting damage, stats, unlocks, cooldown completion, or a
Canon mutation
Then the server ignores or rejects the claimed result and computes any accepted
outcome from authoritative state.

### Temporary burnout

Given an Overload Surge burns out a Meridian pathway
When effective attributes are derived during its cooldown
Then effective DEX and Kinetic Control are flattened to zero for that pathway's
bounded window without mutating persistent base values.

### Provisional generated sector

Given Ollama returns a structurally valid provisional blueprint
When it has not yet been atomically written to the server-owned Canon store
Then it remains non-Canon and cannot be treated as durable world history.

## TDD and validation seam

This is a documentation-only slice. Its focused executable check scans
`CLAUDE.md` for the required sections and safety terms and verifies referenced
repository paths. Runtime regression uses `scripts/run_gut_validation.sh`,
which emits `build/validation/gut.xml` and
`build/validation/validation-summary.json`.

Focused validation:

```bash
required=("Current Reality And Target Contract" "Non-Negotiable Design Laws" "Six-Node Biological Vessel" "STR" "DEX" "CON" "INT" "WIS" "CHA" "Mental Focus" "not a seventh" "Inverse Biological Friction" "Massive Bulk" "Fragile Agility" "Kinetic Volume" "Kinetic Control" "Kinetic Output" "Impact Meridian" "Flow Meridian" "Spark Meridian" "Biological Burnout" "Overload Surge" "Magic Equilibrium" "VesselProgressionState" "EffectiveMechanicsSnapshot" "KineticState" "MeridianState" "BurnoutInstance" "ActionIntent" "ActionResolution" "ProgressionEvidenceEvent" "MagicChannelAttempt" "CanonMutationEvent" "JIT Generation And Permanent Canon" "Llama-3-8B" "Tesla P100" "starting positions" "quest-target" "SQLite" "lever" "closing gate" "pillar" "server owns outcomes"); for term in "${required[@]}"; do grep -Fq -- "$term" CLAUDE.md || { printf 'missing: %s\n' "$term"; exit 1; }; done && ! grep -nE '\{\{[^}]*\}\}' CLAUDE.md docs/slices/010-core-mechanics-architecture.md docs/adr/0002-authoritative-mechanics-and-progression.md .scratch/game-vision/issues/17-core-mechanics-architecture.md
```

Result: PASS, exit 0. A local Markdown-link target check also passed with exit
0; every link introduced by this slice resolves.

Full regression: `scripts/run_gut_validation.sh` passed 23/23 tests and 70
assertions with exit 0. `build/validation/gut.xml` reports 23 tests and zero
failures. `build/validation/validation-summary.json` records `status: passed`
and `exit_code: 0` at `2026-09-12T14:59:52Z`.

Review outcome: accepted. The specification preserves all supplied mechanics,
keeps `MET` derived rather than adding a vessel node, prohibits puzzle stat
gates, separates durable and effective state, and reconciles future Canon
requirements with the narrower Slice 008/009 implementation reality.

## ADR decision

ADR required. The contract fixes cross-cutting authority, state ownership,
temporary-versus-persistent state, and Canon boundaries that future slices
must not redefine locally. See
[ADR 0002](../adr/0002-authoritative-mechanics-and-progression.md).

## Telemetry and stop signals

This slice adds no runtime telemetry. The specification requires future public
seams to expose accepted/rejected outcomes and reasons. Missing required
mechanics, broken links, unresolved placeholders, or a failed GUT suite are
delivery stop signals.

## Non-goals

No application or test code, balance constants, formulas, migrations,
geometry, spell/content catalogs, audiovisual work, or closure of the existing
melee-planning tickets.
