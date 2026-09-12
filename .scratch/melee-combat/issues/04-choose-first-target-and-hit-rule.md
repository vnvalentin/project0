Type: grilling
Status: closed (assigned: Copilot)
Blocked by: None

## Question

What server-owned target selection and hit-resolution rule makes the first
melee outcome deterministic, testable, and honest about its temporary
collision/geometry limits?

Decide what a client may identify, what server state validates, how a target is
selected or rejected, and the form of the replicated result. Keep health,
defeat, physics knockback, and production collision out of this decision unless
they are essential to proving the first exchange.

## Resolution

The target selection and hit-resolution rule is defined as follows:

1. **Deterministic Geometric Hit Resolution**:
   - During the attack's active ticks, the server evaluates candidate target colliders against the attacker's authoritative position and forward facing vector using pure vector geometry:
     - Distance check: `attacker_pos.distance_to(target_pos) <= reach_meters` (2.0m for Generic Sword).
     - Arc angle check: `attacker_forward.dot((target_pos - attacker_pos).normalized()) >= cos(deg_to_rad(arc_degrees / 2.0))` (within ±30°).
   - This vector check is 100% deterministic, instant, requires no physics engine frame-delay workarounds, and is testable in pure GUT tests.

2. **Target Representation & Feedback**:
   - A stationary server-owned `TargetDummy` actor placed in the test scene.
   - When a hit is confirmed, the server broadcasts an authoritative `CombatEvent.HIT` containing `attacker_peer_id`, `target_id`, and `impact_pos`.
   - On the client, the target dummy provides immediate visual feedback (e.g. flash white/wobble) upon receiving the confirmed hit event. No health or defeat persistence is mutated.
