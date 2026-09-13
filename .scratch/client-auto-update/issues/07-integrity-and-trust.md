Type: grilling
Status: unclaimed
Blocked by: 01, 03, 05

## Question

**(Security linchpin.)** Decide how a downloaded patch is verified for
**integrity and authenticity** BEFORE it is loaded or executed — because
auto-update is remote code delivery, and a wrong answer here is arbitrary code
execution on every tester's machine.

Resolve:

- **What is hashed and what is signed**: a SHA-256 over the patch unit, and a
  signed **update manifest** that binds version to that hash? What key ships in
  the client (a bundled trusted **public key**), and how is it protected from
  being swapped by the same attacker who could swap the patch?
- **Trust anchor at this level**: home-hosted / invite-gated, no public
  code-signing certificate. Is an **RSA-signed manifest** (native Godot
  `Crypto.verify`, per research
  [03](03-research-godot-integrity-signing-primitives.md)) sufficient? Note
  explicitly why **TLS/HTTPS alone is not** (server compromise, LAN MITM).
- **Fail-closed behavior**: an unverifiable or mismatched patch is refused and
  **never applied**; where verification sits in the flow (after download, before
  apply) and what the failure path does (abort, keep the prior known-good,
  emit telemetry).

Depends on version identity
([01](01-domain-model-and-version-identity.md)), the crypto-primitives research
([03](03-research-godot-integrity-signing-primitives.md)), and the patch unit
([05](05-patch-unit.md)). Feeds apply/restart/rollback and the spec.
