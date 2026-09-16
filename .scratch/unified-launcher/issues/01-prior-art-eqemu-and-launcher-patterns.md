# Prior-art research: EQEMU login server and online-game launcher/patcher patterns

Status: resolved
Assignee: research-subagent
Type: research
Blocked by: (none)

## Question

Surface the facts the launcher architecture waits on by studying established
prior art. Specifically gather, from high-trust primary sources:

- **EQEMU login server**: how it separates login/account authority from the
  world/zone servers, the account creation/registration model, the
  client<->login<->world handshake, and any server-list / "which server do I
  join" selection it exposes. What maps onto Project0's login-authority +
  assertion + game-server split, and what does not.
- **Online-game launcher/patcher patterns** (survey several, e.g. classic MMO
  launchers, open-source patchers): how they express a **version manifest**
  (file list + hashes/sizes + version id), how they deliver patches (full vs
  delta/binary-diff), how they verify **integrity/authenticity** (hash and/or
  signature), how they apply updates **atomically** with rollback, and how the
  launcher is kept separate from the game payload it patches.
- **Account onboarding in launchers**: how first-run login vs new-account
  registration is presented and where account creation happens (in-launcher,
  web, or out-of-band), and the abuse controls used on public registration.

## Required output

A findings document capturing the above as concrete, citable facts and the
one-or-two-line "what this implies for Project0" takeaway per area. Enough that
the manifest, patch-delivery, onboarding, and registration tickets can be
decided without re-researching. Link the document as an asset from this ticket.

## Answer

Findings captured in
[research/01-prior-art.md](../research/01-prior-art.md) (all claims traced to
primary sources: EQEmu `loginserver/` source; Sparkle, Squirrel, Tauri, and
itch/wharf updater docs; OWASP Authentication Cheat Sheet). Decision-relevant
takeaways:

- **EQEmu validates Project0's login/world split**, but its `ClientAuth.key` is
  an opaque back-channel-validated token, whereas Project0's HMAC assertion is
  self-verifying at the game server — keep that advantage. The reusable idea is
  the explicit **server-list -> select -> session-credential** handshake/UI
  sequence, which informs the LAN/WAN selection (ticket 02) and onboarding
  (ticket 05).
- **Production updaters sign a version manifest and verify before swap**
  (Squirrel `RELEASES`+SHA1, Sparkle appcast+EdDSA, Tauri `latest.json`+mandatory
  signature). Adopt a **signed manifest with per-file size+hash**; keep signing
  keys off the manifest host. Informs tickets 03/04/07.
- **Atomic apply = versioned staging dir + swap + retain N-1** (Squirrel keeps
  current+previous), launcher binary kept separate from the game payload.
  Informs ticket 04.
- **Delta/binary patching is a bandwidth optimization, not the trust boundary**
  (always gated by a base checksum); keep full-file replacement as the
  correctness fallback. Informs ticket 04.
- **Onboarding is a policy fork**: EQEmu gates account creation behind
  write-scoped API tokens (operator/web, not in-client), matching Project0's
  existing `mint-invite`; a public self-service `/register` instead requires the
  full OWASP set (non-enumerating responses, contact verification, per-account+IP
  rate limiting, bot mitigation) and would extend DT-009. Directly informs the
  registration decision (ticket 06).
