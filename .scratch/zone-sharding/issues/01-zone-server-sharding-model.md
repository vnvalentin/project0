# Zone-server sharding for horizontal world scale

Status: open
Assignee: unassigned
Type: grilling
Blocked by: none (deliberately deferred; no current slice depends on it)

## Question

The authoritative game server is a single fixed-tick process that owns all
players, all simulation, and all Canon writes. That is a hard ceiling on
concurrent players and world size: adding replicas of the same world would
corrupt Canon, because Canon is server-owned SQLite with a single writer.

EQEmu splits this into a **world server** (login handoff, character select,
zone routing, global chat) and **zone servers** (each authoritative for a set
of zones, simulating only the players currently inside them). Should Project0
adopt an equivalent split — keeping the current "game server" as the world/
routing authority and introducing a "zone server" process that owns a bounded
set of sectors?

## Why this is not trivially the same as EQEmu

EQEmu zones are authored, static, and known at boot. Project0 sectors are
generated just-in-time by a local LLM and then frozen as permanent Canon
(`CLAUDE.md`, "JIT Generation And Permanent Canon"). That difference creates
tensions a naive zone split would hit immediately:

1. **Who requests generation.** Sector generation is triggered by authoritative
   player proximity to an unexplored boundary. If sectors are owned per zone
   server, two zone servers can approach the same unexplored coordinate at
   once. Coordinate uniqueness and first-write-wins already exist as rules, but
   the requesting/queueing authority is currently implicit in "the one server".
2. **Ollama is a single scarce resource.** One local model on one GPU
   serializes across every zone server. Queue ownership, fairness, backpressure,
   and timeout behavior become cross-process concerns rather than in-process
   ones.
3. **Canon writes are single-writer.** Either a central Canon service stays the
   sole writer and zone servers become clients of it, or Canon is sharded by
   sector coordinate with strict ownership. The first keeps the existing
   invariant but adds a hop on every mutation; the second multiplies the
   invariant across processes.
4. **Player handoff must be atomic and idempotent.** Crossing a zone boundary
   has to transfer authoritative vessel revision, Kinetic energy, active
   Burnout, cooldowns, and in-flight action sequence without duplicating or
   dropping effects. This is the same idempotency problem as `ActionIntent`
   replay, but now spanning two processes.
5. **Tick clocks are per-process.** `BurnoutInstance`, `ExecutionProfile`, and
   cooldowns are all expressed in authoritative server ticks. Two zone servers
   have independent tick counters, so a handoff must either translate ticks or
   the system must adopt a monotonic global time source.

## Required decision output

A decision on whether to shard, and if so: the process topology, which process
owns Canon writes, how sector generation is requested and queued across shards,
the player handoff contract (fields, atomicity, idempotency key, failure and
rollback), how tick-based temporary state survives handoff, and explicit
non-goals. No implementation is implied by this ticket.

## Notes

- Containerizing the services (Slices 105/106) is a prerequisite enabler, not a
  solution: containers make it trivial to *run* N shards, but the code must
  support shard ownership first.
- Stateless HTTP services (enrollment, operator, dashboard) already scale by
  replica count and are out of scope here.
- If multi-writer persistence is ever required, SQLite is the binding
  constraint and that is its own ADR, not a detail of this ticket.
