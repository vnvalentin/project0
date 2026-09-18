extends RefCounted
class_name PlayerCombatContracts
## Slice 094 / 125: the shared HP seed a Player and the baseline monster both
## spawn with. The Player's live HP pool is now the shared CombatHealth contract
## (see shared/combat_health.gd and server/server_player_state.gd), which retired
## this module's original provisional PlayerVitals class in Slice 125. This
## module now only owns the shared default seed. See
## docs/slices/094-player-hp-monster-damage.md,
## docs/slices/125-phase14-player-health-integration.md, and
## .scratch/npcs/issues/04-provisional-shared-stat-block.md.
##
## PROVISIONAL: this flat seed is a placeholder for the future six-node
## vessel-derived health formula (Phase 12/15, 0% built). PLAYER_MAX_HP
## deliberately equals MonsterContracts.MAX_HP so a Player and the baseline
## monster start with the same durability until the vessel derives it from CON.

const SCHEMA_VERSION: int = 1

## Fixed full health a Player spawns with. A single constant, not a per-build
## table, since no vessel/derivation exists yet (Phase 12). Mirrors
## MonsterContracts.MAX_HP as the one shared default seed (ticket 04). Seeds the
## Player's CombatHealth pool in server/server_player_state.gd.
const PLAYER_MAX_HP: int = 30
