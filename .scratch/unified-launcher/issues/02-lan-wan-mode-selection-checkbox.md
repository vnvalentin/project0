# LAN/WAN mode selection: the "LAN" checkbox contract

Status: open
Assignee: (unassigned)
Type: grilling
Blocked by: (none)

## Question

Define exactly what the user-facing **"LAN" checkbox** means and changes.
Default is unchecked = WAN (WireGuard tunnel). Checked = LAN direct-connect,
only valid when the server is on the same network as the client.

Decide:

- **Where the checkbox lives**: launcher UI (the launcher currently has no GUI,
  only a console credential prompt) versus in-client. What minimal UI surface
  the unified launcher gains to present it.
- **What the choice toggles**, end to end: `PROJECT0_TUNNEL` on/off, the
  HTTPS-login vs ENet-login path (`client_https_login_enabled()` /
  `PROJECT0_CLIENT_HTTPS_LOGIN`), and target-host resolution
  (`resolve_client_target_host()` / `--server-host`).
- **How the choice is captured and remembered** across runs (persisted setting,
  last-used default), and the exact default on first run.
- **LAN target host entry**: how the LAN server address is supplied when the box
  is checked (field, remembered value, discovery).
- **Failure/edge behavior**: what happens if LAN is checked but no reachable
  LAN server is found, or if WAN is selected but enrollment/tunnel is
  unavailable. (Auto-probe is explicitly not the selector; it may only assist.)

## Required decision output

A precise mode contract: the checkbox's persisted state, the exact set of env
vars / args each mode produces, the host-entry rule, and the defined behavior
for the unreachable-server edge in each mode. This contract is the input the
onboarding and integration tickets build on.

## Answer

_(unresolved)_
