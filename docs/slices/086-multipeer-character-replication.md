# Slice 086 — Multi-peer Character replication

Status: **delivered**

Phase: 11 (Multi-peer Player replication), advancing
[F-004](../FEATURE-LIST.md#f-004-multi-peer-player-replication) and closing the
Phase 14 "multi-peer Character replication" queued follow-up. Extends the
existing per-peer position replication with the peer's bound Character identity,
so other players see who they are sharing the world with after the split
login/assertion architecture (slices 058–085) landed.

## User outcome

When two players are in the world, each sees the other's remote Player labeled
with its selected Character's display name, floating above the capsule — instead
of an anonymous representation. A player who joins later sees the names of
players already in the world; a player who enters the world after others sees
its name propagate to them.

## Scope and non-goals

In scope:
- `server/server_player_state.gd`: a `character_bound(peer_id, display_name,
  cosmetic)` signal emitted when `bind_character` runs at world entry.
- `server/server_main.gd`: on that signal, broadcast
  `receive_remote_player_identity` to every other connected peer; seed a
  newly-connected peer with the identities of peers already bound.
- `client/network_client.gd`: `receive_remote_player_identity` RPC target +
  `remote_player_identity_received` signal; caches the latest identity per peer
  so a RemotePlayer spawned around the same time is still labeled; clears the
  cache on despawn.
- `client/remote_player.gd` + `client/remote_player.tscn`: a billboarded
  `NameLabel` (Label3D) populated via `set_character_identity`, ignoring
  identities for other peer ids.

Out of scope (later work): rendering the cosmetic (accepted for contract parity
but not drawn); local player's own name HUD; more than the current
`MAX_REPLICATED_PEERS` two-peer bound; a live two-client GUI confirmation
(manual follow-up, same class as the split-flow GUI check).

## Public seam

- `server/server_player_state.gd` (`character_bound`).
- `server/server_main.gd` (`_on_player_state_character_bound`, late-joiner seed).
- `client/network_client.gd` (`receive_remote_player_identity`,
  `remote_player_identity_received`).
- `client/remote_player.gd` (`set_character_identity`).

## Safety invariant

Identity is replicated only — never a trusted position, outcome, or account
reference. The server derives the display name/cosmetic from the already-bound
authoritative `ServerPlayerState` (itself set from the session's selected
Character at world entry), so a client can never inject or spoof another peer's
identity. The label is presentation only; `NetworkClient` and `RemotePlayer`
never derive identity themselves. All existing flows are unchanged when a peer
has not entered the world (no identity is sent, the label stays empty).

## ADR rationale

No new ADR. This extends the established Slice 007 multi-peer replication seam
(per-peer `ServerPlayerState`, explicit `RemotePlayer_<peer_id>` RPCs) with one
additional reliable, ordered identity broadcast, mirroring the existing
`position_updated`/`melee_swing_started` signal-then-broadcast separation.

## BDD / TDD

`tests/unit/test_character_identity_replication.gd` (5 asserts):
- `bind_character` emits `character_bound` with the owning peer id, display
  name, and cosmetic, and sets the identity fields.
- `RemotePlayer.set_character_identity` labels the floating `NameLabel`.
- `remote_player_identity_received` labels only the node whose `peer_id`
  matches, leaving a non-matching node's label empty.

The world-entry path that fires `character_bound` is exercised end-to-end by
`scripts/test_login_handoff_e2e.gd` (bound Player "Handoff Hero"). The live
two-client visual (two labeled remotes on screen) is a manual GUI follow-up.

## Validation

- Full suite: `scripts/run_gut_validation.sh` on the Linux host — **passed,
  401/401 tests across 59 scripts, 1430 asserts, exit 0** (adds
  `tests/unit/test_character_identity_replication.gd`).
- End-to-end: `scripts/test_login_handoff_e2e.gd` on Linux — **ALL PASS**,
  including `world_entry == ok` and the bound Player named `Handoff Hero`,
  proving the `bind_character` path that now also emits `character_bound` is
  unaffected.
- `scripts/check_record_sync.sh` exit 0.

## Root-cause learning

No unexpected runtime failure, defect, or validation surprise occurred during
this slice. The multi-peer replication seam (Slice 007) and the world-entry
binding (Slice 043) composed as designed; the only gap was that identity was
bound server-side but never broadcast, which this slice closes additively.
