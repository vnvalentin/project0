# Slice 128 - Phase 14 integration: NPC/monster carries the shared CharacterFoundation
GitHub issue: #227

Status: **delivered**

Phase: 14 (NPC generalization and shared Character)

Feature: [F-036](../FEATURE-LIST.md#f-036-phase-14-unified-character-and-npc-generalization)

Design source: [Slice 116 handoff](116-phase14-character-foundation-handoff.md)
(the falsifiable hypothesis: Player and NPC consume one Character foundation,
differing only in controller type), [ADR 0007](../adr/0007-unified-character-and-npc-generalization.md).

## User outcome

The monster is now literally a Character — the same unified `CharacterFoundation`
the player carries — just AI-controlled instead of player-controlled. "NPC ==
Player Character" is no longer a design aspiration; it is enforced by shared
code, with no duplicated monster stat model.

## Scope and non-goals

In scope: giving `ServerMonsterState` a server-owned baseline
`CharacterFoundation` (controller AI, kind "monster") and a presentation-safe
`character_snapshot()`, plus the cross-cutting parity test proving Player and NPC
satisfy the same contract and differ only in controller type.

Out of scope: replicating the monster's Character snapshot to clients (no monster
vessel HUD yet), driving the monster's AI/movement/spawning from the Character
contracts (its detect/chase/attack FSM is unchanged), and any non-baseline
development/equipment/technique state. This slice establishes NPC parity of the
Character foundation, not a behavioural rewrite.

## Public seam

`server/server_monster_state.gd`: a server-owned `CharacterFoundation` created in
`_init` (AI / "monster" baseline) and `character_snapshot() -> Dictionary` — the
same presentation-safe shape `ServerPlayerState` exposes.

## Falsifiable hypothesis

If the monster carries the same `CharacterFoundation` as the Player, then a test
can show both satisfy one contract with an identical baseline vessel structure,
differing only in `controller_type` — proving the Phase 14 seam serves Player and
NPC state without duplicating monster logic.

## SDD

`ServerMonsterState._init` calls
`CharacterFoundation.create_baseline(CONTROLLER_AI, "monster")`, mirroring
`ServerPlayerState`'s `CONTROLLER_PLAYER` baseline. `character_snapshot()` returns
`to_presentation_snapshot()` (normalized graph axes + controller/kind, no raw
numbers). No change to the monster's HP pool (already the shared `CombatHealth`
from Slice 126), phase machine, or telemetry.

## BDD

1. Given a monster, when created, then it carries an AI-controlled
   `CharacterFoundation` of kind "monster".
2. Given a Player and a monster, when both snapshots are compared, then they
   expose the same six balanced vessel axes and differ only in controller type.
3. Given the monster snapshot, when inspected, then it is presentation-safe (no
   raw base/development/effective numbers).

## TDD / validation

```bash
bash scripts/run_gut_validation.sh
bash scripts/check_record_sync.sh
```

**Delivered evidence (2026-09-17, Linux host `okami`):** full GUT suite green —
**73 scripts / 493 tests / 493 passing, exit 0**. The new
`test_shared_character_player_npc_parity.gd` ran **4/4** (real `ServerPlayerState`
node + real `ServerMonsterState`: Player is PLAYER-controlled, monster is
AI-controlled/kind "monster", both share the same six balanced vessel axes and
differ only in controller type, and the NPC snapshot is presentation-safe) — the
F-036 exit-gate parity evidence. The monster combat regression net passed
unchanged: `test_server_monster_state.gd` **10/10** and
`test_server_monster_manager.gd` **19/19**. `check_record_sync.sh` exit 0. GUT
cannot run on Windows, so validation was on the Linux host per repo convention;
the drifted contract chain (`monster_contracts`, `server_player_state`,
`combat_health`, `character_foundation`) and the post-126 `test_monster_contracts`
were staged for the run and then restored/removed.

## Safety invariants

- The server owns the monster's Character; only presentation-safe state would
  ever cross to a client.
- The monster's Character uses the shared `CharacterFoundation` — no parallel
  monster stat model.
- The monster's existing combat behaviour (HP, phase machine, death, respawn) is
  unchanged.

## ADR and debt

Architecture: [ADR 0007](../adr/0007-unified-character-and-npc-generalization.md).
No new technical-debt entry. Remaining Phase 14 follow-ons (replicating the
monster vessel to clients, driving NPC movement/spawning from the Activity/Spawn
contracts, richer graph rendering) are future feature work on the Phase 14 map,
not liabilities.
