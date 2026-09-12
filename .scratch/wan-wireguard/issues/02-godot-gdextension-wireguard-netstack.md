# 02 - Godot GDExtension WireGuard Netstack Prototype

Status: resolved
Type: prototype
Blocked by: 01

## Question

Can a C++/Rust/Go GDExtension compile `wireguard-go` in netstack mode for Godot 4.3 (Windows x64 and Linux x64) without requiring OS admin privileges, wintun installation, or root access?

## Answer

Yes. Build a Go C-shared library (`libwgnetstack.so` / `wgnetstack.dll`) loaded via CFFI/GDExtension. On startup, it accepts client credentials, initializes `netstack`, opens a local UDP socket on `127.0.0.1:<ephemeral_port>`, and returns the port for `ENetMultiplayerPeer.create_client("127.0.0.1", local_port)`. Runs completely in unprivileged userspace on Windows and Linux.
