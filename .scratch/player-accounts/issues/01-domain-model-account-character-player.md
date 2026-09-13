Type: grilling
Status: open

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
