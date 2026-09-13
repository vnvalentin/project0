# Map: Player Accounts and Characters

## Destination

A handoff-ready spec (SDD/BDD-shaped) describing how a person authenticates into
Project0 under a persistent **Account**, selects among their **Characters** on a
character-select screen, and creates a new Character on a character-creation
screen — with each selected Character instantiated as the existing
server-authoritative **Player**. Trust level is a home-hosted, invite-gated
server: real server-side credential verification, with no public-internet-grade
recovery, OAuth, MFA, or payment.

The map is complete when the domain model, authentication/session model, the
Account + Character data model, the persistence boundary (design decided here;
SQLite storage engine handed to a downstream slice shared with Phase 9), the
client↔server contract, the screen flow, and the Character → Player
instantiation seam are decided well enough to create implementation tickets
safely. See [Project Tracker](../../docs/PROJECT-TRACKER.md),
[CLAUDE.md](../../CLAUDE.md), and [CONTEXT.md](../../CONTEXT.md).

## Notes

- Domain: Godot 4 GDScript 2.0 strict typing, server-authoritative per
  CLAUDE.md's Runtime Ownership rules. Existing patterns to match:
  `shared/combat_contracts.gd` and `shared/sector_blueprint_schema.gd`
  (versioned, bounded, fail-closed value contracts); `client/identity_gate.gd`
  + `client/player_identity.gd` (the provisional pre-gameplay flow this effort
  replaces); `server/server_player_state.gd` (`start_for_peer` — the Player
  instantiation seam); `client/network_client.gd` / `server/server_main.gd`
  (the ENet connect lifecycle auth must slot into).
- Planning mode: this effort produces decisions and a handoff-ready spec; no
  product code while charting. Copilot owns grilling, domain decisions, scope,
  and the handoff; Claude CLI owns the subsequent code edits. **User
  authorization (2026-09-13): if Claude CLI is in a rate-limit state, Copilot
  may continue by implementing directly.**
- Skills to consult per ticket: `domain-modeling` (CONTEXT.md currently says to
  AVOID "account", "login", and "character" — this effort formally introduces
  them; keep the glossary in sync), `codebase-design` (seam placement for the
  auth/character contract), `grilling`, `prototype` (screen flow), `research`.
- Decided while charting (round 1, user-accepted):
  - **Destination artifact** = a handoff-ready spec, not code in this map.
  - **Trust level (b)** = home-hosted, invite-gated; real server-side
    credential verification, not public-internet-grade. (Refined 2026-09-13:
    account **registration is self-serve** — the WireGuard tunnel (Phase 13) is
    the network gate, so only enrolled peers can reach the server to register.)
  - **Domain model** = User (person) → Account (credential) → owns N Characters
    (persistent persona) → a selected Character is instantiated as the existing
    Player. (Formalized + reconciled with CONTEXT.md by
    [01 — Domain model](issues/01-domain-model-account-character-player.md).)
  - **Persistence** = this map decides the account/character persistence
    *model*; the SQLite storage-engine *build* is a downstream slice sharing
    infra with Phase 9 (Canon persistence). This deliberately breaks today's
    "nothing is persisted" invariant for the first time.
  - **Vessel seam** = character creation is scoped to name + cosmetic + a
    forward-compatible data model that can carry vessel state later; actual
    initial six-node vessel allocation is coordinated with Phase 12, not
    finalized here.
- Standing requirement (matches sibling maps): every implementation slice from
  this map follows the repo's SDD/BDD/TDD workflow (public-seam failing test
  first, unit + GUT integration tests, regression tests for safety invariants)
  with bounded telemetry built in from the start, reusing CLAUDE.md's
  "Telemetry And Andon Signals" seam.

## Decisions so far

> **Status: COMPLETE** — all six tickets resolved 2026-09-13. User-accepted
> forks: self-serve registration behind the WireGuard tunnel gate, 5 Characters
> per Account, globally-unique names, soft delete, and a new Phase 14. The
> consolidated handoff-ready spec is [spec.md](spec.md); implementation consumes
> the Wave 4 shared SQLite foundation.

<!-- one line per closed ticket; zoom the link for detail -->

- [01 — Domain model](issues/01-domain-model-account-character-player.md): User
  is informal; **Account** (opaque `account_id`) is the modelled root, owning up
  to 5 **Characters** (opaque `character_id`, globally-unique name); the Identity
  gate retires into the Account login + Character select flow; CONTEXT.md now
  carries Account and Character as canonical terms.
- [02 — Godot 4 password hashing](issues/02-research-godot-password-hashing.md):
  Godot 4 has no native PBKDF2 / bcrypt / argon2 and no SHA-512 — recommend a
  manual PBKDF2-HMAC-SHA256 (16-byte per-account CSPRNG salt, 32-byte derived
  key, stored with algo + iterations), verified via `Crypto.constant_time_compare`
  off the main thread; iterations tuned below OWASP's 600k, acceptable only at
  this home-hosted / invite-gated trust level.
- [03 — Godot 4 persistence / SQLite](issues/03-research-godot-persistence-sqlite.md):
  Recommend one shared server-owned SQLite engine via the MIT `godot-sqlite`
  GDExtension (headless-supported, tracks Godot 4.x), atomic via `BEGIN`/`COMMIT`
  + WAL + `PRAGMA user_version` fail-closed, in `user://`, parameter-bound
  queries only; write-temp-then-`DirAccess.rename` flat file is an atomic
  zero-dependency interim, not the destination; share ONE mechanism with Phase 9
  Canon.
- [04 — Authentication & session](issues/04-authentication-and-session-model.md):
  username + password (PBKDF2-HMAC-SHA256, off-thread constant-time verify);
  **self-serve registration** behind the WireGuard tunnel gate; auth is the
  first post-connect RPC before any Character/Player; opaque in-memory session
  bound to the peer; full re-auth on reconnect; the login screen replaces
  `identity_gate`.
- [05 — Character data model](issues/05-character-data-model-and-lifecycle.md):
  versioned `CharacterRecord` (schema_version, opaque ids, globally-unique name
  3–20, cosmetic, timestamps, soft-`deleted`, forward-compatible `vessel_seam`);
  max 5 per Account; soft delete keeps the name reserved; no rename in v1; the
  server owns ids/creation/uniqueness.
- [06 — Account/Character persistence](issues/06-account-character-persistence-design.md):
  one shared server-owned `godot-sqlite` engine (WAL, `user_version` fail-closed,
  parameter-bound), `accounts` + `characters` tables with a partial unique name
  index WHERE not deleted, atomic create/delete, server-only handle, bounded
  client DTOs; shares ONE mechanism with Phase 9; the downstream Wave 4 slice
  builds the engine.

## Specified in the handoff spec

The items below graduated from the decisions above and are now specified in
[spec.md](spec.md), ready to become implementation tickets:

- The client↔server RPC contract for auth and Character operations (register /
  login / list / create / select / delete).
- The screen flow and states (login/register → character select → character
  creation → enter world) replacing `client/identity_gate.tscn`.
- The Character → Player instantiation seam (a selected Character binds to
  `server/server_player_state.gd`'s `start_for_peer`).
- Enrollment = self-serve registration; session = in-memory per connection with
  full re-auth on reconnect; tracker placement = a new **Phase 14**.

## Deferred to implementation / later phases

- The concrete character-select / character-creation screen visual design and
  the cosmetic-option catalog (bounded by the Character data model; authored in
  the first UI slice).
- Initial six-node vessel starting values / allocation (Phase 12; only the
  forward-compatible `vessel_seam` is designed here).
- The `godot-sqlite` engine build, migrations, and repositories (the Wave 4
  shared SQLite foundation slice, shared with Phase 9 Canon).

## Out of scope

- Public-internet-grade authentication: email verification, password
  reset/recovery, OAuth / social login, MFA, CAPTCHA, and anti-abuse rate
  limiting (trust level is home-hosted, invite-gated).
- Payment, billing, or any monetization identity.
- The SQLite storage-engine implementation itself — Phase 9's build; this map
  decides the persistence *model* and hands off the engine
  ([P-011](../../docs/FEATURE-LIST.md#p-011-canonical-history-archive) area).
- Finalizing initial six-node vessel starting values / allocation rules — Phase
  12's own effort; this map only designs the forward-compatible seam.
- Production account administration, moderation, or ban tooling.
- Cross-server or cloud identity federation.
