# 04 - Enrollment Service Invite System & OPNsense Peer API Integration

Status: resolved
Type: grilling
Blocked by: none

## Question

How should the HTTPS enrollment service at `enroll.valentin.vip` authenticate single-use invite codes, accept client public keys, allocate available `/32` IPs from `10.77.0.0/24`, invoke the OPNsense WireGuard API to register peers, and return client configuration safely?

## Answer

Deploy a lightweight FastAPI container behind OPNsense nginx reverse proxy (`https://enroll.valentin.vip`). Single-use invite codes authenticate redemption, create player records, allocate the next free `/32` IP from `10.77.0.0/24`, call OPNsense WireGuard API (`/api/wireguard/client/addClient` + `/api/wireguard/service/reconfigure`), and return the peer config bundle (server pubkey, endpoint `game.valentin.vip:51900`, assigned `/32`, split-tunnel `192.168.1.254/32`). Client private keys are generated client-side and never transmitted.
