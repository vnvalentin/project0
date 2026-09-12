Type: grilling
Status: closed (assigned: Copilot)
Blocked by: None

## Question

Given the resolved melee exchange, authority model, weapon archetypes, and hit
rule, what is the smallest reversible implementation slice and public seam that
proves the first authoritative melee interaction?

Decide its explicit non-goals, safety invariant, telemetry/rejection behavior,
BDD scenarios, TDD public seam, focused validation command, and whether the
decision requires an ADR. This ticket produces the implementation handoff, not
the implementation itself.

## Resolution

The first authoritative melee slice is specified as follows:

### Slice Specification: `Slice 012 — Server-authoritative melee strike and hit registration`

1. **User Outcome**:
   - A connected player can press attack (LMB / Space), execute a responsive locally-predicted sword swing with server-enforced windup/active/recovery timing and movement slowdown, and receive an authoritative server-confirmed hit event when striking a stationary target dummy within reach and arc.

2. **Scope**:
   - `ActionIntent` carrying client sequence, tick, action kind (`MELEE_STRIKE`), and aim direction.
   - Authoritative server state machine tracking 60Hz simulation ticks: `WINDUP` (6 ticks) -> `ACTIVE` (4 ticks) -> `RECOVERY` (10 ticks) -> `IDLE`.
   - Locomotion speed penalty enforced authoritatively (0.5x windup, 0.8x recovery).
   - Deterministic vector-based reach (2.0m) and arc (±30°) query against a stationary `TargetDummy`.
   - Replicated `CombatEvent.HIT` with attacker peer ID, target ID, and impact coordinates, triggering a visual reaction on the client.
   - Monotonic sequence tracking and idempotent handling of duplicate/stale intents with bounded rejection codes.

3. **Explicit Non-Goals**:
   - No HP, damage math, floating combat text, or death/defeat states.
   - No inventory UI, equipment persistence, or weapon switching (default Generic Sword only).
   - No PvP player-on-player combat or moving target prediction.
   - No SQLite persistence, Ollama, or progression integration.

4. **Public Seams**:
   - **Shared**: `shared/combat_contracts.gd` (`ActionIntent`, `ActionResolution`, `CombatEvent`, `MeleeWeaponArchetype`).
   - **Server**: `server/server_player_state.gd` & `server/server_main.gd` (tick lifecycle, monotonic sequence arbitration, hit calculation).
   - **Client**: `client/networked_player_input.gd` & `client/player.gd` (intent capture, local prediction start, reconciliation).
   - **Target**: `client/target_dummy.gd` (visual hit feedback).
   - **Tests**:
     - `tests/unit/test_melee_combat_contracts.gd` (schema validation, sequence replay, geometric vector math).
     - `tests/integration/test_authoritative_melee_strike.gd` (networked intent -> server validation -> target hit confirmation).

5. **Validation Command**:
   - `scripts/run_gut_validation.sh` (or `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit,res://tests/integration -gexit`).
