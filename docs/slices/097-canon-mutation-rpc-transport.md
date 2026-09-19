# Slice 097 — Canon mutation intent RPC transport + headless round-trip e2e
GitHub issue: #95

Status: **in-progress**

Phase: 9 (Canon persistence and world mutation), advancing
[P-013](../FEATURE-LIST.md#p-013-dynamic-world-mutation-tracking). Fourth P-013
slice: it puts the Slice 096 intent contract and resolution service **on the
wire** and wires a live `CanonMutationRepository`/`CanonMutationService` into the
running server.

## User outcome

A connected client can send a Canon mutation intent to the authoritative server
over the real network and receive back the server's accepted/rejected
resolution — the first working over-the-wire path for durable world mutation.

## Scope and non-goals

In scope:

- `client/network_client.gd`: a client `submit_canon_mutation_intent(intent)`
  (C→S, reliable), the server-side `@rpc("any_peer")`
  `receive_canon_mutation_intent_on_server(intent)` that emits the sender peer id
  for the server to resolve, and the owning-client `@rpc("authority")`
  `receive_canon_mutation_resolution(resolution)` relay, plus the two signals.
- `server/server_main.gd`: instantiate a live `CanonMutationRepository`
  (`ensure_schema`) and `CanonMutationService` (clocked from the server's own
  `_monster_tick`), connect the intent signal, map the sender peer to its bound
  Character id as the authoritative actor, resolve, and return the resolution to
  that peer only.
- `scripts/test_canon_mutation_rpc_e2e.gd`: a two-process headless harness (the
  established pattern from the melee/prediction/multi-peer e2e scripts) proving a
  real client submits an intent over ENet and receives a real resolution back.

Out of scope (Slice 098+): mutation replay into live scene state on sector load,
gameplay authorization beyond Character identity, physical-event verification,
telemetry, and an accepted-over-the-wire proof that would require driving the
full login/assertion flow inside the harness (the accepted/target/idempotent
outcome mapping is already proven at the service seam in Slice 096).

## Public seam

- `NetworkClient.submit_canon_mutation_intent(intent: Dictionary)` and the signal
  `canon_mutation_resolution_received(resolution: Dictionary)`.
- Server-side: `NetworkClient.canon_mutation_intent_received(sender_peer_id, intent)`
  consumed by `server_main._on_canon_mutation_intent`.

## Safety invariants

- **Server owns the actor:** the actor is the sender peer's server-bound
  `character_id`; the client's intent may not carry one (enforced by
  `CanonMutationIntent`). A peer with no bound Character is rejected
  (`invalid_actor`) — an unauthenticated peer cannot mutate Canon.
- **Owning-client resolution:** the resolution is RPC'd back only to the peer
  that submitted the intent (`rpc_id(sender_peer_id, ...)`), never broadcast.
- **Fail-closed wiring:** a mutation-schema failure refuses server start, matching
  the existing Canon fail-closed boot checks; the handler no-ops if the service
  or the peer's Player state is absent.
- **Relay-only client:** `network_client.gd` ferries the intent and relays the
  resolution; it never derives an outcome. The repository/service stay server-only.

## ADR rationale

No new ADR. Reuses the established `@rpc` intent/resolution transport pattern and
the CLAUDE.md server-authoritative outcome model.

## BDD / TDD

Runtime evidence (RPC cannot be exercised by single-process GUT — one
MultiplayerAPI peer per SceneTree): `scripts/test_canon_mutation_rpc_e2e.gd`
boots the real server, connects a real client, submits an intent, and asserts a
resolution round-trips (reason `invalid_actor` for the unauthenticated harness
peer), proving both RPC directions and the server wiring. The service outcome
mapping (accepted/idempotent/target-not-found/stale) is covered by Slice 096's
`test_canon_mutation_service` integration suite.

## Validation

Linux host: full `scripts/run_gut_validation.sh` exit 0 (unchanged 482/70 — no
new GUT tests; the transport is proven by the e2e), the e2e harness prints
`ALL PASS` (exit 0), and `scripts/check_record_sync.sh` exit 0.

## Root-cause learning

- Symptom: the e2e round-trip passed both RPC directions but failed "the
  resolution echoes the client's sequence" — the `invalid_actor` resolution
  returned `client_seq = -1`.
- Public seam: `CanonMutationService.resolve_intent`.
- Hypothesis (confirmed): the actor check ran before the intent was read, so the
  early rejection had no `client_seq` to echo and hard-coded `-1`; a client could
  not correlate that rejection to its request.
- Why existing tests missed it: Slice 096's `test_empty_actor_is_rejected`
  asserted only status/reason, not the echoed `client_seq`; the gap surfaced only
  once a real client needed to match the response to its submission.
- Countermeasure: extract `client_seq` up front and echo it on every resolution,
  including early rejections; added a regression assertion to
  `test_canon_mutation_service` and the e2e now checks the echo.
- Regression evidence: full host GUT green + `scripts/test_canon_mutation_rpc_e2e.gd`
  prints ALL PASS (see P-013 change history for counts).
