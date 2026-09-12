Type: grilling
Status: closed (assigned: Copilot)
Blocked by: None

## Question

What compact, extensible melee weapon-archetype model distinguishes unarmed
strikes from a massive heavy weapon while allowing future melee weapons without
subclass sprawl?

Decide the data and behavioral dimensions the first model owns, such as windup,
active reach, recovery, mobility constraint, hit capacity, and impact class.
Do not decide equipment persistence, inventory UI, balance values, or final
content lists.

## Resolution

To keep the initial slice as simple as possible, we adopt a single middle-of-the-road **Generic Sword** archetype as the default baseline weapon:

1. **Data Model**:
   - A compact, typed `MeleeWeaponArchetype` class in `shared/` with immutable properties:
     - `archetype_id: String` (`"BASIC_SWORD"`)
     - `windup_ticks: int = 6` (~100ms at 60Hz)
     - `active_ticks: int = 4` (~66ms)
     - `recovery_ticks: int = 10` (~166ms)
     - `reach_meters: float = 2.0`
     - `arc_degrees: float = 60.0`
     - `windup_speed_factor: float = 0.5`
     - `recovery_speed_factor: float = 0.8`
     - `max_targets: int = 1`

2. **Equipping / Switching**:
   - No inventory UI or weapon switching in the first slice; all players spawn with this default generic sword. Extensibility to other archetypes is preserved through the data schema without extra runtime complexity.
