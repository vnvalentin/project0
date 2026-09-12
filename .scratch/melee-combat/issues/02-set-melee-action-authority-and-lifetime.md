Type: grilling
Status: closed (assigned: Copilot)
Blocked by: None

## Question

What authority, ordering, validation, and timing rules govern a melee action
from client request through authoritative server outcome and replication?

Decide the boundary between responsive client feedback and server-owned combat
results, including how duplicate, stale, invalid, or impossible requests are
rejected. Decide whether the current server physics cadence is sufficient for a
first melee slice or which bounded runtime prerequisite must be delivered
first.

## Resolution

The authority, ordering, validation, and timing rules are resolved as follows:

1. **Action Intent Ordering & Validation**:
   - The server maintains monotonic sequence tracking per peer (`last_processed_sequence`).
   - Replayed/duplicate sequences return previous cached resolution idempotently without spawning a new swing.
   - Stale sequences or intents submitted while the Player state machine is busy (in windup/active/recovery or stunned) are rejected with explicit bounded reason codes (`REJECTED_BUSY`, `REJECTED_COOLDOWN`, `REJECTED_STALE`, `REJECTED_INVALID_STATE`).

2. **Authoritative Action State Machine & Fixed Tick Cadence**:
   - Attack lifecycles are counted deterministically in fixed simulation ticks (60Hz `_physics_process`) through discrete phases: `WINDUP_TICKS` -> `ACTIVE_TICKS` (hit detection window) -> `RECOVERY_TICKS` -> `IDLE`.
   - Hit testing is performed authoritatively during the `ACTIVE_TICKS` window at the server's current position and aim.

3. **Locomotion Arbitration**:
   - Movement velocity is multiplied on the server by the weapon archetype's phase-specific locomotion factor (e.g., Unarmed: 1.0x windup/recovery; Heavy: 0.0x windup, 0.2x recovery).
   - Any client prediction that drifts from this server-enforced penalty is reconciled automatically by snapshot reconciliation.

4. **Outcome Replication**:
   - Continuous state (current phase, active weapon, speed multiplier) is replicated in the regular peer snapshot.
   - Discrete events (swing started, hit confirmed, swing completed/missed) are replicated as authoritative action resolutions containing attacker peer ID, sequence, outcome (`ACCEPTED`/`REJECTED`), and hit target references.
