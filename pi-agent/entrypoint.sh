#!/bin/bash
# Runs, as the unprivileged "pi" user:
#   - tailscaled in userspace mode (no TUN, no capabilities), joined to the
#     tailnet with Tailscale SSH enabled
#   - pi-web (agegr/pi-web), bound to 127.0.0.1 only, published to the tailnet
#     over HTTPS by Tailscale Serve
# If either long-running process exits, the container exits and Docker
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

# The tailnet hostname is read on every start so it is never hard-coded. pi-web
# answers only loopback Hosts plus the names in PI_WEB_ALLOWED_HOSTS (others get 403).
dns_name=""
for _ in $(seq 1 15); do
  dns_name="$(ts status --json | jq -r '.Self.DNSName // empty' | sed 's/\.$//')"
  [ -n "$dns_name" ] && break
  sleep 1
done
if [ -n "$dns_name" ]; then
  export PI_WEB_ALLOWED_HOSTS="$dns_name"
else
  echo "WARNING: no tailnet DNS name (is MagicDNS enabled?); the tailnet URL will be rejected by pi-web" >&2
fi
# No update checks and no browser. Idle sessions are shut down after pi-web's default
# 10 minutes (PI_WEB_IDLE_TIMEOUT_MS), which also frees memory under the 1 GiB limit.
export PI_WEB_SKIP_VERSION_CHECK=1 PI_WEB_NO_OPEN=1

# Publish pi-web to the tailnet only (not Funnel). Never fatal: if HTTPS
# certificates are not enabled on the tailnet this fails and SSH keeps working.
if ! timeout 30 tailscale --socket="$SOCKET" serve --bg --https=443 "http://127.0.0.1:$PI_WEB_PORT"; then
  echo "WARNING: tailscale serve failed; enable HTTPS certificates in the Tailscale admin console (DNS page)" >&2
fi

# pi-web runs the Pi sessions in-process, so it gets the Agent Credentials.
/usr/local/bin/pi-web-wrapper /opt/pi/bin/pi-web --hostname 127.0.0.1 --port "$PI_WEB_PORT" --no-open &
pids+=($!)

wait -n || true
echo "a managed process exited; stopping container" >&2
kill "${pids[@]}" 2>/dev/null || true
exit 1
