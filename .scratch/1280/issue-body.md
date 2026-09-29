Parent acceptance: #1219
Related feature boundary: #754

## Goal
Deliver one bounded enemy attack sequence that is readable to a Windows player while preserving server-authoritative hit resolution.

## Scope
- Preserve the existing internal `PHASE_ATTACK` name as the approved ACTIVE phase.
- Keep the server-owned lifecycle `IDLE -> WINDUP -> PHASE_ATTACK -> RECOVERY`.
- Server determines target facing and attack timing.
- Introduce the smallest versioned replicated attack-state contract needed to expose WINDUP state, target timestamp, duration, and facing.
- Render the telegraph locally on the client; the client must not decide collision or damage.
- Instantiate and evaluate the hitbox on the server physics tick.
- Preserve the existing rewind limit of <= 200 ms, spatial overlap/raycast checks, mitigation, and atomic server health mutation.

## Exclusions
Do not implement or import #754 dynamic STR/DEX/CON body mapping, poise/stagger thresholds, hit-reaction scaling, Kinetic Control timing extensions, broad combat progression, launcher work, or client authority.

## Acceptance Evidence
- Focused public-seam tests cover state replication, telegraph timing/facing, authoritative hit/miss, and rewind bound.
- A packaged Windows run records build/server identities, setup, actions, visible telegraph, player response, authoritative result, cleanup, and correlation.
- User approves responsiveness and feel for one repeatable encounter.
- Full GUT and record-sync validation pass.

## Blockers
Any missing network snapshot or combat contract is recorded as a bounded implementation blocker before expansion. No unrelated #754 work is pulled into this slice.