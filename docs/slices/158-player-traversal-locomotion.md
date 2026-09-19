# Slice 158 - Player traversal locomotion baseline

GitHub issue: #229

Status: **delivered**

Phase: 14 follow-on (unified Character movement)

Feature: [F-036](../FEATURE-LIST.md#f-036-phase-14-unified-character-and-npc-generalization)

## User outcome

The Player can jump over a gap or onto a higher landing, dodge through a
telegraphed hazard, duck under a low obstruction, and slide while moving.
Movement outcomes remain server-authoritative and local input remains responsive
through prediction and reconciliation.

## Scope and non-goals

In scope: a shared bounded locomotion intent, server-owned jump/dodge/posture
state, deterministic jump and dodge motion, client prediction, and public-seam
tests for the Player and ServerPlayerState.

Out of scope: authored platform/height-map collision, damage or hit-resolution
changes, stamina/stat-scaled tuning, animation assets, and NPC locomotion.

## Public seam

`NetworkClient.submit_locomotion_intent(intent, sequence)` carries planar input
and one locomotion mode. `ServerPlayerState.apply_locomotion_intent(...)` owns
mode validation and state transitions. `Player` predicts the same fixed-tick
motion and reconciles from the existing authoritative position channel.

## Falsifiable hypothesis

If locomotion mode is part of the ordered intent and both client and server use
the same fixed-tick jump/dodge constants, then a jump or dodge can cross a
vertical/traversal interval without the client claiming an outcome, while duck
and slide remain reversible posture states.

## BDD

1. A grounded Player pressing jump enters a bounded upward arc and lands at the
   floor height; a jump while airborne is ignored.
2. A Player pressing dodge enters a bounded burst and exits after its recovery
   ticks; repeated dodge input cannot restart it.
3. Holding duck enters the duck posture and releasing it restores standing.
4. Sliding requires movement input, enters the slide posture, and ends after
   its bounded duration or when movement stops.
5. A stale or wrong-owner locomotion intent has no server-side effect.
6. Reconciliation starts from the server position and replays pending intents,
   including locomotion mode, without accepting a client position.

## TDD / validation

Focused public-seam tests cover the server transition and fixed-tick motion,
then the full GUT suite and record-sync check provide delivery evidence.

## Safety invariants

- The server owns position, floor state, mode transitions, and landing.
- Client predictions are disposable and never resolve damage, invulnerability,
  or terrain outcomes.
- Modes and numeric state are bounded; stale and wrong-owner inputs are refused.

## Ownership note

Copilot is implementing this slice under the standing authorization because the
local Claude CLI is unavailable/non-interactive on Windows (see repository
memory `implementation-ownership.md`).

## Validation evidence

Focused validation on Windows: `godot --headless -s addons/gut/gut_cmdln.gd
-gselect=test_server_player_locomotion -gdisable_colors -gexit` — **8/8 tests,
14/14 assertions passed**, including jumping across and landing on the authored
raised platform at height `2.2`.

Full validation passed on the Linux host `okami` using the repository's
throwaway temp-tree overlay workflow. `bash scripts/run_gut_validation.sh`
passed, and `bash scripts/check_record_sync.sh` exited 0. The Windows-native
extension limitation is therefore only a local validation constraint, not a
failure of the delivered tree.

`bash scripts/check_record_sync.sh` reports only pre-existing historical
feature-reference warnings for Slices 002, 003, 009, 010, 038, and 041; it
reports no Slice 158 error.