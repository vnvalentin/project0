Type: grilling
Status: unclaimed
Blocked by: 01

## Question

Design the **pre-auth version-handshake** contract by which the game server
advertises the required client build version and refuses out-of-date clients
(the mandatory gate).

Resolve:

- **Message / RPC shape**: after the ENet connection is established, does the
  client send its build version as the **first** message (before the
  player-accounts login/register RPC) and the server reply `ACCEPTED` or a
  bounded rejection? Or does the server advertise the required version first and
  the client self-checks? Model it in `shared/` like the existing versioned
  contracts (`shared/network_config.gd`, `shared/combat_contracts.gd`,
  `shared/sector_blueprint_schema.gd`).
- **Bounded rejection reason enum** (fail-closed): e.g. `CLIENT_OUTDATED`,
  `UNSUPPORTED_VERSION`, `MALFORMED` — mirroring the repo's fail-closed
  contract style.
- **Ordering vs auth**: the version gate MUST pass before login/register.
  Reconcile with [player-accounts](../../player-accounts/map.md) (auth is the
  first *authenticated* RPC). Does the version handshake become **the** new
  first RPC, ahead of auth?
- **What a rejection carries** so the client can self-patch: the required
  version plus how to obtain it (a pointer handed to the transport ticket).
- **Where it lives**: the `shared/` contract, the `server/server_main.gd`
  accept path, and the `client/network_client.gd` connect path.

Depends on the version identity ([01](01-domain-model-and-version-identity.md)).
Feeds the consolidated spec.
