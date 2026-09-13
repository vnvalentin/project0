Type: grilling
Status: resolved
Blocked by: 01

## Question

Define the Character value contract and its lifecycle operations.

Resolve:

- **Fields**: `character_id` (opaque server id), owning `account_id`, display
  name, cosmetic/appearance data (what, and how bounded), timestamps
  (created / last-played), and a forward-compatible slot for future six-node
  vessel state (designed as a seam; values deferred to Phase 12). Follow
  CLAUDE.md's versioned-contract rules (`schema_version`, finite/bounded fields)
  and match the `shared/combat_contracts.gd` / `sector_blueprint_schema.gd`
  style.
- **Limits**: maximum Characters per Account; name length / charset and the
  uniqueness rule (per-account vs global) — consistent with the domain-model
  ticket.
- **Lifecycle**: create, select, delete (soft vs hard), rename (allowed?). What
  is server-authoritative vs client-supplied — the client never supplies a
  `character_id` or trusted state; the server owns creation and ids.
- **Validation and rejection reasons** for create / select / delete, fail-closed.

Feeds the persistence-design, the client↔server contract, the screen-flow, and
the Character → Player seam decisions. Uses the domain-model decision
([01](01-domain-model-account-character-player.md)).

## Decision (2026-09-13, user-accepted)

A versioned `CharacterRecord` value contract (CLAUDE.md rules: `schema_version`,
finite/bounded fields, opaque ids, server-authoritative), in the
`shared/combat_contracts.gd` / `sector_blueprint_schema.gd` style:

- **Fields**: `schema_version`, `character_id` (opaque server id), `account_id`
  (owner), `display_name`, `cosmetic` (bounded typed dict), `created_at`,
  `last_played_at`, `deleted` (bool), and `vessel_seam` — a versioned, nullable,
  forward-compatible slot whose values are **deferred to Phase 12** (the seam
  exists now; the six-node allocation does not).
- **Limits**: **max 5 Characters per Account**; `display_name` is **globally
  unique among non-deleted Characters**, length 3–20, charset `[A-Za-z0-9 _-]`
  with no leading/trailing/double spaces.
- **Lifecycle**: `create` (server assigns `character_id` + timestamps, validates
  name + charset + uniqueness + the 5-cap), `select` (binds the Character to the
  session and sets `last_played_at`), `delete` (**soft** — sets `deleted`, retains
  the row; the name **stays reserved to that Account** so no one else can take
  it). **Rename is not in v1.**
- **Authority**: the server owns creation, ids, timestamps, and uniqueness; the
  client never supplies a `character_id` or trusted state — it sends only a
  requested name and cosmetic.
- **Rejection reasons** (fail-closed): `UNSUPPORTED_VERSION`, `MALFORMED`,
  `NAME_TAKEN`, `NAME_INVALID`, `CHARACTER_CAP_REACHED`, `NOT_OWNER`,
  `NO_SUCH_CHARACTER`, `ALREADY_DELETED`.

Feeds 06 (persistence), the client↔server contract, the screen flow, and the
Character → Player seam. Uses 01.
