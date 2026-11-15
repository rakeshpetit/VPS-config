#!/bin/bash
# Runs, as the unprivileged "pi" user:
#   - tailscaled in userspace mode (no TUN, no capabilities), joined to the
#     tailnet with Tailscale SSH enabled
#   - pi-web (session daemon + web server), bound to 127.0.0.1 only, published to
#     the tailnet over HTTPS by Tailscale Serve
# If any of the long-running processes exits, the container exits and Docker
# restarts it.
set -euo pipefail

SOCKET=/tmp/tailscaled.sock
AUTHKEY_FILE=/run/secrets/ts_authkey
PI_WEB_PORT=8504
ts() { tailscale --socket="$SOCKET" "$@"; }

pids=()
trap 'kill "${pids[@]}" 2>/dev/null || true; exit 0' TERM INT

tailscaled \
  --tun=userspace-networking \
  --state=/var/lib/tailscale/tailscaled.state \
  --socket="$SOCKET" &
pids+=($!)

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
ts up "${up_args[@]}"

# pi-web config is generated on every start so the tailnet hostname is never
# hard-coded. pi-web only answers requests whose Host header is this name.
dns_name=""
for _ in $(seq 1 15); do
  dns_name="$(ts status --json | jq -r '.Self.DNSName // empty' | sed 's/\.$//')"
  [ -n "$dns_name" ] && break
  sleep 1
done
export PI_WEB_CONFIG=/tmp/pi-web-config.json
export PI_WEB_PORT
if [ -n "$dns_name" ]; then
  jq -n --arg h "$dns_name" --argjson p "$PI_WEB_PORT" \
    '{host: "127.0.0.1", port: $p, hostAccess: {mode: "restricted", hosts: [$h]}}' > "$PI_WEB_CONFIG"
else
  echo "WARNING: no tailnet DNS name (is MagicDNS enabled?); pi-web host restriction not set" >&2
  jq -n --argjson p "$PI_WEB_PORT" '{host: "127.0.0.1", port: $p}' > "$PI_WEB_CONFIG"
fi

# Publish pi-web to the tailnet only (not Funnel). Never fatal: if HTTPS
# certificates are not enabled on the tailnet this fails and SSH keeps working.
if ! timeout 30 tailscale --socket="$SOCKET" serve --bg --https=443 "http://127.0.0.1:$PI_WEB_PORT"; then
  echo "WARNING: tailscale serve failed; enable HTTPS certificates in the Tailscale admin console (DNS page)" >&2
fi

# The session daemon starts the Pi sessions, so it gets the Agent Credentials.
# The web server does not need them.
/usr/local/bin/pi-web-wrapper /opt/pi/bin/pi-web-sessiond &
pids+=($!)
sleep 2
/opt/pi/bin/pi-web-server &
pids+=($!)

wait -n || true
echo "a managed process exited; stopping container" >&2
kill "${pids[@]}" 2>/dev/null || true
exit 1
