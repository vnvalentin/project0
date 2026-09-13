Type: grilling
Status: unclaimed

## Question

Establish the canonical vocabulary and the **authoritative version identity**
for client auto-update. This is the root of the map; every downstream ticket
consumes it.

Resolve:

- **Vocabulary** (with `domain-modeling`): define **client build version**,
  **update manifest**, **patch**, and **version handshake** as CONTEXT.md
  canonical terms, and keep them explicitly **distinct** from the existing
  `schema_version` / `tuning_version` data-contract terms in
  [CLAUDE.md](../../../CLAUDE.md). CONTEXT.md carries none of these yet.
- **What the version actually is**: is the authoritative "are you up to date?"
  identity a human-readable **semver string** (extending today's
  `PROJECT0_CLIENT_VERSION`, default `0.6.0`, currently baked only into the ZIP
  *name*), an **opaque server-issued build id**, and/or a **content hash of the
  `.pck`**? Decide which one is authoritative for the comparison and which are
  informational.
- **Runtime self-knowledge**: where is the version stamped into the packaged
  client so the *running* client can read its own version at runtime? Today
  `PROJECT0_CLIENT_VERSION` lives only in the package name — insufficient.
  Options: a bundled version resource inside the pck, the exe
  file/product-version metadata (`application/file_version` in
  `export_presets.cfg`), or a generated const compiled into the pck.
- **Server-side required version**: how does the server know the version it
  advertises — a config/tuning value it owns and can bump per release?

Output: the term definitions (ready to fold into CONTEXT.md) and the decided
version-identity model. Feeds every other ticket, especially the version
handshake, the patch unit, and integrity.
