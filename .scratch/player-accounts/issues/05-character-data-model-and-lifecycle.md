Type: grilling
Status: open
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
