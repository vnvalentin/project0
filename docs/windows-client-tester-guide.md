# Project0 Windows Client — Tester Guide

This guide is for a tester who has received a `Project0-client-windows-x64-<version>.zip`
file and a Linux server address, and wants to connect. It assumes no Godot
editor, no access to the source repository or Linux network share, and no
gameplay configuration beyond the server address.

## What's in the package

Extracting the ZIP produces a single folder,
`Project0-client-windows-x64-<version>/`, containing only:

- `Project0.exe` — the client executable.
- `Project0.pck` — the packaged client scenes and scripts.

There is no installer, no editor, no server files, no Ollama or SQLite
components, and no credentials. This package only replays the same identity
gate, movement, and networking behavior already validated on the development
build; it adds no new gameplay.

The portable client ZIP is the primary distribution. The optional Project0
launcher is a separate updater/bootstrapper around the same `Project0.exe` and
`Project0.pck` payload. Release launchers should be Authenticode-signed;
unsigned local builds may trigger Windows SmartScreen or antivirus reputation
warnings because the launcher downloads updates and starts a child process.

## 1. Extract the package

Right-click the ZIP file and choose **Extract All...** (or use any archive
tool), and pick a destination folder such as `Documents\Project0`. Do not run
the client directly from inside the ZIP — extract it first.

## 2. LAN prerequisites

- Your Windows machine and the Linux server must be on the same local
  network (e.g. the same home Wi-Fi/router), or otherwise able to reach each
  other directly. This package does not support internet-wide matchmaking or
  NAT traversal.
- You need the server's LAN IP address (e.g. `192.168.1.50`) and port
  (`9999` unless the person running the server tells you otherwise).
- The server operator must have started the server bound to that LAN address
  and opened port 9999 to inbound connections if their firewall blocks it by
  default. That step happens on their machine, not yours.

## 3. Configure the server address

The client has no in-game settings screen for this yet — the server address
is supplied the same way the development build already supports, using
either of the following (pick one):

**Option A — command-line argument** (recommended: create a shortcut once,
reuse it every time):

1. Right-click `Project0.exe` and choose **Create shortcut**.
2. Right-click the new shortcut, choose **Properties**.
3. In the **Target** field, add `--server-host=<server LAN IP>` after the
   existing path, for example:
   ```
   "C:\Users\you\Documents\Project0\Project0.exe" --server-host=192.168.1.50
   ```
4. Click **OK**, then double-click the shortcut to launch.

**Option B — environment variable** (useful if you'll always connect to the
same server):

1. Open **Start**, search for "Edit environment variables for your account",
   and open it.
2. Add a new user variable named `PROJECT0_SERVER_HOST` with the server's LAN
   IP as its value (e.g. `192.168.1.50`).
3. Launch `Project0.exe` normally (double-click).

If neither is set, the client defaults to `127.0.0.1` (localhost) and will
only find a server running on the same Windows machine — this is the same
safe default the development build uses.

## 4. Launch and connect

1. Run `Project0.exe` (directly or via your configured shortcut).
2. At the identity gate, enter any display name and select **Enter**.
3. Watch the on-screen connection status label. It should progress:
   `Server: disconnected` → `Server: connecting` → `Server: connected: player spawned`.
4. Once connected, you should see two capsules: a red one you control
   directly with W/A/S/D, and a blue one that mirrors the server's
   authoritative position for your own connection.

## Expected connected status

`Server: connected: player spawned` is the expected success state. If you
see anything else after a few seconds:

- `Server: failed: connection refused` — the server isn't listening at the
  address/port you configured, or a firewall is blocking it. Confirm the
  server operator has started the server and the LAN IP is correct.
- Stuck on `Server: connecting` — the address may be unreachable (wrong
  subnet, VPN interference, or the server machine is off/asleep).
- Stuck on `Server: disconnected` — the client never attempted to connect;
  double-check the `--server-host=` argument or environment variable is
  spelled exactly as shown above.

## 5. Connecting over WAN (internet) instead of LAN

The same client and server also support connecting across the internet
(WAN), not just a shared local network. This still uses the same identity
gate and `--server-host=`/`PROJECT0_SERVER_HOST` mechanism described above —
WAN only changes which address you're given and what the server operator
must configure on their side.

### GUI Server Host field

The identity gate screen (where you enter your display name) also has a
**Server Host** field pre-filled with the resolved default. To connect over
WAN, clear it and type the server's public IP address or domain name (e.g.
`play.example.com` or `203.0.113.42`) before selecting **Enter**. This
overrides the CLI argument/environment variable for that session and does
not require a new shortcut.

### `--server-host=` argument

The same shortcut technique from Option A above works for WAN addresses —
just use the public IP or domain name instead of a LAN IP:

```
"C:\Users\you\Documents\Project0\Project0.exe" --server-host=play.example.com
```

### What the server operator needs to configure

For a tester to reach the server over WAN, the server operator must:

1. **Bind the server to all interfaces**, not just localhost/LAN, by
   launching with:
   ```
   godot --headless --path . -s server/server_main.gd -- --server-bind-address=0.0.0.0
   ```
   `0.0.0.0` tells the server to accept connections on any network
   interface, including the public one — not just `127.0.0.1` or a LAN IP.
2. **Forward UDP port 9999 on their router** to the internal LAN IP of the
   machine running the server, so inbound internet traffic reaches it.
3. **Allow the port through the host firewall** on the server machine. On a
   Linux server with `ufw`, that's:
   ```
   sudo ufw allow 9999/udp
   ```
4. **Share the correct address** with testers: their public IP or a domain
   name that resolves to it, plus a reminder that port 9999 must be
   forwarded/open.

### VPN alternative (Tailscale, etc.)

Router port forwarding and public firewall exposure aren't always available
or desirable. As an alternative, the server operator and testers can join a
shared VPN mesh such as [Tailscale](https://tailscale.com/) (or any
WireGuard-based VPN):

1. The server operator and each tester install the VPN client and join the
   same private network/tailnet.
2. The server operator starts the server bound to their VPN-assigned
   address (or `0.0.0.0`, which also covers the VPN interface) — no router
   port forwarding or public firewall rule is needed, since traffic only
   flows over the VPN tunnel.
3. Testers use the server's VPN-assigned IP or MagicDNS name (e.g.
   `100.x.y.z` or `serverhost.tailnet-name.ts.net`) as the `--server-host=`
   value or GUI Server Host field entry.

This keeps the connection off the public internet entirely while still
working across different physical networks, which is useful if opening a
router port isn't an option.

### Security note

Binding to `0.0.0.0` and forwarding a port exposes the server to
unauthenticated inbound connections from anyone who has the address, matching
the existing warning the server prints for any non-localhost bind. Prefer the
VPN option above when testers and the operator are comfortable installing
one; only forward the port on a router if you accept that tradeoff.

## What this package does not do

- No installer, no Start Menu entry, no auto-update, no code signing.
- No in-client settings UI for the server address (command line / environment
  variable only, matching the existing development mechanism).
- No matchmaking, authentication, or internet-wide server discovery — you
  must be given a specific LAN address by the server operator.
- No world generation, persistence, or gameplay beyond movement — this
  package only proves the existing identity/connection/movement slice runs
  standalone on Windows.
