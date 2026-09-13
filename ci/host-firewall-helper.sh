#!/usr/bin/env bash
#
# Idempotent host-side firewall lockdown for the Project0 game host
# (192.168.1.254), restricting UDP 9999 (the authoritative game port) to the
# WireGuard tunnel subnet 10.77.0.0/24, dropping all other sources.
#
# Delivered for Slice 028
# (docs/slices/028-wireguard-remote-access-infrastructure-foundation.md)
# against decision issue 05
# (.scratch/wan-wireguard/issues/05-host-firewall-lockdown-script.md).
#
# This script only ever touches udp dport 9999, via a dedicated P0_GAME
# iptables chain hooked into INPUT. It requires root (run with sudo) because
# it calls iptables directly.
#
# Usage:
#   sudo ci/host-firewall-helper.sh apply [--allow-lan]
#   sudo ci/host-firewall-helper.sh remove
#   ci/host-firewall-helper.sh status
#
# apply    Flush/recreate the P0_GAME chain and hook it into INPUT. Accepts
#          UDP 9999 from 10.77.0.0/24 (and, with --allow-lan, also from
#          192.168.1.0/24 for local dev bring-up), drops all other UDP 9999
#          traffic. Safe to re-run: idempotent.
# remove   Unhook and delete the P0_GAME chain, restoring pre-lockdown
#          behavior for UDP 9999 on this host.
# status   Print whether the chain is hooked into INPUT and list its rules.

set -euo pipefail

CHAIN="P0_GAME"
GAME_PORT="9999"
TUNNEL_SUBNET="10.77.0.0/24"
LAN_SUBNET="192.168.1.0/24"

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        echo "ERROR: this command requires root (run with sudo)" >&2
        exit 1
    fi
}

chain_exists() {
    iptables -n -L "${CHAIN}" >/dev/null 2>&1
}

input_jump_exists() {
    iptables -C INPUT -p udp --dport "${GAME_PORT}" -j "${CHAIN}" >/dev/null 2>&1
}

cmd_apply() {
    require_root
    local allow_lan="0"
    if [[ "${1:-}" == "--allow-lan" ]]; then
        allow_lan="1"
    fi

    if chain_exists; then
        iptables -F "${CHAIN}"
    else
        iptables -N "${CHAIN}"
    fi

    # Always allow loopback first so local (127.0.0.0/8) tests and same-host
    # clients on udp/9999 are never dropped by the lockdown.
    iptables -A "${CHAIN}" -s 127.0.0.0/8 -j ACCEPT
    iptables -A "${CHAIN}" -p udp --dport "${GAME_PORT}" -s "${TUNNEL_SUBNET}" -j ACCEPT
    if [[ "${allow_lan}" == "1" ]]; then
        iptables -A "${CHAIN}" -p udp --dport "${GAME_PORT}" -s "${LAN_SUBNET}" -j ACCEPT
    fi
    iptables -A "${CHAIN}" -p udp --dport "${GAME_PORT}" -j DROP

    if ! input_jump_exists; then
        iptables -I INPUT -p udp --dport "${GAME_PORT}" -j "${CHAIN}"
    fi

    echo "Applied: UDP ${GAME_PORT} restricted to ${TUNNEL_SUBNET}$( [[ ${allow_lan} == 1 ]] && echo " and ${LAN_SUBNET} (--allow-lan)" )."
}

cmd_remove() {
    require_root
    if input_jump_exists; then
        iptables -D INPUT -p udp --dport "${GAME_PORT}" -j "${CHAIN}"
    fi
    if chain_exists; then
        iptables -F "${CHAIN}"
        iptables -X "${CHAIN}"
    fi
    echo "Removed: P0_GAME chain and its INPUT hook deleted."
}

cmd_status() {
    if input_jump_exists; then
        echo "INPUT hook: present"
    else
        echo "INPUT hook: absent"
    fi
    if chain_exists; then
        echo "Chain ${CHAIN} rules:"
        iptables -n -L "${CHAIN}" -v
    else
        echo "Chain ${CHAIN}: absent"
    fi
}

main() {
    local subcommand="${1:-}"
    shift || true
    case "${subcommand}" in
        apply)
            cmd_apply "${1:-}"
            ;;
        remove)
            cmd_remove
            ;;
        status)
            cmd_status
            ;;
        *)
            echo "Usage: $0 {apply [--allow-lan]|remove|status}" >&2
            exit 1
            ;;
    esac
}

main "$@"
