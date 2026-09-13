Type: grilling
Status: resolved
Blocked by: 01, 02

## Question

Decide the authentication and session model at trust level (b) (home-hosted,
invite-gated; real server-side verification, no recovery / OAuth / MFA).

Resolve:

- **Credential type**: username + password (recommended) vs alternatives.
- **Where auth sits in the connection lifecycle**: the ENet client currently
  connects and then a Player spawns (`client/network_client.gd` /
  `server/server_main.gd`). Does the client submit credentials as the first
  authenticated RPC after connect, before any Player or Character is created?
  What does the server do on failure — reject/disconnect with a bounded reason
  enum, matching the repo's fail-closed contract style?
- **Session representation**: does the server issue an opaque session
  token/handle bound to the peer for the connection's lifetime? Is anything
  persisted, or is a session purely in-memory per connection?
- **Reconnect**: full re-auth on reconnect (recommended) vs a resumable session.
- **Relationship to `identity_gate` / `PlayerIdentity`**: does the login screen
  replace the identity gate, and what does the `PlayerIdentity` autoload hold
  now — an authenticated Account handle instead of a raw display name?

Uses the domain-model decision
([01](01-domain-model-account-character-player.md)) and the password-hashing
research ([02](02-research-godot-password-hashing.md)).

## Decision (2026-09-13, user-accepted)

- **Credential**: username + password. The server stores only a
  **PBKDF2-HMAC-SHA256** derivation (16-byte per-account CSPRNG salt, 32-byte
  derived key, stored with algorithm + iteration count), verified with
  `Crypto.constant_time_compare` off the main thread (ticket 02). No plaintext,
  no reversible secret.
- **Enrollment = self-serve registration** (user choice). A `register` request
  creates an Account when the username is free. This is safe at this trust level
  because the **WireGuard tunnel (Phase 13) is the network gate** — only enrolled
  peers can reach the server, and registration is self-serve *within* that
  boundary. No email verification, password recovery, OAuth, MFA, or CAPTCHA
  (out of scope).
- **Lifecycle placement**: after the ENet connection is established, the
  client's **first authenticated RPC** submits a `login` or `register` request
  **before any Character or Player exists**. On success the server issues an
  **opaque in-memory session handle bound to the peer** for the connection's
  lifetime; on failure it replies with a **bounded rejection reason** and
  disconnects. Nothing about the session is persisted.
- **Rejection reason enum** (fail-closed, bounded): `UNSUPPORTED_VERSION`,
  `MALFORMED`, `BAD_CREDENTIALS`, `USERNAME_TAKEN` (register), `ACCOUNT_LOCKED`
  (reserved), `ALREADY_AUTHENTICATED`.
- **Reconnect**: full re-auth (no resumable session).
- **Screen / autoload**: the login + register screen replaces
  `client/identity_gate.tscn`; `client/player_identity.gd` holds the
  authenticated Account handle and the selected Character instead of a raw
  display name.

Uses 01 (domain) and 02 (hashing). Feeds the client↔server contract and the
screen flow.
