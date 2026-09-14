# Account and login service boundary

Status: resolved
Assignee: Copilot
Type: grilling
Blocked by: 01-runtime-boundary-and-container-adapter

## Question

What does a separate Account/login process own, and what validated session
assertion does it exchange with the authoritative game server? Decide identity
authority, registration/login flow, token/session lifetime, reconnect behavior,
Character lookup ownership, failure modes, and the prohibition on the game
server trusting client-supplied Account or Character identity.

## Required decision output

A bounded service contract that preserves server-authoritative world entry and
leaves current account/Character behavior migratable without a flag day.

## Resolution

The existing authentication implementation is the migration anchor and must
be reused rather than rewritten. The current `PasswordHasher`, worker-thread
PBKDF2 execution, bounded rejection outcomes, `AccountHandle`,
`AccountCharacterRepository`, `AuthService`, `CharacterService`, and
peer-bound `SessionRegistry` remain the behavior and security baseline.

The Account/login service becomes the sole authority for durable Accounts,
credentials, and Characters. The authoritative game server remains the sole
authority for live peer sessions, Player instantiation, world entry,
gameplay, Canon, and all gameplay outcomes.

Migration is compatibility-first:

1. Extract a narrow internal login interface from the existing `AuthService`
   and Character service without changing current RPC behavior.
2. Keep an in-process adapter that satisfies the interface and preserves the
   current tests and runtime lifecycle.
3. Add signed session assertion creation and validation.
4. Add a private authenticated-HTTPS login-service adapter implementing the
   same interface.
5. Move Account/Character persistence ownership to the login process only
   after compatibility, reconnect, expiry, and failure tests pass.
6. Retire the in-process repository only after rollback evidence exists.

The login flow is:

```text
Client -> Login interface: register/login
Login interface -> AccountHandle + account-only signed assertion
Client -> Login interface: Character operations
Login interface -> selected-character signed assertion
Client -> Game server: assertion
Game server -> validates assertion and ownership -> local peer session
```

The first assertion contains only the Account identity. Character selection
produces a refreshed assertion containing the selected Character. The client
may carry assertions but cannot create, modify, or promote their claims.

The assertion contract is versioned and bounded. It contains a session id,
account id, optional selected Character id, issuer, audience, issued-at time,
expiry time, and schema version. The game server rejects bad signatures,
unsupported versions, wrong issuer/audience, expired/future timestamps,
unknown Character ownership, and replayed or revoked session ids.

The game server keeps its local `SessionRegistry`: it binds the validated
external session to the live ENet peer and clears that binding on disconnect.
Reconnect requires a fresh valid assertion. No durable login session is
stored in the game server.

The private login transport is authenticated HTTPS on the internal/container
network. It is not exposed through the public WireGuard enrollment hostname,
and the game server does not share the login database directly.

## Acceptance evidence

The implementation route must preserve the current auth/Character tests while
adding contract tests for assertion issuance, validation, expiry, audience,
ownership, reconnect, replay, and login-service failure. During migration,
the in-process adapter must remain a working rollback path.

## Decision status

Resolved by user confirmation on 2026-09-14. No production files were changed
by this planning decision.
