Type: grilling
Status: closed (assigned: Copilot)
Blocked by: None

## Question

What is the smallest player-visible melee exchange that proves combat has begun
without prematurely deciding damage systems, enemy AI, collision fidelity, or
presentation assets?

Resolve the action shape a Player requests, the minimum observable server
outcome, and the gameplay distinction that must be visible between an unarmed
strike and a massive heavy weapon. Establish the terms needed to describe that
exchange consistently.

## Resolution

The smallest player-visible melee exchange is defined as follows:

1. **Observable Server Outcome**:
   - The server validates an `ActionIntent`, transitions the player into an authoritative attack lifecycle state (windup -> active -> recovery ticks), performs a server-side geometric/reach test against stationary in-world colliders, and replicates an authoritative `ActionResolution` / `hit_confirmed` event with target ID and impact vector.
   - No persistent health pools, damage formulas, or permanent defeat states are mutated in this first exchange.

2. **Unarmed vs. Massive Heavy Weapon Contrast**:
   - *Unarmed Strike*: Short windup (e.g., 2 ticks), short reach (~1.2m), zero mobility penalty during windup/recovery, rapid action cadence.
   - *Massive Heavy Weapon*: Long committed windup (e.g., 12-15 ticks), extended reach (~3.0m), server-enforced locomotion freeze/slow during swing, longer recovery cooldown.

3. **Target Representation**:
   - A stationary server-owned `Target Dummy` with a bounded collision volume placed on the flat plane. Proves hit detection deterministically without relying on remote peer movement jitter.

4. **Client Intent & Prediction**:
   - Client performs local prediction of the windup/attack state immediately upon input, and reconciles/rolls back if the server returns `REJECTED` (e.g. cooldown or invalid state).
