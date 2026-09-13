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
    credential verification, not public-internet-grade.
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

<!-- one line per closed ticket; zoom the link for detail -->

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

## Not yet specified

- The client↔server message/RPC contract for auth and character operations
  (login, list / create / select / delete Character) — graduates once the
  authentication model and the Character data model are decided.
- The screen flow and UI states (login → character select → character creation
  → enter world), and how they replace or evolve `identity_gate.tscn` —
  graduates once auth and the Character data model are decided.
- The character-select and character-creation screen designs (fields shown,
  validation, cosmetic options) — graduates from the Character data model.
- The Character → Player instantiation seam (how a selected Character binds to
  `server_player_state.gd`'s `start_for_peer`) — graduates from the Character
  data model.
- Account enrollment / registration: self-serve registration vs invite-code
  gated (Phase 13 tie-in) vs admin-provisioned — graduates from the
  authentication model.
- Session persistence and reconnect behavior (does a session survive a client
  restart; how re-auth works on reconnect) — graduates from the authentication
  model.
- Phase and tracker placement (a new phase vs folding into Phase 9 / 12 / 13;
  feature / debt / slice indexing) — graduates once the core design decisions
  exist.

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
