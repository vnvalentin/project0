Type: grilling
Status: open
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
