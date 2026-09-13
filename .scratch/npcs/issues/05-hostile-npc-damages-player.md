Type: grilling
Status: unclaimed
Blocked by: 04

## Question

Now that the Player has provisional HP (ticket 04), define what a `HOSTILE`
NPC's **landed** attack does to the Player. The attack already resolves
authoritatively at the `WINDUP → ATTACK` transition in
`server/server_monster_state.gd` but currently applies **no damage** (a gap the
file documents). Resolve with `grilling`:

- **Damage amount.** A fixed provisional constant (mirroring the monster's own
  `MonsterContracts.DAMAGE_PER_HIT`), server-owned and tuning-shaped.
- **Fairness.** Only an accepted, telegraph-fair hit damages the Player — the
  human's dodge window (stepping out of reach/arc during `WINDUP`) must still
  make the attack miss (CLAUDE.md Combat Reading, non-negotiable).
- **Telemetry.** Emit bounded telemetry on player-damage and on the 0-HP
  transition.
- **At 0 HP (bounded minimum only).** A full death/respawn/penalty system is
  **out of scope** (map). Decide the minimal placeholder: e.g. clamp HP at 0 and
  emit a "player defeated" telemetry event, or a placeholder return-to-spawn with
  HP reset. Enough to be always-playable, no more.

Recommended default: a fixed `DAMAGE_TO_PLAYER` constant applied only on a
telegraph-fair landed hit; on reaching 0 HP, emit a defeated event and reset the
Player to a spawn anchor with full provisional HP (placeholder), with real
death/respawn deferred to fog.
