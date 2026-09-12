# Domain Context

## Product

`Project0` helps `a single developer and their playtesters` accomplish `entering
a shared 3D isometric world under one player identity and moving a character
through it, as the foundation for a server-authoritative multiplayer
action-adventure with JIT-generated, canon-persisted world content`.

## Domain terms

- **Identity gate**: The local, pre-gameplay step where a player supplies a
  display name (or other minimal credential) before a Player is created.
  Authoritative for the current slice; provisional — it is a stand-in for a
  real authentication/session design, not a security boundary.
  _Avoid_: login (implies networked auth that does not exist yet), account.
- **Player**: The in-scene actor a person controls after passing the identity
  gate. Authoritative in the current slice as a client-visible node; once
  networking exists, position/state authority moves to the server.
  _Avoid_: character, avatar, user (User is a person; Player is their in-world
  actor).
- **Flat plane**: The minimal placeholder ground scene used to prove movement
  without committing to any generated or hand-built map. Authoritative as the
  current slice's only world geometry.
  _Avoid_: level, map, world (those terms are reserved for the future
  generated/canon world).
- **Sector**: A unit of JIT-generated world content produced by the local LLM
  and, once validated, written to the SQLite canon store. Provisional — no
  generation or persistence exists yet; defined here only so the term is
  reserved and not reused for the flat plane.
  _Avoid_: chunk, tile map, level.
- **Canon**: World state that has been validated and persisted to SQLite,
  making it authoritative and durable across sessions. Provisional — canon
  persistence is not implemented in this slice; nothing produced today is
  canon.
  _Avoid_: save data, world save.

## External contexts

- **Ollama API** (`http://127.0.0.1:11434`, local Llama-3-8B on a Tesla P100):
  Supplemental, server-side-only inference source for future sector
  generation. Not authoritative for any game state by itself — the server
  must validate its output before anything becomes canon. Not exercised by
  the current identity-gate/movement slice.
- **SQLite canon database** (future, server-owned): Will be authoritative for
  persisted world state (canon) once introduced. Does not exist yet.

## Invariants

- The identity gate never blocks on, and has no dependency on, Ollama or
  SQLite.
- Nothing in the current slice is persisted to disk; closing the client
  discards all state.
- A Sector is never treated as Canon until the server has validated and
  written it to the SQLite store (future work; stated here so the boundary is
  not blurred when that system is built).

## Ambiguity policy

When evidence conflicts or is incomplete, preserve the source evidence, surface
the ambiguity, and define whether the affected action is blocked, retried, or
sent for review. Never silently guess.

## Ambiguity policy

When evidence conflicts or is incomplete, preserve the source evidence, surface
the ambiguity, and define whether the affected action is blocked, retried, or
sent for review. Never silently guess.