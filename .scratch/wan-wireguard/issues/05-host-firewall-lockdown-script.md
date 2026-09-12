# 05 - Host Firewall Game Port Lockdown Script

Status: resolved
Type: task
Blocked by: 03

## Question

How will `ci/host-firewall-helper.sh` restrict game port 9999 on host `192.168.1.254` so it only accepts connections originating from the WireGuard subnet (`10.77.0.0/24`) and drops/rejects all untunneled LAN and public WAN attempts?

## Answer

Extend `ci/host-firewall-helper.sh` (or `iptables` / `DOCKER-USER` chain helper on host `192.168.1.254`) to add a rule: `iptables -A INPUT -p udp --dport 9999 -s 10.77.0.0/24 -j ACCEPT` followed by `iptables -A INPUT -p udp --dport 9999 -j DROP`. This ensures that even on the local physical network `192.168.1.0/24`, direct untunneled connections to game port 9999 are rejected, enforcing WireGuard tunnel authentication for all game traffic.
