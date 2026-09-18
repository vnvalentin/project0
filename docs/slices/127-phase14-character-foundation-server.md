# Slice 127 - Phase 14 integration: server-owned Character foundation + presentation-snapshot replication
GitHub issue: #227

Status: **delivered**

Phase: 14 (NPC generalization and shared Character)

Feature: [F-036](../FEATURE-LIST.md#f-036-phase-14-unified-character-and-npc-generalization)

Design source: [#230](https://github.com/vnvalentin/project0/issues/230)
(vessel + presentation graph), [Slice 116 handoff](116-phase14-character-foundation-handoff.md),
[ADR 0007](../adr/0007-unified-character-and-npc-generalization.md). Consumes
[Slice 116](116-phase14-character-foundation-handoff.md)'s `CharacterFoundation`.

## User outcome

The live player now carries the unified `CharacterFoundation` on the server —
the same Character contract NPCs will use — and their client shows a vessel
readout ("Vessel: humanoid (balanced)") derived from a presentation-safe
snapshot. The raw stat numbers never leave the server; the client only ever
learns the normalized graph shape.

## Scope and non-goals

In scope: giving `ServerPlayerState` a server-owned baseline
`CharacterFoundation` at world entry; a presentation-safe `character_snapshot()`
accessor and a `character_snapshot_ready` signal; the peer-scoped RPC channel
(`receive_character_snapshot`) mirroring the HP channel; the client store +
`character_snapshot_changed` signal; and a minimal HUD `VesselLabel` consuming
it with a unit-tested static summary.

Out of scope: giving NPCs/monsters a `CharacterFoundation` (a later slice), a
full spider-graph rendering (the label is a compact textual summary), any
non-baseline development/equipment/technique state in the snapshot, and vessel-
derived health (Phase 15). The snapshot is sent once at world entry; live
re-replication on development change is a later concern.

## Public seam

- Server: `server/server_player_state.gd` — `character_snapshot() -> Dictionary`
  (presentation-safe) and `signal character_snapshot_ready(peer_id, snapshot)`,
  emitted in `start_for_peer`.
- Replication: `server/server_main.gd` —
  `_on_player_state_character_snapshot_ready` RPCs the owning client only.
- Client: `client/network_client.gd` — `receive_character_snapshot` stores
  `latest_character_snapshot` and emits `character_snapshot_changed`;
  `client/character_vessel_label.gd` renders it (static `summarize`/
  `dominant_axis` helpers).

## Falsifiable hypothesis

If the live Player carries a `CharacterFoundation` and only its
`to_presentation_snapshot()` crosses to the client, then the same seam serves
NPCs later, and a test can prove the client never receives raw stat numbers —
the presentation-safe boundary the Slice 116 handoff requires.

## SDD

`ServerPlayerState.start_for_peer` creates
`CharacterFoundation.create_baseline(PLAYER, humanoid)` and emits
`character_snapshot_ready` with `character_snapshot()` =
`to_presentation_snapshot()` (schema/controller/kind + normalized `graph_axes`
only). `server_main` connects the signal like the HP channel and RPCs the owning
peer. `network_client.receive_character_snapshot` stores the snapshot and emits
`character_snapshot_changed`; `VesselLabel` renders "Vessel: <kind> (<axis>)",
where `dominant_axis` returns "balanced" for the equal baseline or the peak node
key. The RPC/store legs mirror the audited `receive_health_update` channel
exactly.

## BDD

1. Given a Player enters the world, when it is set up, then a baseline humanoid
   `CharacterFoundation` exists and `character_snapshot_ready` fires with the
   snapshot.
2. Given the snapshot, when inspected, then it carries controller PLAYER, kind
   humanoid, and six normalized graph axes summing to 1.0 (balanced baseline).
3. Given the snapshot, when inspected, then it contains NO raw base/development/
   effective numbers (presentation-safe).
4. Given a snapshot, when the HUD summarizes it, then it renders the kind and a
   balanced/dominant axis; an empty snapshot renders a placeholder.

## TDD / validation

```bash
bash scripts/run_gut_validation.sh
bash scripts/check_record_sync.sh
```

**Delivered evidence (2026-09-17, Linux host `okami`):** full GUT suite green
with the new script and scene changes — **74 scripts / 502 tests / 502 passing,
exit 0**. New coverage: `test_character_foundation_replication.gd` **4/4** (real
`ServerPlayerState` node: world-entry signal emission, the baseline
humanoid/PLAYER snapshot, normalized+balanced graph axes, and the presentation-
safe invariant that no raw numbers leak — runtime evidence) and
`test_character_vessel_label.gd` **5/5** (the static summary helpers). The two
existing tests that instantiate the real `gameplay.tscn` passed unchanged —
`test_identity_gate_and_movement.gd` **4/4** and
`test_melee_strike_visual_indicator.gd` **9/9** — confirming the new `VesselLabel`
node and the `NetworkClient.character_snapshot_changed` signal load and run in
the real scene. `check_record_sync.sh` exit 0.

Validation notes: GUT cannot run on Windows, so validation was on the Linux host
per repo convention; the merged-but-undeployed `combat_health.gd` and
`character_foundation.gd` were staged alongside the modified files and then
removed, and the four modified tracked files were restored from backup. A
standalone `godot --check-only -s server/server_main.gd` reports
`Identifier not found: CharacterFoundation` at `character_foundation.gd:79` — the
known GDScript quirk where a `class_name X.new()` self-reference fails a
STANDALONE parse but resolves in a full-project load; the 502/502 suite (which
loads `server_player_state` and instantiates the scene) is the authoritative
evidence that the chain compiles and runs. The `server_main.gd` changes are three
lines of signal glue identical in shape to the existing HP channel. The
"Parameter m is null" lines are pre-existing headless dummy-renderer noise, not
failures (both scenes reported all tests passed).

## Safety invariants

- The server owns the Character; only the presentation-safe snapshot (graph
  proportions, never raw base/development/effective numbers) crosses to the
  client.
- The snapshot is replicated to the owning peer only (peer-scoped like HP).
- The client never derives Character state; it stores and renders what the
  server sends.
- No existing replication shape changed; the HP and identity channels are
  untouched.

## ADR and debt

Architecture: [ADR 0007](../adr/0007-unified-character-and-npc-generalization.md).
No new technical-debt entry. Follow-on integration remains on the Phase 14 map:
giving NPCs/monsters a `CharacterFoundation`, live re-replication on development
change, and a richer graph rendering — none are liabilities.
