#!/bin/bash
# Usage (on the VPS, in /root/pi-agent): ./set-secret.sh github_token|openrouter_api_key|ts_authkey
# Prompts without echo, so the value never lands in shell history or process args.
set -euo pipefail

name="${1:?usage: $0 github_token|openrouter_api_key|ts_authkey}"
case "$name" in
  github_token|openrouter_api_key|ts_authkey) ;;
  *) echo "unknown secret: $name" >&2; exit 1 ;;
esac

dir="$(cd "$(dirname "$0")" && pwd)/secrets"
install -d -m 700 -o root -g root "$dir"

read -r -s -p "Value for $name: " value
echo
[ -n "$value" ] || { echo "empty value, aborting" >&2; exit 1; }

umask 077
tmp="$(mktemp -p "$dir")"
printf '%s' "$value" > "$tmp"
chown 1000:1000 "$tmp"
chmod 400 "$tmp"
mv -f "$tmp" "$dir/$name"
echo "wrote $dir/$name (owner 1000, mode 400)"
