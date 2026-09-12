Type: grilling
Status: resolved

## Question

What is the minimal flat HP/damage/death data shape to add — a new class in
`shared/combat_contracts.gd` or a sibling shared contract file — for a
monster target, replacing `client/target_dummy.gd`'s flash-only reaction to
`CombatEvent.HIT`? Must explicitly mark the model provisional (a flat
`current_hp`/`max_hp` pool with a fixed damage-per-hit value from the
existing `MeleeWeaponArchetype`) pending the future six-node vessel-derived
health formula (Phase 12, 0% built). Needs a new or extended `CombatEvent`
kind for death (today only `COMBAT_EVENT_HIT` exists, with no damage field at
all).

## Answer

- **File placement**: a new sibling file, `shared/monster_contracts.gd`, not
  an addition to `shared/combat_contracts.gd`. That file's own doc comment
  scopes it tightly to Slice 012's melee-strike contracts with explicit
  non-goal boundaries (no damage/HP fields) — growing it would blur that
  boundary. `monster_contracts.gd` references
  `CombatContracts.MeleeWeaponArchetype` rather than duplicating it.
- **HP shape**: `MonsterCombatState` with `current_hp: int`, `max_hp: int`,
  `target_id: String` (mirrors `TargetDummy`'s existing `target_id` so
  `CombatEvent.target_id` resolution is unchanged). A single fixed
  provisional constant (e.g. `MAX_HP = 30`), no per-archetype table — only
  one monster archetype exists in this map's scope.
- **Damage per hit**: a new fixed `DAMAGE_PER_HIT` constant (e.g. `10`) in
  `monster_contracts.gd`, not added to `MeleeWeaponArchetype` (which has no
  damage field today by Slice 012's explicit non-goal — adding one there
  would silently expand that slice's closed scope).
- **Death event**: reuse `CombatEvent`'s existing shape (attacker, target,
  position, tick already fit "who/where/when" for a death) with a new kind
  constant `COMBAT_EVENT_DEATH` added to `combat_contracts.gd`'s kind
  constants, rather than a new event class.
- All of the above explicitly provisional pending the future six-node
  vessel-derived health formula (Phase 12, 0% built).
