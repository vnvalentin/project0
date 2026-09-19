# Slice 096 — Canon mutation intent DTO + server-authoritative resolution service
GitHub issue: #95

Status: **in-progress**

Phase: 9 (Canon persistence and world mutation), advancing
[P-013](../FEATURE-LIST.md#p-013-dynamic-world-mutation-tracking). Third P-013
slice, building on the Slice 050 mutation log and the Slice 095 entity-GUID
target check. It is the authority-critical half of the "mutation over the wire"
path; the `@rpc` transport and a headless round-trip e2e are the next slice.

## User outcome

When a player triggers a durable change to a canonical sector, the **server**
decides the outcome: the client only expresses *intent* (which sector, which
entity, which kind of change, which revision it believes is current), and the
server stamps the authoritative actor, event id, and tick before it touches
Canon. A client can neither forge who did it, nor forge the event identity, nor
replay the same action into two separate mutations.

## Scope and non-goals

In scope:

- `shared/canon_mutation_intent.gd` (`CanonMutationIntent`) — the pure,
  versioned, bounded **client→server intent** contract: a builder for the wire
  dictionary and a fail-closed `parse` that rejects malformed intents **and any
  intent that carries a server-owned field** (`event_id`, `actor_player_id`,
  `server_tick`, `applied_revision`). This is the `ActionIntent` half of the
  `CLAUDE.md` intent/resolution split for world mutation.
- `server/canon_mutation_service.gd` (`CanonMutationService`) — the server-only
  resolver that turns an authenticated caller's intent into a **server-owned**
  `CanonMutationEvent`: it stamps `actor_player_id` from the authenticated
  Player (never the client), derives a deterministic server-owned `event_id`
  from `(actor, client_seq)` for idempotency, reads `server_tick` from an
  injected clock, and applies it through `CanonMutationRepository`. It maps the
  repository outcome to a bounded `accepted`/`rejected` resolution.

Out of scope (Slice 097 and later): the `@rpc` transport in
`client/network_client.gd` and `server/server_main.gd`, wiring a live
`CanonMutationRepository`/service into `server_main`, the headless two-peer
round-trip e2e, mutation replay into live scene state, gameplay authorization of
the actor beyond identity ownership, physical-event verification, and telemetry.

## Public seam

- `CanonMutationIntent.build(sector_id, target_guid, mutation_kind, expected_revision, client_seq, payload) -> Dictionary`
  and `CanonMutationIntent.parse(value) -> {outcome, intent|detail}`.
- `CanonMutationService.new(mutation_repository, clock: Callable)` and
  `resolve_intent(actor_player_id: String, raw_intent: Variant) -> Dictionary`
  returning `{status: "accepted"|"rejected", reason, applied_revision, client_seq, event_id}`.

## Safety invariants

- **Server owns outcomes:** `actor_player_id`, `event_id`, and `server_tick` are
  set by the server; a client-supplied value for any of them is rejected as a
  forged intent before any write.
- **Idempotent:** the server-owned `event_id` is a pure function of
  `(actor_player_id, client_seq)`, so a retransmitted intent resolves to the
  same mutation (repository `idempotent`) and never double-applies; a different
  payload under the same `(actor, seq)` is the repository's `conflict`.
- **Fail-closed:** an invalid actor, malformed intent, non-canon sector,
  unknown target, or stale revision is a `rejected` resolution with a bounded
  reason and no write.
- **Shared contract, server authority:** the intent shape is shared (both
  processes must agree), but resolution, identity, the clock, and the store stay
  server-only; `shared/canon_mutation_intent.gd` references no store/server type.

## ADR rationale

No new ADR. The intent/resolution split, server-owned outcome fields, and
idempotent revision-checked mutation are already normative in `CLAUDE.md`
(`ActionIntent`/`ActionResolution`, `CanonMutationEvent`).

## BDD / TDD

- `tests/unit/test_canon_mutation_intent.gd` (written first): build/parse round
  trip, bounds, unsupported kind, negative sequence/revision, oversized payload,
  and rejection of server-owned fields.
- `tests/integration/test_canon_mutation_service.gd` (written first): accepted
  first mutation, sequential accepted mutation, idempotent replay, target-not-
  found, sector-not-canon, stale-revision rejection, forged-field rejection, and
  invalid-actor rejection, over a real SQLite-backed canonical sector.

## Validation

Linux host: `scripts/run_gut_validation.sh` full suite exit 0 (script/test
counts must rise for the two new files) + `scripts/check_record_sync.sh` exit 0.

## Root-cause learning

None yet.
