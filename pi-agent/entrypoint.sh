#!/bin/bash
# Runs tailscaled in userspace mode (no TUN, no capabilities) as the unprivileged
# "pi" user and joins the tailnet with Tailscale SSH enabled.
set -euo pipefail

SOCKET=/tmp/tailscaled.sock
AUTHKEY_FILE=/run/secrets/ts_authkey

tailscaled \
  --tun=userspace-networking \
  --state=/var/lib/tailscale/tailscaled.state \
  --socket="$SOCKET" &
TS_PID=$!

for _ in $(seq 1 30); do
  [ -S "$SOCKET" ] && break
  sleep 1
done

up_args=(--ssh --advertise-tags=tag:pi-agent --hostname=pi-agent --accept-dns=false)
# After the first join the node key lives in the pi-tailscale volume and the
# (single-use) auth key file may be empty.
if [ -s "$AUTHKEY_FILE" ]; then
  up_args+=(--auth-key="file:$AUTHKEY_FILE")
fi
tailscale --socket="$SOCKET" up "${up_args[@]}"

wait "$TS_PID"
