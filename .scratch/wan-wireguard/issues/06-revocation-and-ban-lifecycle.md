# 06 - Peer Revocation and Ban Lifecycle Protocol

Status: resolved
Type: grilling
Blocked by: 04

## Question

What is the exact revocation workflow when an operator bans an account, including removing the peer via the OPNsense WireGuard API, reclaiming its allocated `/32` IP, and ensuring tunnel tear-down within one keepalive interval?

## Answer

When an account is revoked/banned:
1. Enrollment service marks the account as revoked in its local database and releases its allocated `/32` IP back to the IP pool.
2. Enrollment service calls OPNsense API `/api/wireguard/client/delClient/<uuid>` followed by `/api/wireguard/service/reconfigure`.
3. OPNsense drops the peer from `wg0`. Within 1 keepalive interval (~25s max), handshakes fail and the client's tunnel is terminated.
4. Idempotent re-enrollment logic allows an existing account to re-enroll with a new public key by updating the existing peer UUID rather than leaking stale peers.
