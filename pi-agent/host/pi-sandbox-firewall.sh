#!/bin/bash
# Blocks the Pi Sandbox from reaching the Host and private networks while
# leaving general internet egress open. Idempotent.
#   pi-sandbox-firewall.sh apply | remove | status
set -euo pipefail

SUBNET=172.28.0.0/24
PRIVATE=(10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 100.64.0.0/10 169.254.0.0/16)

ensure() { # ensure <chain> <position> <rule...>
  local chain=$1 pos=$2; shift 2
  iptables -C "$chain" "$@" 2>/dev/null || iptables -I "$chain" "$pos" "$@"
}
drop() {
  iptables -C "$@" 2>/dev/null && iptables -D "$@" || true
}

case "${1:-}" in
  apply)
    # Traffic to the Host itself (its public IP, the bridge gateway) is INPUT, not FORWARD.
    ensure INPUT 1 -s "$SUBNET" -m conntrack --ctstate NEW -j DROP
    # Traffic to other containers / private ranges / cloud metadata is FORWARD.
    for net in "${PRIVATE[@]}"; do
      ensure DOCKER-USER 1 -s "$SUBNET" -d "$net" -j DROP
    done
    ;;
  remove)
    drop INPUT -s "$SUBNET" -m conntrack --ctstate NEW -j DROP
    for net in "${PRIVATE[@]}"; do
      drop DOCKER-USER -s "$SUBNET" -d "$net" -j DROP
    done
    ;;
  status)
    iptables -S INPUT | grep "$SUBNET" || echo "INPUT: no sandbox rule"
    iptables -S DOCKER-USER | grep "$SUBNET" || echo "DOCKER-USER: no sandbox rules"
    ;;
  *) echo "usage: $0 apply|remove|status" >&2; exit 1 ;;
esac
