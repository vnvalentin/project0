# Player Accounts & Characters — Handoff-Ready Spec

Status: complete (2026-09-13). This is the destination artifact of the
[player-accounts map](map.md): a handoff-ready, SDD/BDD-shaped design consolidating
tickets 01–06. It is design, not code. Implementation follows as bounded
SDD/BDD/TDD slices (see [Implementation slices](#implementation-slices)) and
consumes the Wave 4 shared SQLite foundation. Governing authority:
[CLAUDE.md](../../CLAUDE.md), [CONTEXT.md](../../CONTEXT.md).

## Outcome

A person authenticates into Project0 under a persistent **Account**, sees their
roster of **Characters** on a character-select screen, creates a new Character
on a character-creation screen, and enters the world as the existing
server-authoritative **Player**. Trust level: home-hosted, reachable only over
the Phase 13 WireGuard tunnel; real server-side credential verification, no
public-internet-grade recovery/OAuth/MFA.

## Domain model (ticket 01)

- **User** — the human person; informal, not a stored entity.
- **Account** — the modelled root of identity: opaque `account_id`, unique
  username, salted PBKDF2 secret. Owns up to **5** Characters.
- **Character** — a persistent persona owned by exactly one Account: opaque
  `character_id`, **globally-unique** display name, cosmetic, timestamps,
  forward-compatible `vessel_seam`. Soft-deletable.
- **Player** — the existing in-world actor a **selected Character is
  instantiated as**. Unchanged authority model.

CONTEXT.md now carries Account and Character as canonical terms; the Identity
gate term is marked superseded.

## Versioned contracts (`shared/`, CLAUDE.md rules)

Pure, versioned, bounded, fail-closed value objects in the
`shared/combat_contracts.gd` / `shared/sector_blueprint_schema.gd` style. No
authority, no DB handle, no secrets.

- **`CharacterRecord`**: `schema_version`, `character_id`, `account_id`,
  `display_name`, `cosmetic` (bounded typed dict), `created_at`,
  `last_played_at`, `deleted` (bool), `vessel_seam` (versioned, nullable;
  values deferred to Phase 12).
- **`AccountHandle`** (client-facing DTO): `account_id` + `username` only —
  never the salt/hash.
- **Rejection enums** (bounded): auth — `UNSUPPORTED_VERSION`, `MALFORMED`,
  `BAD_CREDENTIALS`, `USERNAME_TAKEN`, `ACCOUNT_LOCKED` (reserved),
  `ALREADY_AUTHENTICATED`; character — `NAME_TAKEN`, `NAME_INVALID`,
  `CHARACTER_CAP_REACHED`, `NOT_OWNER`, `NO_SUCH_CHARACTER`, `ALREADY_DELETED`.

Validation: `display_name` length 3–20, charset `[A-Za-z0-9 _-]`, no
leading/trailing/double spaces; all numbers finite/bounded; unknown enum ⇒ reject.

## Authentication & session (ticket 04)

- **Credential**: username + password. Stored only as **PBKDF2-HMAC-SHA256**
  (16-byte CSPRNG salt, 32-byte key, stored with algorithm + iterations),
  verified with `Crypto.constant_time_compare` off the main thread.
- **Enrollment**: **self-serve registration**, safe because the WireGuard
  tunnel (Phase 13) is the network gate. No email/recovery/OAuth/MFA/CAPTCHA.
- **Lifecycle**: ENet connect → client's **first authenticated RPC** is
  `register` or `login`, **before any Character/Player**. Success ⇒ server binds
  an **opaque in-memory session** to the peer; failure ⇒ bounded reason +
  disconnect. Session is never persisted. Reconnect ⇒ full re-auth.
- **Replaces**: `client/identity_gate.tscn` (login/register screen);
  `client/player_identity.gd` holds the `AccountHandle` + selected Character.

## Character model & lifecycle (ticket 05)

- **Limits**: ≤ 5 per Account; name globally unique among non-deleted.
- **Operations**: `create` (server assigns id/timestamps; validates name +
  charset + uniqueness + cap), `select` (binds to session; sets
  `last_played_at`), `delete` (**soft**; name stays reserved to the Account).
  **No rename in v1.**
- **Authority**: server owns creation, ids, timestamps, uniqueness. Client sends
  only a requested name + cosmetic; never a `character_id` or trusted state.

## Persistence (ticket 06)

- **One shared server-owned `godot-sqlite` engine** (`user://`, WAL,
  `PRAGMA user_version` fail-closed, parameter-bound) — the **same mechanism
  Phase 9 Canon uses**, separate tables.
- **Schema**:
  - `accounts(account_id PK, username UNIQUE NOT NULL, pbkdf2_salt, pbkdf2_hash,
    pbkdf2_iterations, created_at, schema_version)`
  - `characters(character_id PK, account_id NOT NULL REFERENCES accounts,
    display_name, cosmetic_json, vessel_json NULL, created_at, last_played_at,
    deleted INTEGER NOT NULL DEFAULT 0, schema_version)` + a **partial unique
    index on `display_name` WHERE deleted = 0** and an index on `account_id`.
- **Atomicity**: account/character create and soft-delete each in one
  `BEGIN`/`COMMIT`; no partial durable record on failure. Unsupported
  `user_version` fails closed.
- **Ownership**: DB handle server-only; `shared/` never holds it; the client
  receives only bounded DTOs. First deliberate break of the "nothing is
  persisted" invariant.

## Client↔server RPC contract

All authority RPCs, versioned, fail-closed, server-authoritative outcomes:

| Direction | Message | Payload → Result |
| --- | --- | --- |
| C→S | `register` | username, password → `AccountHandle` \| reason |
| C→S | `login` | username, password → `AccountHandle` \| reason |
| C→S | `list_characters` | (session) → `CharacterRecord[]` (client DTOs) |
| C→S | `create_character` | name, cosmetic → `CharacterRecord` \| reason |
| C→S | `select_character` | character_id → ack (world entry) \| reason |
| C→S | `delete_character` | character_id → ack \| reason |
| S→C | `auth_result` / `character_result` | outcome + bounded reason enum |

Every C→S message requires a live session except `register`/`login`. Duplicate/
malformed/out-of-order requests are rejected with a bounded reason and have no
side effect.

## Screen flow

`login/register` → `character select` (roster + create/delete) → `character
creation` (name + cosmetic) → **enter world**. Replaces the identity gate as the
pre-gameplay flow.

## Character → Player instantiation seam

On `select_character`, the server binds the chosen `CharacterRecord` to the
peer's session and instantiates the Player through the existing
`server/server_player_state.gd` `start_for_peer` seam — passing Character
identity/cosmetic instead of a raw display name. Movement/combat authority is
unchanged.

## Integration constraints

- One SQLite engine shared with Phase 9 Canon (build once — Wave 4).
- `vessel_seam` is forward-compatible with the Phase 12 six-node vessel.
- Auth slots into the existing `client/network_client.gd` /
  `server/server_main.gd` ENet connect lifecycle.
- Bounded telemetry per CLAUDE.md ("Telemetry And Andon Signals") from the start.

## Tracker placement

New **Phase 14 — Player accounts and characters**; a new feature record
(next free `F-<n>`). Exit gate: a person registers/logs in over the tunnel,
manages up to 5 Characters durably across restarts, and enters the world as the
selected Character, all server-authoritative and fail-closed.

## Implementation slices

Test-first (public-seam failing test first), each independently shippable:

1. **Shared account/character contracts** — `CharacterRecord`, `AccountHandle`,
   rejection enums, validation. Pure, unit-tested; no persistence.
2. **Wave 4 shared SQLite foundation** (shared with Phase 9) — `godot-sqlite`
   engine, WAL, `user_version` migrations, a server-only repository seam. The
   linchpin dependency.
3. **Account auth + session (server)** — register/login RPC, PBKDF2 hashing,
   in-memory session, fail-closed reject. Consumes 1 + 2.
4. **Character CRUD (server)** — create/select/delete with the 5-cap, global
   name uniqueness, soft delete. Consumes 1 + 2 + 3.
5. **Client login/register + character select/create screens** replacing the
   identity gate. Consumes the RPC contract.
6. **Character → Player instantiation** — `start_for_peer` binds the selected
   Character. End-to-end.

## Out of scope

Email verification, password recovery, OAuth/social, MFA, CAPTCHA, anti-abuse
rate limiting; payment/billing identity; production admin/moderation/ban tooling;
cross-server/cloud federation; final vessel starting values (Phase 12).
