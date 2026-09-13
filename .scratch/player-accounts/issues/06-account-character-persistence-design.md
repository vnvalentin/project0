Type: grilling
Status: open
Blocked by: 03, 05

## Question

Decide how Accounts and Characters are persisted durably and server-owned,
deliberately breaking today's "nothing is persisted" invariant for the first
time.

Resolve:

- **Storage model**: given the persistence research, what store backs Accounts
  and Characters (e.g. SQLite via GDExtension, or a bounded file store as an
  interim), and how it relates to Phase 9's Canon SQLite store — share one
  server-owned mechanism vs keep them separate.
- **Data shape at rest**: records for Account (id, username, salted derived
  credential, created-at) and Character (id, account_id, name, cosmetic, vessel
  seam, timestamps); ownership and referential integrity.
- **Transaction / atomicity boundary**: atomic account creation, atomic
  character create/delete, and restart recovery — satisfying CLAUDE.md's
  "atomic, no partial durable record" and "fail closed on unsupported versions"
  rules.
- **Server-only ownership**: the store handle never leaves the server
  (CLAUDE.md's shared-code rule); the client only sees replicated, bounded
  results.
- **Boundary handoff**: what this map DECIDES vs what the downstream persistence
  slice (shared with Phase 9) BUILDS.

Uses the persistence research
([03](03-research-godot-persistence-sqlite.md)) and the Character data model
([05](05-character-data-model-and-lifecycle.md)).
