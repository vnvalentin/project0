Type: task
Status: unclaimed
Blocked by: 04, 05, 06, 07, 08

## Question

Assemble the decided contract into `.scratch/client-auto-update/spec.md` — a
handoff-ready, SDD/BDD-shaped spec (the effort's destination artifact), matching
the sibling [player-accounts spec](../../player-accounts/spec.md) in shape.

Cover:

- The **version identity** and the new CONTEXT.md terms.
- The **pre-auth version handshake** and the **mandatory gate** (contract,
  rejection enum, ordering vs auth).
- The **patch unit**, the **transport / source**, the **integrity / trust**
  model, and the **apply / restart / rollback** mechanism.
- The **public seams** (the `shared/` contract, the `server/server_main.gd`
  accept path, the `client/network_client.gd` connect path, and the updater),
  the **non-goals**, the fail-closed **safety invariants** (remote code
  delivery), the **validation commands**, and the **required test seams** per
  CLAUDE.md's "Required Test Seams" (normal patch, out-of-date refusal,
  tampered/unverifiable patch refused, interrupted-patch rollback, idempotent
  re-check).

Depends on every decision ticket
([04](04-version-handshake-contract-and-mandatory-gate.md),
[05](05-patch-unit.md),
[06](06-patch-transport-and-distribution-source.md),
[07](07-integrity-and-trust.md),
[08](08-apply-restart-and-rollback.md)). Ready to become implementation tickets.
