Type: grilling
Status: unclaimed
Blocked by: 05

## Question

Decide **where the client fetches the patch bytes** and over what transport.
(Q3 fixed the server as the version *authority* but deliberately left the patch
*source* open.)

Resolve:

- **Options**: (a) HTTPS from a static host co-located with the game server;
  (b) over the existing WireGuard tunnel (`client/network_client.gd`,
  `native/wgnetstack/`); (c) streamed through the game server process itself as
  a file-transfer RPC. Weigh the trade-offs given the LAN / WAN / tunnel
  topologies in `shared/network_config.gd` and that the game transport is
  ENet/**UDP**, which is not built for bulk file transfer.
- **Endpoint discovery**: is the download URL/endpoint advertised by the server
  in the version handshake
  ([04](04-version-handshake-contract-and-mandatory-gate.md)), or fixed config?
- **Resumability** and where the download hands off to integrity verification
  ([07](07-integrity-and-trust.md)).

Depends on the patch unit ([05](05-patch-unit.md)). Feeds the integrity and the
consolidated-spec tickets.
