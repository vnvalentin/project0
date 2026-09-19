---
status: proposed
---

# Versioned embodiment mechanics architecture: six-node vessel, tuning contract, and redistribution

Phase 15 implements the biological progression layer (vessel attributes, progression, derived stats, friction, kinetics, meridians, burnout, magic). Without explicit decisions on versioning, storage, and redistribution, individual slices could fragment on how balance values are authored, versioned, and persisted — breaking reproducibility and eventual admin-config goals. This ADR locks the shape decisions so all six embodiment subsystems share one consistent architecture.

## Context

The Embodiment Mechanics Design Map ([#219](https://github.com/vnvalentin/project0/issues/219)) identified five frontier decisions needed before Phase-15 slicing. The map is now charted:

- **Tuning-resource contract** ([#220](https://github.com/vnvalentin/project0/issues/220)): what form, versions, and access seam does embodiment tuning use?
- **Section-1 reconciliation** ([#222](https://github.com/vnvalentin/project0/issues/222)): does the spec (docs/SYSTEMS-SPECIFICATION.md) subsume the Master Spec markdown and resolve naming ambiguities?
- **Redistribution algorithm** ([#223](https://github.com/vnvalentin/project0/issues/223)): how exactly do opposition-weight compression, floor handling, and rejection work?
- **Delivery sequence** ([#224](https://github.com/vnvalentin/project0/issues/224)): what slicing strategy and first-slice seam unblocks the full subsystem build?

Grilling decisions are locked; this ADR records the shape contract all six Phase-15 subsystems (vessel foundation, friction, kinetic, meridian, burnout, magic) build against.

## Decision

### Versioned Tuning Resource

1. **Storage form**: Embodiment tuning constants are **baked as `const` tables inside a `RefCounted` `class_name` GDScript** (e.g., `server/embodiment_tuning.gd`), matching the repo's established idiom (`world_scale.gd`). Shaped as a **versioned registry behind a fail-closed `EmbodimentTuning.resolve(tuning_version)` seam**, so the storage source can later swap to admin-config/external without changing any consumer. This choice is reversible, not a lock-in.

2. **Version fields**: Two independent version fields, per docs/SYSTEMS-SPECIFICATION.md:
   - **`schema_version: int`** — bumped when the tuning *structure* changes (new fields, new subsystem sections, rearrangement). Matches the repo's all-integer schema convention.
   - **`tuning_version: String`** — opaque immutable identifier (e.g., `"vessel-2026q4-highmagic"`), stamped onto derived state for provenance. This is the key `resolve()` looks up and fits the future admin-config direction (named, non-numeric tuning sets).

3. **Scope**: One embodiment tuning set, one `tuning_version`, **internally namespaced by subsystem** (vessel/kinetic/friction/meridian/burnout/magic). One immutable provenance stamp; a bump re-freezes the whole set. The internal namespacing is shaped to allow finer per-subsystem granularity later (future fog) without reworking the single-stamp provenance model.

4. **Access seam**: `EmbodimentTuning.resolve(tuning_version: String) -> {outcome: String, detail: String, tuning: RefCounted | null}` is the **sole, fail-closed** access path; subsystems never read `const` tables directly. Unknown/unsupported `tuning_version` → `unsupported_tuning_version` outcome, no fallback guess. **Server refuses to start** on unresolved default tuning (Jidoka: fail-closed, never boot a mis-tuned authoritative world). Startup failure is **operator-facing only** (Andon/telemetry), never surfaced as a player-facing error (Zen Validation).

5. **Placement**: 
   - **`shared/embodiment_tuning_schema.gd`**: bounds (`const MAX_*` / `SUPPORTED_*`), outcome enums, and **pure derivation helpers** (no state mutations). Both processes interpret identically.
   - **`server/embodiment_tuning.gd`**: frozen numeric tables + the `resolve()` registry. Server-owned; tuning values never ship to or are authored by the client.
   - **Client receives only replicated derived results** (`EffectiveMechanicsSnapshot`), never the tuning tables.

### Fixed-Budget Vessel Redistribution

The spec mandates a 7-step redistribution sequence per vessel gain: validate evidence → load versioned gain curve + opposition-weight row → apply bounded gain → redistribute across eligible opposers → normalize to budget → reject if impossible → commit atomically. This ADR specifies the shape details:

1. **Opposition-weight structure**: For each trainable node, a tuning-owned row of non-negative weights over the other five nodes; **weight 0 = node is not compressed (ineligible)**. A pure tuning table behind `resolve()`. This delivers the "organic compression of opposing vectors" feel (a heavy-STR build compresses DEX/CON differently than INT) without code churn on rebalance.

2. **Floor handling**: **Clamp + deterministic re-spread** — when compression would push an opposing node below its floor, clamp it at floor, then deterministically re-spread the leftover deficit across *still-eligible* nodes (above floor, non-zero weight, weights renormalized, fixed node iteration order). **Reject only when no eligible capacity remains** (every opposer floored → budget cannot be preserved). This minimizes player-facing dead-ends while reserving rejection for the genuinely impossible case.

3. **Rejection semantics**: Reject = **atomic no-op**; the event_id is recorded in the dedup ledger with its **terminal outcome** (idempotent replay returns the same rejection, never re-applies or loops); nothing else commits; bounded **operator** telemetry emitted. Player-facing: a benign **"at capacity / no change"** signal, never an error or Andon (Zen Validation — a designed limit is never the player's fault).

4. **Retuning and earned progression** (constraint from tuning-contract decision):
   - Earned `base_nodes` are **frozen durable state — never retroactively recomputed** by a tuning change. What the player worked for stays exactly as earned.
   - A vessel revision is **pinned to the `tuning_version` it was built under**; future training gains on that vessel are evaluated with that pinned tuning (its budget, weights, floors) **until an explicit, bounded, opt-in migration** re-pins it to newer tuning.
   - **Effective derivation (runtime power) uses current tuning.** Balance changes flow through the *effective* snapshot — transparently and universally to everyone — which is the intended balance lever and is not a targeted retroactive nerf.
   - Migration, if ever offered, is deliberate and bounded (natural fit for the future server-admin config surface), not automatic.
   - **Zen-Validation line**: you keep the graph you earned (`base_nodes`); how it *plays* may rebalance (`effective_nodes`), but that rebalance is transparent and applies to all, never a retroactive edit of your saved progression.

### Delivery Architecture

Phase 15 slices in a **hybrid** sequence:

1. **L1+L2 foundation (first slice, P-016-A)**: `VesselProgressionState` + `EffectiveMechanicsSnapshot` data contracts, server-authoritative progression acceptance, effective-snapshot derivation and **deterministic replication to client**, plus a bounded **headless scene assertion** verifying end-to-end works (train evidence → compute effective nodes → replicate → assert determinism). No art/UI/gameplay features yet; proof the whole path works and downstream slices have a live, replicated read-model. Always-green.

2. **Thin vertical subsystem slices (P-016-B onwards, in dependency order)**:
   - P-016-B: Inverse friction modifier derivation (Massive Bulk / Fragile Agility).
   - P-016-C (parallel): Kinetic Flow layer (Volume/Control/Output).
   - P-016-D: Meridian pathways (cross-training evidence → unlock).
   - P-016-E: Biological Burnout (Overload Surge → pathway flattened).
   - P-016-F: Magic equilibrium (insulation → fizzle/backlash).

Each slice adds one falsifiable hypothesis, tested immediately and shipped green.

## Consequences

- **Embodiment machinery is now unified and versioned.** All six subsystems inherit one schema/tuning contract, one opposition-weight seam, one retuning fairness model, and one replication seam. No ad-hoc decision-making per subsystem.

- **Server tuning is immutable and reproducible.** The `tuning_version` stamp ensures any derived state can be re-derived identically later (critical for bug reproduction, balance audits, and player trust). Automatic tuning bumps never happen; migrations are opt-in and bounded.

- **Future admin config is unblocked.** The `resolve()` seam permits swapping from baked `const` to external/admin-config sources without changing consumers. The named `tuning_version` string fits admin-selected or experiment-branch tuning sets naturally.

- **Progression is fair and transparent.** Players keep what they earned; balance rebalances are transparent and universal, never retroactive punishments. The two-version model (`base_nodes` pinned to build-time tuning, `effective_nodes` using live tuning) keeps both.

- **Each subsystem slice is independently testable.** L1+L2 seam is the shared API; friction/kinetic/meridian/burnout/magic build cleanly atop it with minimal churn. Thin vertical slices mean tight feedback loops and early risk reduction.

- **New tuning concepts require no new architecture.** Future deep-tuning (per-subsystem granularity, per-pathway modifiers, etc.) add to the internal namespace and the opposition-weight table shape, not new seams.

### Follow-up work

- **ADR details**: The vessel/tuning-architecture shape is locked. Any subsystem-specific elaboration (e.g., exact Kinetic derivation formula, Burnout expiry semantics, magic equilibrium thresholds) belongs in that subsystem's slice record, not here.

- **Server-admin console (Phase 17 fog)**: The tuning-version string and the `resolve()` seam are the choke points for future admin-config surfaces. Link this ADR from those later tickets.

- **Migration strategy** (Phase-17 fog): Decide how and when vessel migrations between tuning versions are offered/forced (probably alongside tuning bumps); model it as a separate deferred choice once live tuning changes happen.

- **Slicing**: P-016-A through P-016-F are the Phase-15 slice sequence. Each slice record links back to this ADR for architecture and links to the closed map tickets for the grilling decisions.
