Type: grilling
Status: resolved

## Question

Formalize the canonical domain vocabulary this whole effort hangs on, and
reconcile it with `CONTEXT.md` — which currently tells us to **avoid** the terms
"account", "login", and "character".

Proposed four-layer model (from charting round 1, user-accepted starting point):

- **User** — the human person.
- **Account** — the persistent, authenticated credential a User logs in with.
- **Character** — a persistent, selectable persona owned by an Account (name,
  cosmetic/appearance, and a forward-compatible slot for future vessel state).
- **Player** — the existing in-world actor a selected Character is instantiated
  as (already defined in `CONTEXT.md`; unchanged).

Resolve:

- Is **User** a distinct modelled entity, or informal only (with Account as the
  modelled root)?
- **Identifiers**: what stably identifies an Account and a Character? (Opaque
  server-owned stable strings per CLAUDE.md's identifier rule.)
- **Multiplicity**: one Account owns N Characters (confirmed). Can a Character
  belong to more than one Account (expected: no)? Is a display name unique
  per-Account, globally unique, or non-unique?
- The relationship between the existing provisional **Identity gate** term and
  the new Account/login concept — does "Identity gate" retire, or become the
  Account login screen?
- **Update `CONTEXT.md`**: introduce Account and Character as canonical terms
  and revise the "Identity gate" / "Player" avoid-lists accordingly (using the
  `domain-modeling` skill's CONTEXT format).

This ticket blocks the authentication model and the Character data model, which
both depend on these definitions.

## Decision (2026-09-13, user-accepted)

- **User is informal; Account is the modelled root.** The human `User` is not a
  stored entity. The `Account` is the persistent, server-owned credential and
  the root of identity.
- **Identifiers** are opaque server-owned stable strings (CLAUDE.md):
  `account_id` and `character_id`. Clients never supply them.
- **Multiplicity**: one Account owns up to **5** Characters; a Character belongs
  to exactly one Account (no sharing). The Character **display name is globally
  unique** among non-deleted Characters, so a name denotes exactly one persona
  in-world.
- **Identity gate retires** into the new **Account login + Character select**
  flow (Phase 14). `PlayerIdentity` will hold an authenticated Account handle
  and the selected Character, not a raw display name.
- **CONTEXT.md updated**: `Account` and `Character` are now canonical terms; the
  `Identity gate` and `Player` entries were revised (Identity gate marked
  superseded; Player redefined as the in-world instantiation of a Character).

Unblocks 04 (authentication) and 05 (Character data model).
