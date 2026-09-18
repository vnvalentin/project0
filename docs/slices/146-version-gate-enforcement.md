# Slice 146 - Phase 16 (F-037): live version-gate enforcement

GitHub issue: #100 (Goal: client-auto-update)

Status: **delivered**

Phase: 16 (Client delivery experience)

Feature: [F-037](../FEATURE-LIST.md#f-037-windows-client-delivery--version-identity-mandatory-gate-and-signed-patching)

Design source: [Windows client delivery contract](../../.scratch/client-auto-update/spec.md)
("Version handshake"), [ADR 0008](../adr/0008-windows-client-delivery-trust-and-rollback.md)
decision 2. Enforces the contract proven in
[Slice 145](145-version-handshake-contract.md), using the identity from
[Slice 144](144-client-build-version-stamp.md).

## Ownership deviation (auditable)

Implemented directly by Copilot under the **standing authorization** in
[AGENTS.md](../../AGENTS.md) (user, 2026-09-18). **Fallback trigger:** Claude CLI
is interactive-only on this machine. The full delivery gate was applied.

## User outcome

The mandatory version gate is now real. A client whose build does not match what
the server serves is refused before it gets a world, a Player, or any other RPC —
and is told which version it needs and where to get it. A server that cannot say
what it serves refuses to start rather than turning every tester away.

## Scope and non-goals

In scope: the live wiring. The client sends the handshake as its first
post-connect message; the server defers all peer admission until it accepts one;
a refused peer is told why and disconnected; a misconfigured server refuses to
boot.

Out of scope: fetching or verifying the signed manifest, patch staging, the
updater, rollback, the launcher, onboarding, and the controller placeholder. The
rejection carries *where* to patch; acting on it is a later slice.

## Public seam

- `client/network_client.gd`:
  - sends `VersionHandshake.request()` from `_on_connected_to_server()`;
  - `receive_version_handshake_on_server` (`any_peer`) → emits
    `version_handshake_received(peer_id, handshake)` on the server;
  - `receive_version_handshake_rejected` (`authority`) → retains
    `latest_version_rejection`, sets a bounded status, emits
    `version_handshake_rejected`.
- `server/server_main.gd`:
  - resolves the gate before binding and `quit(1)`s when it is unusable;
  - `_on_peer_connected` now only marks the peer pending;
  - `_on_version_handshake_received` decides, then admits or refuses;
  - `_admit_peer` holds the former admission body.

## Design notes

Admission is **deferred, not filtered after the fact**. `_on_peer_connected`
previously replicated the town, spawned a Player, allocated a house, and
cross-replicated peers immediately. All of that moved into `_admit_peer`, which
only runs after an `ACCEPTED` outcome, so a refused client never receives world
state at all. Refusing *after* handing out the world would have leaked exactly
what the gate exists to withhold.

The rejection is sent before a **graceful** `disconnect_peer`, so the reliable
packet flushes rather than being dropped with the socket.

A resent handshake is ignored once a peer leaves the pending set, so a client
cannot re-roll the gate or double-admit itself.

Refusing to boot on a malformed requirement follows the repository's existing
fail-closed precedent (the server already refuses to start on unresolved
tuning): a server that cannot state its requirement would otherwise reject every
client, which looks identical to a mass outage caused by the players.

## BDD

1. Given a connecting peer, then it is admitted nothing until it handshakes.
2. Given a matching client, then it passes the gate and enters the world normally.
3. Given a mismatched client, then it is refused with `CLIENT_OUTDATED` and
   disconnected, and never receives world state or a Player.
4. Given a malformed `PROJECT0_REQUIRED_CLIENT_VERSION`, then the server refuses
   to start and never binds.
5. Given a refused client, then it retains the reason and surfaces a bounded
   status for the UI.

## Validation

Full GUT suite on the Linux host (working-tree overlay): **751/751 tests passing
across 103/103 scripts, 2393 asserts, exit 0** (from 747/102: +1 script,
+4 tests). The socket E2E harnesses
(`test_multi_peer_replication_e2e`, `test_prediction_reconciliation_e2e`) pass
unchanged, which is the regression proof that deferring admission did not break
normal connection.

**Runtime evidence** (real processes, not unit doubles):

- *Matching server (default):* the real multi-peer E2E orchestrator
  (`scripts/test_multi_peer_replication.gd`) exited **0** with
  `Peer … passed the version gate.` for both peers and `ALL PASS`.
- *Mismatched server (`PROJECT0_REQUIRED_CLIENT_VERSION=9.9.9`):* the same
  orchestrator exited **1**; the server logged
  `Peer … (awaiting version handshake)` then
  `Refusing peer …: CLIENT_OUTDATED (client build version does not match the
  required version)` for both peers, and every "client spawns its own Player"
  assertion **failed** — proving a refused client receives no world and no Player.
- *Misconfigured server (`PROJECT0_REQUIRED_CLIENT_VERSION=1.2`):* exited **1**
  with `Refusing to start: PROJECT0_REQUIRED_CLIENT_VERSION is set to a malformed
  client build version.` and no `Server listening` line — it never bound.

`bash scripts/check_record_sync.sh` → 0 errors, exit 0.

New test: `tests/unit/test_version_gate_client_seam.gd` (4 tests) covering the
refused client's retained reason, bounded status, relayed signal, and that a
server misconfiguration is not reported as the player's client being outdated.

## Root-cause learning

No product defect. Two harness-invocation mistakes were caught while gathering
runtime evidence and are worth recording: `scripts/multi_peer_client_harness.gd`
requires `--state-file=`, and it reads `OS.get_cmdline_user_args()`, so custom
arguments must follow a bare `--`. Both produced a client that exited before
connecting, which initially *looked* like the gate silently dropping peers. The
discriminating check was reading the client log rather than the server log — it
showed the harness erroring on its own arguments before any socket work.
Countermeasure: drive this kind of evidence through the existing E2E orchestrator
(`scripts/test_multi_peer_replication.gd`), which already wires its own processes
correctly, instead of hand-invoking the inner harness.

## Follow-on / known limitation

A peer that connects and never sends a handshake stays in the pending set
holding an ENet slot until it disconnects. It receives nothing, and
`MAX_CLIENTS` bounds the exposure, but a pending-handshake timeout would close
that idle-slot vector and is worth a later slice.
