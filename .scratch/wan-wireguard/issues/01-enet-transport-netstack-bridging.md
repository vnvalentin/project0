# 01 - ENet Transport Netstack Bridging Architecture

Status: resolved
Type: research
Blocked by: none

## Question

How can Godot 4.3's `ENetMultiplayerPeer` route UDP packets through `wireguard-go` userspace netstack without requiring Godot engine modifications or elevated OS privileges?

Evaluate:
1. In-process local loopback UDP bridge: client binds ENet to `127.0.0.1:<local_port>`, and a thread/GDExtension forwards raw UDP packets between loopback and `wireguard-go netstack.DialUDP("udp", nil, "192.168.1.254:9999")`.
2. Custom `PacketPeer` / `MultiplayerPeerExtension` GDExtension wrapping netstack directly.

## Answer

Adopt **Option 1 (In-Process Local Loopback UDP Socket Bridge)**.
- **Why**: Zero modification to Godot engine core or ENet protocols. Performance overhead is <0.1ms (1 loopback socket hop), which is imperceptible relative to WAN latency (~20–100ms) or 60Hz physics ticks (16.6ms).
- **Execution**: The GDExtension exposes `wireguard-go` + gVisor `netstack` in userspace. It binds a local UDP socket on `127.0.0.1:<ephemeral_port>` and forwards packets bidirectionally between loopback and `netstack.DialUDP("udp", nil, "192.168.1.254:9999")`.
- **Client Integration**: GDScript calls `ENetMultiplayerPeer.create_client("127.0.0.1", local_port)` unchanged. Zero OS admin rights or Wintun/TUN drivers needed on Windows/Linux.
